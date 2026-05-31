import Foundation
import Observation

/// Builds relationship indexes from a FamilyTree for efficient lookups
struct FamilyIndex {
    let tree: FamilyTree
    
    /// Person ID -> Union where they are a child
    private(set) var childOf: [UUID: Union] = [:]
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
            }
        }
    }
    
    func parentsOf(_ person: Person) -> (father: Person?, mother: Person?) {
        guard let union = childOf[person.id] else { return (nil, nil) }
        var father: Person? = nil
        var mother: Person? = nil
        for pid in union.partnerIds {
            guard let p = byId[pid] else { continue }
            if p.sex == .male { father = p }
            else if p.sex == .female { mother = p }
        }
        if father == nil && mother == nil {
            if let p1id = union.partner1Id { father = byId[p1id] }
            if let p2id = union.partner2Id { mother = byId[p2id] }
        }
        return (father, mother)
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
        guard let parentUnion = childOf[person.id] else { return [] }
        return parentUnion.childrenIds.compactMap { byId[$0] }.filter { $0.id != person.id }
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
