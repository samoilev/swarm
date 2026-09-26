import Foundation

public enum MergeMatchKind: String, Codable, Sendable {
    case stableID
    case sharedTreeXref
    case heuristicSuggestion
}

public struct MergePersonMatch: Identifiable, Codable, Hashable, Sendable {
    public var id: String { "\(localPersonID.uuidString):\(incomingPersonID.uuidString)" }
    public let localPersonID: UUID
    public let incomingPersonID: UUID
    public let kind: MergeMatchKind
    public let reasons: [String]
}

public enum MergeFactChoice: String, Codable, CaseIterable, Sendable {
    case local
    case incoming
    case both
}

public struct MergeConflict: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let localPersonID: UUID
    public let incomingPersonID: UUID
    public let field: String
    public var choice: MergeFactChoice
}

public struct MergePreview {
    public let localTreeID: UUID
    public let incomingTree: FamilyTree
    public var automaticMatches: [MergePersonMatch]
    public var heuristicSuggestions: [MergePersonMatch]
    public var acceptedHeuristicMatchIDs: Set<String>
    public var conflicts: [MergeConflict]
    public var incomingOnlyPersonIDs: [UUID]

    public init(
        localTreeID: UUID,
        incomingTree: FamilyTree,
        automaticMatches: [MergePersonMatch],
        heuristicSuggestions: [MergePersonMatch],
        acceptedHeuristicMatchIDs: Set<String> = [],
        conflicts: [MergeConflict],
        incomingOnlyPersonIDs: [UUID]
    ) {
        self.localTreeID = localTreeID
        self.incomingTree = incomingTree
        self.automaticMatches = automaticMatches
        self.heuristicSuggestions = heuristicSuggestions
        self.acceptedHeuristicMatchIDs = acceptedHeuristicMatchIDs
        self.conflicts = conflicts
        self.incomingOnlyPersonIDs = incomingOnlyPersonIDs
    }

    /// The conflicts that actually apply: those belonging to an automatic match or to
    /// a suggestion the user accepted. Conflicts are generated for every candidate
    /// pair up front, so accepting a suggestion reviews its facts instead of taking
    /// the defaults, but an unaccepted pair must not clutter the sheet.
    public var activeConflicts: [MergeConflict] {
        let applied = Set(automaticMatches.map(\.id)).union(acceptedHeuristicMatchIDs)
        return conflicts.filter {
            applied.contains("\($0.localPersonID.uuidString):\($0.incomingPersonID.uuidString)")
        }
    }
}

public enum TreeMergeError: LocalizedError {
    case wrongDestination
    case snapshotFailed
    case attachmentMissing(String)

    public var errorDescription: String? {
        switch self {
        case .wrongDestination: L10n.tr("Этот список изменений подготовлен для другого дерева.")
        case .snapshotFailed: L10n.tr("Не удалось создать резервную копию перед объединением.")
        case let .attachmentMissing(name): L10n.tr("Файл вложения не найден: \(name).")
        }
    }
}

/// Local-only merge engine. Heuristic candidates are suggestions until their exact
/// match IDs are added to `acceptedHeuristicMatchIDs`; they are never applied silently.
/// Main-actor isolated because it drives the main-actor `TreeStore`; the pure
/// static duplicate-detection helpers stay nonisolated for `TreeWorkspaceIndexes`.
@MainActor
public final class TreeMergeEngine {
    private let store: TreeStore

    public init(store: TreeStore) {
        self.store = store
    }

