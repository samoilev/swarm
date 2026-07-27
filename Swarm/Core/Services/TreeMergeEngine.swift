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
}

public enum TreeMergeError: LocalizedError {
    case wrongDestination
    case snapshotFailed
    case attachmentMissing(String)

    public var errorDescription: String? {
        switch self {
        case .wrongDestination: L10n.tr("Предпросмотр слияния относится к другому дереву.")
        case .snapshotFailed: L10n.tr("Не удалось создать снимок для отката слияния.")
        case let .attachmentMissing(name): L10n.tr("Файл вложения не найден: \(name).")
        }
    }
}

/// Local-only merge engine. Heuristic candidates are suggestions until their exact
/// match IDs are added to `acceptedHeuristicMatchIDs`; they are never applied silently.
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
                    reasons: [L10n.tr("совпадает xref в одном _TREEID")]
                ))
                matchedLocal.insert(localPerson.id)
                matchedIncoming.insert(candidate.id)
            }
        }

        var suggestions: [MergePersonMatch] = []
        for candidate in incoming.people where !matchedIncoming.contains(candidate.id) {
            for localPerson in local.people where !matchedLocal.contains(localPerson.id) {
                let reasons = Self.heuristicReasons(localPerson, candidate, local: local, incoming: incoming)
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

        var conflicts: [MergeConflict] = []
        for match in automatic {
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
        guard let beforeData = try? JSONEncoder().encode(local),
              let before = try? JSONDecoder().decode(FamilyTree.self, from: beforeData) else {
            throw TreeMergeError.snapshotFailed
        }

        _ = try store.createVerifiedBackup(for: local, label: "pre-merge")
        var preparedAttachments: [Attachment] = []
        do {
            var matches = preview.automaticMatches
            matches += preview.heuristicSuggestions.filter { preview.acceptedHeuristicMatchIDs.contains($0.id) }
            let incoming = preview.incomingTree
            var personMap = Dictionary(uniqueKeysWithValues: matches.map { ($0.incomingPersonID, $0.localPersonID) })
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
                if !local.parentLinks.contains(where: { $0.parentID == parentID && $0.childID == childID && $0.kind == copied.kind }) {
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
    public static func duplicateSuggestions(in tree: FamilyTree) -> [DuplicateSuggestion] {
        var buckets: [String: [Person]] = [:]
        for person in tree.people {
            guard let year = person.event(ofKind: .birth)?.date?.year else { continue }
            let name = TreeWorkspaceIndexes.normalize(person.fullName)
            guard !name.isEmpty else { continue }
            buckets["\(name):\(year)", default: []].append(person)
        }
        var result: [DuplicateSuggestion] = []
        for candidates in buckets.values where candidates.count > 1 {
            for firstIndex in candidates.indices {
                for secondIndex in candidates.indices where secondIndex > firstIndex {
                    let first = candidates[firstIndex]
                    let second = candidates[secondIndex]
                    let reasons = heuristicReasons(first, second, local: tree, incoming: tree)
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

    private static func heuristicReasons(
        _ localPerson: Person,
        _ incomingPerson: Person,
        local: FamilyTree,
        incoming: FamilyTree
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
        if corroboratingRelative(localPerson, incomingPerson, local: local, incoming: incoming) { reasons.append(L10n.tr("совпадает родственник")) }
        return reasons
    }

    private static func corroboratingRelative(_ left: Person, _ right: Person, local: FamilyTree, incoming: FamilyTree) -> Bool {
        let localIndex = FamilyIndex(tree: local)
        let incomingIndex = FamilyIndex(tree: incoming)
        let leftParents = localIndex.parentsOf(left)
        let rightParents = incomingIndex.parentsOf(right)
        let leftRelatives = [leftParents.father, leftParents.mother].compactMap { $0 } + localIndex.spousesOf(left)
        let rightRelatives = [rightParents.father, rightParents.mother].compactMap { $0 } + incomingIndex.spousesOf(right)
        let leftNames = Set(leftRelatives.map { TreeWorkspaceIndexes.normalize($0.fullName) })
        let rightNames = Set(rightRelatives.map { TreeWorkspaceIndexes.normalize($0.fullName) })
        return !leftNames.intersection(rightNames).isEmpty
    }

    private func factConflicts(local: Person, incoming: Person) -> [MergeConflict] {
        var result: [MergeConflict] = []
        if Set(local.names) != Set(incoming.names), !local.names.isEmpty, !incoming.names.isEmpty {
            result.append(conflict("names", local: local, incoming: incoming))
        }
        if Set(local.events) != Set(incoming.events), !local.events.isEmpty, !incoming.events.isEmpty {
            result.append(conflict("events", local: local, incoming: incoming))
        }
        if Set(local.citations) != Set(incoming.citations), !local.citations.isEmpty, !incoming.citations.isEmpty {
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
        let choices = Dictionary(uniqueKeysWithValues: conflicts
            .filter { $0.localPersonID == local.id && $0.incomingPersonID == incoming.id }
            .map { ($0.field, $0.choice) })

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
    }

    private func choose<T: Hashable>(_ local: [T], _ incoming: [T], choice: MergeFactChoice) -> [T] {
        switch choice {
        case .local: return local
        case .incoming: return incoming
        case .both:
            var seen = Set<T>()
            return (local + incoming).filter { seen.insert($0).inserted }
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
