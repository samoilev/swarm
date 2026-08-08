import Foundation

/// Builds relationship indexes from a FamilyTree for efficient lookups
public struct FamilyIndex {
    public struct ParentEdge: Hashable, Sendable {
        public let parentID: UUID
        public let childID: UUID
        public let kind: ParentageKind
    }

    public let tree: FamilyTree

    /// Person ID -> the (last) Union where they are a child. Kept for callers that
    /// only need a single parent-union; prefer `childOfAll` / `mergedParentIds`.
    public private(set) var childOf: [UUID: Union] = [:]
    /// Person ID -> every Union that lists them as a child. A child's father and
    /// mother can be recorded in separate FAM records, so parentage must be merged
    /// across all of these (see `mergedParentIds`).
    public private(set) var childOfAll: [UUID: [Union]] = [:]
    /// Person ID -> [Union] where they are a partner
    public private(set) var unionsOf: [UUID: [Union]] = [:]
    /// All people indexed by ID
    public private(set) var byId: [UUID: Person] = [:]
    /// Explicit GEDCOM parentage links, indexed independently of family unions.
    public private(set) var parentLinksByChild: [UUID: [ParentLink]] = [:]
    public private(set) var childLinksByParent: [UUID: [ParentLink]] = [:]

    public init(tree: FamilyTree) {
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
        for link in tree.parentLinks {
            parentLinksByChild[link.childID, default: []].append(link)
            childLinksByParent[link.parentID, default: []].append(link)
        }
    }

    /// Every recorded parent edge, without collapsing multiple parents into
    /// father/mother slots. Explicit PEDI links override the biological default
    /// inferred from a family union.
    public func parentEdges(of childID: UUID) -> [ParentEdge] {
        var result: [UUID: ParentEdge] = [:]
        for union in childOfAll[childID] ?? [] {
            for parentID in union.partnerIds where parentID != childID && byId[parentID] != nil {
                result[parentID] = ParentEdge(
                    parentID: parentID,
                    childID: childID,
                    kind: .biological
                )
            }
        }
        for link in parentLinksByChild[childID] ?? [] where link.parentID != childID && byId[link.parentID] != nil {
            result[link.parentID] = ParentEdge(
                parentID: link.parentID,
                childID: childID,
                kind: link.kind
            )
        }
        return result.values.sorted { $0.parentID.uuidString < $1.parentID.uuidString }
    }

    public func childEdges(of parentID: UUID) -> [ParentEdge] {
        var result: [UUID: ParentEdge] = [:]
        for union in unionsOf[parentID] ?? [] {
            for childID in union.childrenIds where childID != parentID && byId[childID] != nil {
                result[childID] = ParentEdge(
                    parentID: parentID,
                    childID: childID,
                    kind: .biological
                )
            }
        }
        for link in childLinksByParent[parentID] ?? [] where link.childID != parentID && byId[link.childID] != nil {
            result[link.childID] = ParentEdge(
                parentID: parentID,
                childID: link.childID,
                kind: link.kind
            )
        }
        return result.values.sorted { $0.childID.uuidString < $1.childID.uuidString }
    }

    /// Father/mother UUIDs merged across every union that lists this person as a
    /// child (handles split-family GEDCOM where each parent is in its own FAM).
    public func mergedParentIds(_ personId: UUID) -> (father: UUID?, mother: UUID?) {
        var father: UUID? = nil
        var mother: UUID? = nil
        for edge in parentEdges(of: personId) {
            guard let parent = byId[edge.parentID] else { continue }
            if parent.sex == .male {
                if father == nil { father = parent.id }
            } else if parent.sex == .female {
                if mother == nil { mother = parent.id }
            } else if father == nil {
                father = parent.id
            } else if mother == nil {
                mother = parent.id
            }
        }
        return (father, mother)
    }

    /// Sibling UUIDs, merged across all parent-unions (deduplicated, excluding self).
    public func mergedSiblingIds(_ personId: UUID) -> [UUID] {
        var seen = Set<UUID>([personId])
        var result: [UUID] = []
        for union in childOfAll[personId] ?? [] {
            for siblingID in union.childrenIds
                where byId[siblingID] != nil && seen.insert(siblingID).inserted {
                result.append(siblingID)
            }
        }
        for parent in parentEdges(of: personId) {
            for edge in childEdges(of: parent.parentID) where seen.insert(edge.childID).inserted {
                result.append(edge.childID)
            }
        }
        return result
    }

    /// How many parents two people share (0, 1, 2) — distinguishes full vs half siblings.
    public func sharedParentCount(_ a: UUID, _ b: UUID) -> Int {
        let aParents = Set(parentEdges(of: a).map(\.parentID))
        let bParents = Set(parentEdges(of: b).map(\.parentID))
        return aParents.intersection(bParents).count
    }

    public func parentsOf(_ person: Person) -> (father: Person?, mother: Person?) {
        let ids = mergedParentIds(person.id)
        return (ids.father.flatMap { byId[$0] }, ids.mother.flatMap { byId[$0] })
    }

    public func spousesOf(_ person: Person) -> [Person] {
        let unions = unionsOf[person.id] ?? []
        return unions.compactMap { union in
            let otherId = union.partnerIds.first(where: { $0 != person.id })
            guard let oid = otherId else { return nil }
            return byId[oid]
        }
    }

    public func childrenOf(_ person: Person) -> [Person] {
        childEdges(of: person.id).compactMap { byId[$0.childID] }
    }

    public func siblingsOf(_ person: Person) -> [Person] {
        mergedSiblingIds(person.id).compactMap { byId[$0] }
    }
}