    public func preview(local: FamilyTree, incoming: FamilyTree) -> MergePreview {
        var matchedLocal = Set<UUID>()
        var matchedIncoming = Set<UUID>()
        var automatic: [MergePersonMatch] = []

        for candidate in incoming.people {
            if let localPerson = local.people.first(where: { $0.id == candidate.id }) {
                automatic.append(MergePersonMatch(
                    localPersonID: localPerson.id,
                    incomingPersonID: candidate.id,
                    kind: .stableID,
                    reasons: [L10n.tr("совпадает _FTSID")]
                ))
                matchedLocal.insert(localPerson.id)
                matchedIncoming.insert(candidate.id)
            }
        }

        if local.id == incoming.id {
            for candidate in incoming.people where !matchedIncoming.contains(candidate.id) {
                guard let xref = candidate.gedcomXref,
                      let localPerson = local.people.first(where: { !matchedLocal.contains($0.id) && $0.gedcomXref == xref }) else { continue }
                automatic.append(MergePersonMatch(
                    localPersonID: localPerson.id,
                    incomingPersonID: candidate.id,
                    kind: .sharedTreeXref,
                    reasons: [L10n.tr("совпадают идентификаторы записи (xref) и дерева (_TREEID)")]
                ))
                matchedLocal.insert(localPerson.id)
                matchedIncoming.insert(candidate.id)
            }
        }

        // Bucket by the exact rule `heuristicReasons` requires (normalized name plus
        // birth year) instead of comparing every incoming person against every local
        // one: the pairwise scan rebuilt a FamilyIndex for both whole trees on each
        // pair, which stalled the sheet on trees of a few thousand people.
        var suggestions: [MergePersonMatch] = []
        var localBuckets: [String: [Person]] = [:]
        for localPerson in local.people where !matchedLocal.contains(localPerson.id) {
            guard let key = Self.candidateKey(localPerson) else { continue }
            localBuckets[key, default: []].append(localPerson)
        }
        if !localBuckets.isEmpty {
            let localIndex = FamilyIndex(tree: local)
            let incomingIndex = FamilyIndex(tree: incoming)
            for candidate in incoming.people where !matchedIncoming.contains(candidate.id) {
                guard let key = Self.candidateKey(candidate), let bucket = localBuckets[key] else { continue }
                for localPerson in bucket {
                    let reasons = Self.heuristicReasons(
                        localPerson,
                        candidate,
                        localIndex: localIndex,
                        incomingIndex: incomingIndex
                    )
                    if reasons.count >= 2 {
                        suggestions.append(MergePersonMatch(
                            localPersonID: localPerson.id,
                            incomingPersonID: candidate.id,
                            kind: .heuristicSuggestion,
                            reasons: reasons
                        ))
                    }
                }
            }
        }

        // Conflicts are generated for suggested pairs as well as automatic ones, so a
        // suggestion the user accepts is reviewed rather than silently taking the
        // defaults. Entries for pairs that stay unaccepted are inert: `mergePerson`
        // only reads the choices of the pair it is applying, and the sheet lists
        // `activeConflicts`.
        var conflicts: [MergeConflict] = []
        for match in automatic + suggestions {
            guard let left = local.person(byId: match.localPersonID),
                  let right = incoming.person(byId: match.incomingPersonID) else { continue }
            conflicts += factConflicts(local: left, incoming: right)
        }

        return MergePreview(
            localTreeID: local.id,
            incomingTree: incoming,
            automaticMatches: automatic,
            heuristicSuggestions: suggestions,
            conflicts: conflicts,
            incomingOnlyPersonIDs: incoming.people.filter { !matchedIncoming.contains($0.id) }.map(\.id)
        )
    }

