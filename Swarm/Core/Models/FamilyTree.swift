import Foundation
import Observation

/// A kinship role to attach, expressed from the subject person's point of view.
public enum RelationKind: String, CaseIterable, Identifiable, Hashable {
    case parent, spouse, child, sibling
    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .parent: L10n.tr("Родитель")
        case .spouse: L10n.tr("Супруг(а)")
        case .child: L10n.tr("Ребёнок")
        case .sibling: L10n.tr("Брат/сестра")
        }
    }

    /// Apply parents before siblings and spouses before children so a batch of
    /// relatives added at once links into shared unions in the right order.
    public var applyOrder: Int {
        switch self {
        case .parent: 0
        case .spouse: 1
        case .sibling: 2
        case .child: 3
        }
    }
}

/// The four openings that actually start a tree, offered at the end of first-run setup.
/// Each carries the link *and* a sensible sex, which is part of why onboarding no longer
/// asks for sex separately.
public enum FirstRelative: String, CaseIterable, Identifiable, Sendable {
    case father, mother, spouse, child

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .father: L10n.tr("Отец")
        case .mother: L10n.tr("Мать")
        case .spouse: L10n.tr("Супруг(а)")
        case .child: L10n.tr("Ребёнок")
        }
    }

    public var sex: Person.Sex {
        switch self {
        case .father: .male
        case .mother: .female
        case .spouse, .child: .unknown
        }
    }

    /// `addRelation` reads the kind from the *new* person's perspective, so the roles
    /// invert here: a father is someone whose child is the person already in the tree.
    public var relation: RelationKind {
        switch self {
        case .father, .mother: .child
        case .spouse: .spouse
        case .child: .parent
        }
    }

    /// Spouses usually arrive with a different surname; everyone else usually doesn't.
    public var inheritsSurname: Bool { self != .spouse }

    public var givenNameExample: String {
        switch self {
        case .father, .child: L10n.tr("напр. Пётр")
        case .mother, .spouse: L10n.tr("напр. Мария")
        }
    }
}

@Observable
public final class FamilyTree: Identifiable, Codable {
    public var id: UUID
    public var schemaVersion: Int = 2
    public var name: String
    public var subtitle: String?
    public var homePersonId: UUID?
    public var rootUnionId: UUID?
    public var people: [Person]
    public var unions: [Union]
    /// Structured source records and explicit parentage links. Legacy flat source
    /// strings remain readable through Person during the staged migration.
    public var sourceRecords: [SourceRecord] = []
    public var parentLinks: [ParentLink] = []
    /// Unrecognized level-1 HEAD branches are retained separately because HEAD is an
    /// app-owned record and therefore cannot live in `unknownRecords`.
    public var headUnknownBranches: [[String]] = []
    /// The ordered syntax tree of the most recently imported/loaded GEDCOM.
    public var gedcomDocument: GEDCOMDocument?
    /// Diagnostics from the most recent import. This is informational after import;
    /// it never replaces validation of the live tree.
    public var importReport: ImportReport?
    /// Validation findings present when a tree was loaded. Their exact identities are
    /// allowed to persist, while changed/new errors receive new identities and block.
    public var acceptedBaselineIssueIDs: Set<String> = []
    /// Whole top-level GEDCOM records the app doesn't model (SOUR, SUBM, REPO, NOTE
    /// records, …), kept as raw lines and re-emitted verbatim before TRLR so importing
    /// then re-exporting a foreign file doesn't drop them.
    public var unknownRecords: [[String]] = []
    public var createdAt: Date
    public var updatedAt: Date

