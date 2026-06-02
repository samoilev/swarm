import Foundation
import Observation

/// Builds relationship indexes from a FamilyTree for efficient lookups
struct FamilyIndex {
    let tree: FamilyTree
    
    /// Person ID -> the (last) Union where they are a child. Kept for callers that
    /// only need a single parent-union; prefer `childOfAll` / `mergedParentIds`.
    private(set) var childOf: [UUID: Union] = [:]
    /// Person ID -> every Union that lists them as a child. A child's father and
    /// mother can be recorded in separate FAM records, so parentage must be merged
    /// across all of these (see `mergedParentIds`).
    private(set) var childOfAll: [UUID: [Union]] = [:]
    /// Person ID -> [Union] where they are a partner
    private(set) var unionsOf: [UUID: [Union]] = [:]
    /// All people indexed by ID
    private(set) var byId: [UUID: Person] = [:]

    init(tree: FamilyTree) {
        self.tree = tree

        for person in tree.people {
            byId[person.id] = person
            unionsOf[person.id] = []
        }

        for union in tree.unions {
            for pid in union.partnerIds {
                unionsOf[pid, default: []].append(union)
            }
            for cid in union.childrenIds {
                childOf[cid] = union
                childOfAll[cid, default: []].append(union)
            }
        }
    }

    /// Father/mother UUIDs merged across every union that lists this person as a
    /// child (handles split-family GEDCOM where each parent is in its own FAM).
    func mergedParentIds(_ personId: UUID) -> (father: UUID?, mother: UUID?) {
        var father: UUID? = nil
        var mother: UUID? = nil
        for union in childOfAll[personId] ?? [] {
            for pid in union.partnerIds {
                guard let p = byId[pid] else { continue }
                if p.sex == .male { if father == nil { father = pid } }
                else if p.sex == .female { if mother == nil { mother = pid } }
                else if father == nil { father = pid }
                else if mother == nil { mother = pid }
            }
        }
        return (father, mother)
    }

    /// Sibling UUIDs, merged across all parent-unions (deduplicated, excluding self).
    func mergedSiblingIds(_ personId: UUID) -> [UUID] {
        var seen = Set<UUID>([personId])
        var result: [UUID] = []
        for union in childOfAll[personId] ?? [] {
            for c in union.childrenIds where seen.insert(c).inserted {
                result.append(c)
            }
        }
        return result
    }

    /// How many parents two people share (0, 1, 2) — distinguishes full vs half siblings.
    func sharedParentCount(_ a: UUID, _ b: UUID) -> Int {
        let pa = mergedParentIds(a)
        let pb = mergedParentIds(b)
        var aSet = Set<UUID>()
        if let f = pa.father { aSet.insert(f) }
        if let m = pa.mother { aSet.insert(m) }
        var count = 0
        if let f = pb.father, aSet.contains(f) { count += 1 }
        if let m = pb.mother, aSet.contains(m) { count += 1 }
        return count
    }

    func parentsOf(_ person: Person) -> (father: Person?, mother: Person?) {
        let ids = mergedParentIds(person.id)
        return (ids.father.flatMap { byId[$0] }, ids.mother.flatMap { byId[$0] })
    }

    func spousesOf(_ person: Person) -> [Person] {
        let unions = unionsOf[person.id] ?? []
        return unions.compactMap { union in
            let otherId = union.partnerIds.first(where: { $0 != person.id })
            guard let oid = otherId else { return nil }
            return byId[oid]
        }
    }

    func childrenOf(_ person: Person) -> [Person] {
        let unions = unionsOf[person.id] ?? []
        return unions.flatMap { union in
            union.childrenIds.compactMap { byId[$0] }
        }
    }

    func siblingsOf(_ person: Person) -> [Person] {
        mergedSiblingIds(person.id).compactMap { byId[$0] }
    }
    
    /// Get partners of a union as Person objects
    func partners(of union: Union) -> [Person] {
        union.partnerIds.compactMap { byId[$0] }
    }
    
    /// Get children of a union as Person objects
    func children(of union: Union) -> [Person] {
        union.childrenIds.compactMap { byId[$0] }
    }
}