    public func apply(_ preview: MergePreview, to local: FamilyTree) async throws -> SaveReceipt {
        guard preview.localTreeID == local.id else { throw TreeMergeError.wrongDestination }
        guard let before = try? local.deepCopy() else {
            throw TreeMergeError.snapshotFailed
        }

        _ = try store.createVerifiedBackup(for: local, label: "pre-merge")
        var preparedAttachments: [Attachment] = []
        do {
            var matches = preview.automaticMatches
            matches += preview.heuristicSuggestions.filter { preview.acceptedHeuristicMatchIDs.contains($0.id) }
            let incoming = preview.incomingTree
            // Two accepted suggestions can name the same incoming person (identical
            // name and birth year on two local records). Keep the first pairing
            // instead of trapping on a duplicate key halfway through the merge.
            var personMap: [UUID: UUID] = [:]
            matches = matches.filter { personMap.updateValue($0.localPersonID, forKey: $0.incomingPersonID) == nil }
            let sourceMap = mergeSources(from: incoming, into: local)
            var attachmentIDMap: [String: String] = [:]

            for match in matches {
                guard let left = local.person(byId: match.localPersonID),
                      let right = incoming.person(byId: match.incomingPersonID) else { continue }
                preparedAttachments += try mergeFiles(
                    from: right,
                    into: left,
                    localTree: local,
                    sourceMap: sourceMap,
                    attachmentIDMap: &attachmentIDMap
                )
                mergePerson(
                    right,
                    into: left,
                    sourceMap: sourceMap,
                    attachmentIDMap: attachmentIDMap,
                    conflicts: preview.conflicts
                )
            }

            for incomingPerson in incoming.people where personMap[incomingPerson.id] == nil {
                let copied = try clone(incomingPerson)
                let originalID = incomingPerson.id
                if local.people.contains(where: { $0.id == copied.id }) { copied.id = UUID() }
                personMap[originalID] = copied.id
                remapEvidence(in: copied, sourceMap: sourceMap)
                preparedAttachments += try stageFiles(
                    from: incomingPerson,
                    into: copied,
                    localTree: local,
                    attachmentIDMap: &attachmentIDMap
                )
                remapMediaIDs(in: copied, attachmentIDMap: attachmentIDMap)
                local.people.append(copied)
            }

            var existingUnionSignatures = Set(local.unions.map(unionSignature))
            var unionMap: [UUID: UUID] = [:]
            for incomingUnion in incoming.unions {
                let copied = try clone(incomingUnion)
                copied.id = local.unions.contains(where: { $0.id == copied.id }) ? UUID() : copied.id
                copied.partner1Id = copied.partner1Id.flatMap { personMap[$0] }
                copied.partner2Id = copied.partner2Id.flatMap { personMap[$0] }
                copied.childrenIds = copied.childrenIds.compactMap { personMap[$0] }
                remapEvidence(in: copied, sourceMap: sourceMap)
                remapMediaIDs(in: copied, attachmentIDMap: attachmentIDMap)
                let signature = unionSignature(copied)
                if let existing = local.unions.first(where: { unionSignature($0) == signature }) {
                    mergeUnion(copied, into: existing)
                    unionMap[incomingUnion.id] = existing.id
                } else if !existingUnionSignatures.contains(signature) {
                    local.unions.append(copied)
                    existingUnionSignatures.insert(signature)
                    unionMap[incomingUnion.id] = copied.id
                }
            }

            for link in incoming.parentLinks {
                guard let parentID = personMap[link.parentID], let childID = personMap[link.childID] else { continue }
                var copied = link
                copied.id = local.parentLinks.contains(where: { $0.id == copied.id }) ? UUID() : copied.id
                copied.parentID = parentID
                copied.childID = childID
                copied.unionID = link.unionID.flatMap { unionMap[$0] }
                copied.citations = remap(copied.citations, sourceMap: sourceMap)
                if let index = local.parentLinks.firstIndex(where: { $0.parentID == parentID && $0.childID == childID && $0.unionID == copied.unionID && $0.kind == copied.kind }) {
                    // Preserve a recorded doubt without adding a duplicate parent edge.
                    if copied.hasUncertainParentage { local.parentLinks[index].isUncertain = true }
                    local.parentLinks[index].citations = choose(
                        local.parentLinks[index].citations,
                        copied.citations,
                        choice: .both
                    )
                    if local.parentLinks[index].notes?.isEmpty != false { local.parentLinks[index].notes = copied.notes }
                } else {
                    local.parentLinks.append(copied)
                }
            }

            local.reconcileParentLinks()
            local.optimizeRoot()
            return try await store.saveTree(local)
        } catch {
            for attachment in preparedAttachments { store.discardPreparedAttachment(attachment, in: local) }
            restore(before, into: local)
            throw error
        }
    }

