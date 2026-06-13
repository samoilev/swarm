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
        case .parent: "Родитель"
        case .spouse: "Супруг(а)"
        case .child: "Ребёнок"
        case .sibling: "Брат/сестра"
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

@Observable
public final class FamilyTree: Identifiable, Codable {
    public var id: UUID
    public var name: String
    public var subtitle: String?
    public var homePersonId: UUID?
    public var rootUnionId: UUID?
    public var people: [Person]
    public var unions: [Union]
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

            // Skip unions with 0 or 1 partner that have no children (orphan link)
            if partnerSet.count < 2 && union.childrenIds.isEmpty {
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
    }

    /// Put `id` into whichever partner slot of `union` is free (partner1 first).
    private func fillFreePartner(_ union: Union, with id: UUID) {
        if union.partner1Id == nil { union.partner1Id = id }
        else if union.partner2Id == nil { union.partner2Id = id }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, subtitle, homePersonId, rootUnionId, people, unions, createdAt, updatedAt
    }

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        homePersonId = try c.decodeIfPresent(UUID.self, forKey: .homePersonId)
        rootUnionId = try c.decodeIfPresent(UUID.self, forKey: .rootUnionId)
        people = try c.decode([Person].self, forKey: .people)
        unions = try c.decode([Union].self, forKey: .unions)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(homePersonId, forKey: .homePersonId)
        try c.encodeIfPresent(rootUnionId, forKey: .rootUnionId)
        try c.encode(people, forKey: .people)
        try c.encode(unions, forKey: .unions)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