    public init(name: String, subtitle: String? = nil) {
        self.id = UUID()
        self.name = name
        self.subtitle = subtitle
        self.people = []
        self.unions = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public var homePerson: Person? {
        guard let hid = homePersonId else { return nil }
        return people.first(where: { $0.id == hid })
    }

    public var rootUnion: Union? {
        guard let rid = rootUnionId else { return nil }
        return unions.first(where: { $0.id == rid })
    }

    public func person(byId pid: UUID) -> Person? {
        people.first(where: { $0.id == pid })
    }

    /// A counter incremented after each structural change to signal layout recalculation.
    public var layoutVersion: Int = 0

    /// Find the optimal root union (topmost ancestor) and update rootUnionId.
    /// Call after every add/remove/edit that changes the tree structure.
    public func optimizeRoot() {
        // First, deduplicate and merge redundant unions
        deduplicateUnions()

        guard !unions.isEmpty else {
            rootUnionId = nil
            layoutVersion += 1
            return
        }

        // Build a set of people who are children in some union
        var isChild = Set<UUID>()
        for u in unions {
            for cid in u.childrenIds {
                isChild.insert(cid)
            }
        }

        // Score unions: prefer those where BOTH partners have no parents (true top-level)
        // A partner who is a child of another union is NOT a root candidate
        let scored = unions.map { u -> (Union, Int) in
            let partners = u.partnerIds
            let rootPartners = partners.filter { !isChild.contains($0) }
            // Score: 2 = both partners are roots, 1 = one partner is root, 0 = none
            // Bonus: prefer unions that have children (more complete family)
            let childBonus = u.childrenIds.isEmpty ? 0 : 1
            return (u, rootPartners.count * 10 + childBonus)
        }

        if let best = scored.max(by: { $0.1 < $1.1 })?.0 {
            rootUnionId = best.id
        } else {
            rootUnionId = unions.first?.id
        }

        // Ensure homePersonId is set
        if homePersonId == nil || !people.contains(where: { $0.id == homePersonId }) {
            homePersonId = people.first?.id
        }

        layoutVersion += 1
    }

    /// Merge unions that share the same partner pair, and remove empty unions.
    private func deduplicateUnions() {
        // Remove unions with no partners and no children
        unions.removeAll { $0.partnerIds.isEmpty && $0.childrenIds.isEmpty }

        // Group unions by their partner pair (sorted to make order-independent)
        var merged: [Union] = []
        var seen: [Set<UUID>: Int] = [:] // partner set → index in merged

        for union in unions {
            let partnerSet = Set(union.partnerIds)

            // Skip lone-partner unions that carry nothing worth keeping. A single
            // partner is still meaningful when they have children (a single parent)
            // or recorded marriage data (a widow/widower whose spouse was removed) —
            // dropping the latter would silently lose the marriage date/place.
            let hasMarriageData = union.marriageDate != nil || union.marriagePlace != nil
            if partnerSet.count < 2 && union.childrenIds.isEmpty && !hasMarriageData {
                continue
            }

            if partnerSet.count == 2, let existingIdx = seen[partnerSet] {
                // Merge into existing: combine children, keep marriage data from whichever has it
                let existing = merged[existingIdx]
                for cid in union.childrenIds where !existing.childrenIds.contains(cid) {
                    existing.childrenIds.append(cid)
                }
                if existing.marriageDate == nil { existing.marriageDate = union.marriageDate }
                if existing.marriagePlace == nil { existing.marriagePlace = union.marriagePlace }
            } else {
                // Deduplicate children within a single union
                var seenChildren = Set<UUID>()
                union.childrenIds = union.childrenIds.filter { seenChildren.insert($0).inserted }

                seen[partnerSet] = merged.count
                merged.append(union)
            }
        }

        // Remove children from partner-less unions if they already belong to a union with partners
        var childrenInPartnerUnions = Set<UUID>()
        for u in merged where u.partnerIds.count >= 2 {
            for cid in u.childrenIds {
                childrenInPartnerUnions.insert(cid)
            }
        }
        for u in merged where u.partnerIds.isEmpty {
            u.childrenIds.removeAll { childrenInPartnerUnions.contains($0) }
        }
        // Remove now-empty partner-less unions
        merged.removeAll { $0.partnerIds.isEmpty && $0.childrenIds.isEmpty }

        unions = merged
    }

    /// Link `targetId` to `person` in the given role (read from `person`'s point of
    /// view). Reuses existing unions so that adding several relatives — two parents,
    /// a spouse and their children — collapses into the correct shared families.
    public func addRelation(_ kind: RelationKind, person: Person, target targetId: UUID) {
        guard targetId != person.id else { return }
        switch kind {
        case .parent:
            // Make `target` a parent of `person` (person is the child).
            if unions.contains(where: { $0.childrenIds.contains(person.id) && $0.partnerIds.contains(targetId) }) { return }
            if let u = unions.first(where: { $0.childrenIds.contains(person.id) }) {
                // A child belongs to exactly one parent union: add the co-parent if there
                // is room; if it is already a couple, we can't record a third parent —
                // leave it rather than duplicating the child into another union.
                if u.partner1Id == nil || u.partner2Id == nil { fillFreePartner(u, with: targetId) }
            } else if let u = unions.first(where: { $0.partnerIds.contains(targetId) }) {
                // Target already heads a family → person joins it as a child.
                u.childrenIds.append(person.id)
            } else {
                unions.append(Union(partner1Id: targetId, childrenIds: [person.id]))
            }
        case .spouse:
            if unions.contains(where: { $0.partnerIds.contains(person.id) && $0.partnerIds.contains(targetId) }) { return }
            // Prefer slotting into an existing single-partner union so its children stay
            // shared, instead of spawning a duplicate childless union.
            if let u = unions.first(where: { $0.partnerIds == [person.id] }) {
                fillFreePartner(u, with: targetId)
            } else if let u = unions.first(where: { $0.partnerIds == [targetId] }) {
                fillFreePartner(u, with: person.id)
            } else {
                unions.append(Union(partner1Id: person.id, partner2Id: targetId))
            }
        case .child:
            // Make `target` a child of `person` (person is the parent).
            if unions.contains(where: { $0.partnerIds.contains(person.id) && $0.childrenIds.contains(targetId) }) { return }
            if let u = unions.first(where: { $0.childrenIds.contains(targetId) }) {
                // The child already belongs to a parent union: add person as co-parent if
                // there is room; if it is already a couple, don't duplicate the child into
                // a second union (a child has exactly one parent union).
                if u.partner1Id == nil || u.partner2Id == nil { fillFreePartner(u, with: person.id) }
            } else if let existing = unions.first(where: { $0.partnerIds.contains(person.id) }) {
                existing.childrenIds.append(targetId)
            } else {
                unions.append(Union(partner1Id: person.id, childrenIds: [targetId]))
            }
        case .sibling:
            if unions.contains(where: { $0.childrenIds.contains(person.id) && $0.childrenIds.contains(targetId) }) { return }
            if let existing = unions.first(where: { $0.childrenIds.contains(person.id) }) {
                existing.childrenIds.append(targetId)
            } else {
                unions.append(Union(childrenIds: [person.id, targetId]))
            }
        }
        reconcileParentLinks()
    }

    /// An isolated working copy. `FamilyTree`, `Person` and `Union` are reference types
    /// shared across every view, so an editor mutates this instead: nothing it changes
    /// can reach the live tree until the caller validates and persists it.
    public func deepCopy() throws -> FamilyTree {
        try JSONDecoder().decode(FamilyTree.self, from: JSONEncoder().encode(self))
    }

    /// Copy a snapshot's content into this live instance (shared across many views),
    /// then bump `layoutVersion` so canvases recompute. Identity and `createdAt` stay.
    public func applyContent(of snapshot: FamilyTree) {
        schemaVersion = snapshot.schemaVersion
        name = snapshot.name
        subtitle = snapshot.subtitle
        homePersonId = snapshot.homePersonId
        rootUnionId = snapshot.rootUnionId
        people = snapshot.people
        unions = snapshot.unions
        sourceRecords = snapshot.sourceRecords
        parentLinks = snapshot.parentLinks
        headUnknownBranches = snapshot.headUnknownBranches
        unknownRecords = snapshot.unknownRecords
        gedcomDocument = snapshot.gedcomDocument
        importReport = snapshot.importReport
        acceptedBaselineIssueIDs = snapshot.acceptedBaselineIssueIDs
        updatedAt = Date()
        layoutVersion += 1
    }

    /// Ensure every parent/child pair represented by a family union has an explicit
    /// parentage record. Existing non-biological classifications are never replaced.
    public func reconcileParentLinks() {
        let peopleIDs = Set(people.map(\.id))
        let validTriples = Set(unions.flatMap { union in
            union.childrenIds.flatMap { childID in
                union.partnerIds.map { parentID in
                    ParentLinkKey(parentID: parentID, childID: childID, unionID: union.id)
                }
            }
        })
        parentLinks.removeAll { link in
            !peopleIDs.contains(link.parentID) || !peopleIDs.contains(link.childID) ||
                !validTriples.contains(ParentLinkKey(parentID: link.parentID, childID: link.childID, unionID: link.unionID))
        }
        let existing = Set(parentLinks.map { ParentLinkKey(parentID: $0.parentID, childID: $0.childID, unionID: $0.unionID) })
        for key in validTriples where !existing.contains(key) {
            parentLinks.append(ParentLink(
                parentID: key.parentID,
                childID: key.childID,
                unionID: key.unionID,
                kind: .biological
            ))
        }
    }

    /// Migrate old person-level source strings into shared records using exact trimmed
    /// equality only. The legacy text is kept until the compatibility UI is removed.
    public func migrateLegacySources() {
        var byTitle = Dictionary(uniqueKeysWithValues: sourceRecords.map { ($0.title.trimmingCharacters(in: .whitespacesAndNewlines), $0.id) })
        for person in people {
            let legacySources = person.sources
            for raw in legacySources {
                let title = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty else { continue }
                let sourceID: UUID
                if let existing = byTitle[title] {
                    sourceID = existing
                } else {
                    let source = SourceRecord(title: title)
                    sourceRecords.append(source)
                    byTitle[title] = source.id
                    sourceID = source.id
                }
                if !person.citations.contains(where: { $0.sourceID == sourceID }) {
                    person.citations.append(Citation(sourceID: sourceID))
                }
            }
            if !legacySources.isEmpty { person.sources = [] }
        }
    }

    // MARK: - Source records

    /// Every citation in the tree, wherever it hangs. The editor only surfaces
    /// `Person.citations`, but sharing and orphan decisions have to see all of them:
    /// a record still cited from a name, event, attachment, union or parent link must
    /// not be forked needlessly, and must never be pruned while still in use.
    public func allCitations() -> [Citation] {
        var result: [Citation] = []
        for person in people {
            result += person.citations
            result += person.names.flatMap(\.citations)
            result += person.events.flatMap(\.citations)
            result += person.attachments.flatMap(\.citations)
        }
        for union in unions {
            result += union.citations
            result += union.events.flatMap(\.citations)
        }
        result += parentLinks.flatMap(\.citations)
        return result
    }

    public func citationReferenceCount(sourceID: UUID) -> Int {
        allCitations().count { $0.sourceID == sourceID }
    }

    /// Store an edited source and return the id the citation must now point at.
    ///
    /// An imported file can cite one `SOUR` from twenty people. The editor presents a
    /// source as if it belonged to the person being edited, so rewriting a shared
    /// record in place would silently rewrite it for the other nineteen. When the
    /// record is shared this forks it instead and leaves the original untouched.
    @discardableResult
    public func upsertSourceRecord(_ edited: SourceRecord, replacing originalID: UUID?) -> UUID {
        guard let originalID, let index = sourceRecords.firstIndex(where: { $0.id == originalID }) else {
            sourceRecords.append(edited)
            return edited.id
        }
        if citationReferenceCount(sourceID: originalID) <= 1 {
            var updated = edited
            updated.id = originalID
            sourceRecords[index] = updated
            return originalID
        }
        // The fork drops the xref so the export assigns it its own `@S…@`, and drops the
        // preserved branches so it stays app-created and therefore prunable. The original
        // keeps both.
        var fork = edited
        fork.id = UUID()
        fork.gedcomXref = nil
        fork.rawGEDCOMBranches = []
        sourceRecords.append(fork)
        return fork.id
    }

    /// Drop source records nothing cites any more, but only ones this app created.
    /// A record carrying an xref or preserved branches came from a file, and a foreign
    /// file has to survive import and re-export unchanged even when the user deletes
    /// the last citation pointing at it.
    public func pruneUnreferencedSourceRecords() {
        let referenced = Set(allCitations().map(\.sourceID))
        sourceRecords.removeAll { record in
            !referenced.contains(record.id)
                && record.gedcomXref == nil
                && record.rawGEDCOMBranches.isEmpty
        }
    }

    /// Put `id` into whichever partner slot of `union` is free (partner1 first).
    private func fillFreePartner(_ union: Union, with id: UUID) {
        if union.partner1Id == nil { union.partner1Id = id }
        else if union.partner2Id == nil { union.partner2Id = id }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, subtitle, homePersonId, rootUnionId, people, unions, createdAt, updatedAt
        case schemaVersion, sourceRecords, parentLinks, headUnknownBranches, gedcomDocument, importReport, acceptedBaselineIssueIDs
        case unknownRecords
    }

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        schemaVersion = try c.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        name = try c.decode(String.self, forKey: .name)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        homePersonId = try c.decodeIfPresent(UUID.self, forKey: .homePersonId)
        rootUnionId = try c.decodeIfPresent(UUID.self, forKey: .rootUnionId)
        people = try c.decode([Person].self, forKey: .people)
        unions = try c.decode([Union].self, forKey: .unions)
        sourceRecords = try c.decodeIfPresent([SourceRecord].self, forKey: .sourceRecords) ?? []
        parentLinks = try c.decodeIfPresent([ParentLink].self, forKey: .parentLinks) ?? []
        headUnknownBranches = try c.decodeIfPresent([[String]].self, forKey: .headUnknownBranches) ?? []
        gedcomDocument = try c.decodeIfPresent(GEDCOMDocument.self, forKey: .gedcomDocument)
        importReport = try c.decodeIfPresent(ImportReport.self, forKey: .importReport)
        acceptedBaselineIssueIDs = try c.decodeIfPresent(Set<String>.self, forKey: .acceptedBaselineIssueIDs) ?? []
        unknownRecords = try c.decodeIfPresent([[String]].self, forKey: .unknownRecords) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(homePersonId, forKey: .homePersonId)
        try c.encodeIfPresent(rootUnionId, forKey: .rootUnionId)
        try c.encode(people, forKey: .people)
        try c.encode(unions, forKey: .unions)
        if !sourceRecords.isEmpty { try c.encode(sourceRecords, forKey: .sourceRecords) }
        if !parentLinks.isEmpty { try c.encode(parentLinks, forKey: .parentLinks) }
        if !headUnknownBranches.isEmpty { try c.encode(headUnknownBranches, forKey: .headUnknownBranches) }
        try c.encodeIfPresent(gedcomDocument, forKey: .gedcomDocument)
        try c.encodeIfPresent(importReport, forKey: .importReport)
        if !acceptedBaselineIssueIDs.isEmpty { try c.encode(acceptedBaselineIssueIDs, forKey: .acceptedBaselineIssueIDs) }
        if !unknownRecords.isEmpty { try c.encode(unknownRecords, forKey: .unknownRecords) }
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}

private struct ParentLinkKey: Hashable {
    let parentID: UUID
    let childID: UUID
    let unionID: UUID?
}