    /// Duplicate review uses the same conservative candidate rule as merge preview:
    /// matching normalized name and birth year plus at least one corroborating fact.
    public nonisolated static func duplicateSuggestions(in tree: FamilyTree) -> [DuplicateSuggestion] {
        var buckets: [String: [Person]] = [:]
        for person in tree.people {
            guard let year = person.event(ofKind: .birth)?.date?.year else { continue }
            let name = TreeWorkspaceIndexes.normalize(person.fullName)
            guard !name.isEmpty else { continue }
            buckets["\(name):\(year)", default: []].append(person)
        }
        var result: [DuplicateSuggestion] = []
        guard buckets.values.contains(where: { $0.count > 1 }) else { return [] }
        // One index for the whole tree, not one per candidate pair.
        let index = FamilyIndex(tree: tree)
        for candidates in buckets.values where candidates.count > 1 {
            for firstIndex in candidates.indices {
                for secondIndex in candidates.indices where secondIndex > firstIndex {
                    let first = candidates[firstIndex]
                    let second = candidates[secondIndex]
                    let reasons = heuristicReasons(first, second, localIndex: index, incomingIndex: index)
                    if reasons.count >= 2 {
                        result.append(DuplicateSuggestion(
                            firstPersonID: first.id,
                            secondPersonID: second.id,
                            reasons: reasons
                        ))
                    }
                }
            }
        }
        return result
    }

    /// Bucket key for the candidate rule: two people can only be suggested as the
    /// same person when their normalized names and birth years both match.
    private nonisolated static func candidateKey(_ person: Person) -> String? {
        let name = TreeWorkspaceIndexes.normalize(person.fullName)
        guard !name.isEmpty, let year = person.event(ofKind: .birth)?.date?.year else { return nil }
        return "\(name):\(year)"
    }

    private nonisolated static func heuristicReasons(
        _ localPerson: Person,
        _ incomingPerson: Person,
        localIndex: FamilyIndex,
        incomingIndex: FamilyIndex
    ) -> [String] {
        let leftName = TreeWorkspaceIndexes.normalize(localPerson.fullName)
        let rightName = TreeWorkspaceIndexes.normalize(incomingPerson.fullName)
        guard !leftName.isEmpty, leftName == rightName,
              let leftBirth = localPerson.event(ofKind: .birth)?.date?.year,
              leftBirth == incomingPerson.event(ofKind: .birth)?.date?.year else { return [] }
        var reasons = [L10n.tr("совпадают имя и год рождения")]

        let leftPlaces = Set(localPerson.events.compactMap { $0.place.map { TreeWorkspaceIndexes.normalize($0.displayName) } })
        let rightPlaces = Set(incomingPerson.events.compactMap { $0.place.map { TreeWorkspaceIndexes.normalize($0.displayName) } })
        if !leftPlaces.intersection(rightPlaces).isEmpty { reasons.append(L10n.tr("совпадает место")) }
        if let death = localPerson.event(ofKind: .death)?.date?.year,
           death == incomingPerson.event(ofKind: .death)?.date?.year { reasons.append(L10n.tr("совпадает год смерти")) }
        if corroboratingRelative(localPerson, incomingPerson, localIndex: localIndex, incomingIndex: incomingIndex) {
            reasons.append(L10n.tr("совпадает родственник"))
        }
        return reasons
    }

    private nonisolated static func corroboratingRelative(
        _ left: Person,
        _ right: Person,
        localIndex: FamilyIndex,
        incomingIndex: FamilyIndex
    ) -> Bool {
        let leftParents = localIndex.parentsOf(left)
        let rightParents = incomingIndex.parentsOf(right)
        let leftRelatives = [leftParents.father, leftParents.mother].compactMap { $0 } + localIndex.spousesOf(left)
        let rightRelatives = [rightParents.father, rightParents.mother].compactMap { $0 } + incomingIndex.spousesOf(right)
        let leftNames = Set(leftRelatives.map { TreeWorkspaceIndexes.normalize($0.fullName) })
        let rightNames = Set(rightRelatives.map { TreeWorkspaceIndexes.normalize($0.fullName) })
        return !leftNames.intersection(rightNames).isEmpty
    }

    /// Compared by content, not by `Hashable`: these records carry a UUID, so two
    /// people matched heuristically never share one and every field would otherwise
    /// be reported as a conflict even when both files say exactly the same thing.
    private func factConflicts(local: Person, incoming: Person) -> [MergeConflict] {
        func differs(_ left: [some ContentIdentifiable], _ right: [some ContentIdentifiable]) -> Bool {
            !left.isEmpty && !right.isEmpty && Set(left.map(\.contentKey)) != Set(right.map(\.contentKey))
        }
        var result: [MergeConflict] = []
        if differs(local.names, incoming.names) {
            result.append(conflict("names", local: local, incoming: incoming))
        }
        if differs(local.events, incoming.events) {
            result.append(conflict("events", local: local, incoming: incoming))
        }
        if differs(local.citations, incoming.citations) {
            result.append(conflict("citations", local: local, incoming: incoming))
        }
        return result
    }

    private func conflict(_ field: String, local: Person, incoming: Person) -> MergeConflict {
        MergeConflict(
            id: "\(local.id.uuidString):\(incoming.id.uuidString):\(field)",
            localPersonID: local.id,
            incomingPersonID: incoming.id,
            field: field,
            choice: .both
        )
    }

    private func mergeSources(from incoming: FamilyTree, into local: FamilyTree) -> [UUID: UUID] {
        var map: [UUID: UUID] = [:]
        for source in incoming.sourceRecords {
            if let exact = local.sourceRecords.first(where: { $0.id == source.id }) {
                map[source.id] = exact.id
            } else {
                var copied = source
                if local.sourceRecords.contains(where: { $0.id == copied.id }) { copied.id = UUID() }
                local.sourceRecords.append(copied)
                map[source.id] = copied.id
            }
        }
        return map
    }

    private func mergePerson(
        _ incoming: Person,
        into local: Person,
        sourceMap: [UUID: UUID],
        attachmentIDMap: [String: String],
        conflicts: [MergeConflict]
    ) {
        let choices = Dictionary(conflicts
            .filter { $0.localPersonID == local.id && $0.incomingPersonID == incoming.id }
            .map { ($0.field, $0.choice) }, uniquingKeysWith: { first, _ in first })

        local.names = choose(local.names, incoming.names, choice: choices["names"] ?? .both)
        let incomingEvents = incoming.events.map { value in
            var copy = value
            copy.mediaIDs = copy.mediaIDs.map { attachmentIDMap[$0] ?? $0 }
            return copy
        }
        local.events = choose(local.events, incomingEvents, choice: choices["events"] ?? .both)
        local.citations = remap(choose(local.citations, incoming.citations, choice: choices["citations"] ?? .both), sourceMap: sourceMap)
        local.names = local.names.map { name in
            var copy = name
            copy.citations = remap(copy.citations, sourceMap: sourceMap)
            return copy
        }
        local.events = local.events.map { event in
            var copy = event
            copy.citations = remap(copy.citations, sourceMap: sourceMap)
            return copy
        }
        if local.notes?.isEmpty != false { local.notes = incoming.notes }

        // Fields outside the conflict list still have to survive the merge: dropping
        // them silently loses data the incoming file is the only holder of.
        if local.sex == .unknown { local.sex = incoming.sex }
        // A death recorded in either file settles the question; only two files that
        // both believe the person is alive leave them living.
        local.isLiving = local.isLiving && incoming.isLiving
        var seenLinks = Set(local.links.map { WebLink.normalize($0.url) })
        local.links += incoming.links.filter { seenLinks.insert(WebLink.normalize($0.url)).inserted }
        local.sources += incoming.sources.filter { !local.sources.contains($0) }
        local.unknownBranches += incoming.unknownBranches.filter { !local.unknownBranches.contains($0) }
        for (tag, lines) in incoming.eventExtras where local.eventExtras[tag] == nil {
            local.eventExtras[tag] = lines
        }
    }

    /// Absorbs an incoming union into the local one it matched by partners and
    /// children. `incoming` is already a clone with its sources and media remapped.
    private func mergeUnion(_ incoming: Union, into local: Union) {
        local.events = choose(local.events, incoming.events, choice: .both)
        local.citations = choose(local.citations, incoming.citations, choice: .both)
        local.unknownBranches += incoming.unknownBranches.filter { !local.unknownBranches.contains($0) }
        if local.marriageExtras.isEmpty { local.marriageExtras = incoming.marriageExtras }
    }

    /// De-duplicates by content, not by `Hashable`: these records carry a UUID, so
    /// the same fact arriving from two files never compares equal and "keep both"
    /// would leave a person holding two identical birth events. Records that
    /// genuinely differ are all kept — that is what the user asked for.
    private func choose<T: ContentIdentifiable>(_ local: [T], _ incoming: [T], choice: MergeFactChoice) -> [T] {
        switch choice {
        case .local: return local
        case .incoming: return incoming
        case .both:
            var seen = Set<String>()
            return (local + incoming).filter { seen.insert($0.contentKey).inserted }
        }
    }

    private func remap(_ citations: [Citation], sourceMap: [UUID: UUID]) -> [Citation] {
        citations.map { citation in
            var copy = citation
            copy.sourceID = sourceMap[citation.sourceID] ?? citation.sourceID
            return copy
        }
    }

    private func remapEvidence(in person: Person, sourceMap: [UUID: UUID]) {
        person.citations = remap(person.citations, sourceMap: sourceMap)
        person.names = person.names.map { value in
            var copy = value; copy.citations = remap(copy.citations, sourceMap: sourceMap); return copy
        }
        person.events = person.events.map { value in
            var copy = value; copy.citations = remap(copy.citations, sourceMap: sourceMap); return copy
        }
        person.attachments = person.attachments.map { value in
            var copy = value; copy.citations = remap(copy.citations, sourceMap: sourceMap); return copy
        }
    }

    private func remapEvidence(in union: Union, sourceMap: [UUID: UUID]) {
        union.citations = remap(union.citations, sourceMap: sourceMap)
        union.events = union.events.map { value in
            var copy = value; copy.citations = remap(copy.citations, sourceMap: sourceMap); return copy
        }
    }

    private func remapMediaIDs(in person: Person, attachmentIDMap: [String: String]) {
        person.events = person.events.map { value in
            var copy = value; copy.mediaIDs = copy.mediaIDs.map { attachmentIDMap[$0] ?? $0 }; return copy
        }
    }

    private func remapMediaIDs(in union: Union, attachmentIDMap: [String: String]) {
        union.events = union.events.map { value in
            var copy = value; copy.mediaIDs = copy.mediaIDs.map { attachmentIDMap[$0] ?? $0 }; return copy
        }
    }

    private func stageFiles(
        from incoming: Person,
        into copied: Person,
        localTree: FamilyTree,
        attachmentIDMap: inout [String: String]
    ) throws -> [Attachment] {
        if let bytes = incoming.photoData {
            let ext = incoming.photoFilename.flatMap { URL(fileURLWithPath: $0).pathExtension }.flatMap { $0.isEmpty ? nil : $0 } ?? "jpg"
            copied.photoFilename = "merge-\(UUID().uuidString).\(ext)"
            copied.photoData = bytes
        } else {
            copied.photoFilename = nil
        }

        guard !incoming.attachments.isEmpty else { return [] }
        guard let mediaFolder = incoming.mediaFolderURL else {
            throw TreeMergeError.attachmentMissing(incoming.attachments[0].originalName)
        }
        let sourceFolder = mediaFolder.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
        var prepared: [Attachment] = []
        var usedIDs = Set(localTree.people.flatMap(\.attachments).map(\.id))
        do {
            for attachment in incoming.attachments {
                let source = sourceFolder.appendingPathComponent(attachment.storedName)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw TreeMergeError.attachmentMissing(attachment.originalName)
                }
                var staged = try store.prepareAttachment(in: localTree, sourceURL: source)
                if !usedIDs.contains(attachment.id) { staged.id = attachment.id }
                staged.originalName = attachment.originalName
                staged.notes = attachment.notes
                staged.citations = copied.attachments.first(where: { $0.id == attachment.id })?.citations ?? attachment.citations
                usedIDs.insert(staged.id)
                attachmentIDMap[attachment.id.uuidString] = staged.id.uuidString
                prepared.append(staged)
            }
        } catch {
            for attachment in prepared { store.discardPreparedAttachment(attachment, in: localTree) }
            throw error
        }
        copied.attachments = prepared
        return prepared
    }

    private func mergeFiles(
        from incoming: Person,
        into local: Person,
        localTree: FamilyTree,
        sourceMap: [UUID: UUID],
        attachmentIDMap: inout [String: String]
    ) throws -> [Attachment] {
        if !local.hasPhoto, let bytes = incoming.photoData {
            let ext = incoming.photoFilename.flatMap { URL(fileURLWithPath: $0).pathExtension }.flatMap { $0.isEmpty ? nil : $0 } ?? "jpg"
            local.photoFilename = "merge-\(UUID().uuidString).\(ext)"
            local.photoData = bytes
        }
        guard !incoming.attachments.isEmpty else { return [] }
        guard let mediaFolder = incoming.mediaFolderURL else {
            throw TreeMergeError.attachmentMissing(incoming.attachments[0].originalName)
        }
        let sourceFolder = mediaFolder.deletingLastPathComponent().appendingPathComponent("Attachments", isDirectory: true)
        var prepared: [Attachment] = []
        var usedIDs = Set(localTree.people.flatMap(\.attachments).map(\.id))
        do {
            for attachment in incoming.attachments {
                if let existing = local.attachments.first(where: { $0.originalName == attachment.originalName }) {
                    attachmentIDMap[attachment.id.uuidString] = existing.id.uuidString
                    continue
                }
                let source = sourceFolder.appendingPathComponent(attachment.storedName)
                guard FileManager.default.fileExists(atPath: source.path) else {
                    throw TreeMergeError.attachmentMissing(attachment.originalName)
                }
                var copy = try store.prepareAttachment(in: localTree, sourceURL: source)
                if !usedIDs.contains(attachment.id) { copy.id = attachment.id }
                copy.originalName = attachment.originalName
                copy.notes = attachment.notes
                copy.citations = remap(attachment.citations, sourceMap: sourceMap)
                usedIDs.insert(copy.id)
                attachmentIDMap[attachment.id.uuidString] = copy.id.uuidString
                local.attachments.append(copy)
                prepared.append(copy)
            }
        } catch {
            for attachment in prepared {
                local.attachments.removeAll { $0.id == attachment.id }
                store.discardPreparedAttachment(attachment, in: localTree)
            }
            throw error
        }
        return prepared
    }

    private func unionSignature(_ union: Union) -> String {
        let partners = union.partnerIds.map(\.uuidString).sorted().joined(separator: ",")
        let children = union.childrenIds.map(\.uuidString).sorted().joined(separator: ",")
        return "\(partners)|\(children)"
    }

    private func clone<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func restore(_ snapshot: FamilyTree, into tree: FamilyTree) {
        tree.applyContent(of: snapshot)
        tree.createdAt = snapshot.createdAt
        tree.updatedAt = snapshot.updatedAt
        store.refreshMediaFolders(for: tree)
    }
}
