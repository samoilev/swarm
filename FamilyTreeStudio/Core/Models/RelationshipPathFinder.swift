import Foundation

/// Finds the shortest family path between two people and labels each person's relationship to the first
public struct RelationshipPathFinder {
    public let index: FamilyIndex

    public init(index: FamilyIndex) {
        self.index = index
    }

    public struct PathResult {
        /// Ordered list of person IDs from person1 to person2
        public var path: [UUID]
        /// All IDs on the path (for highlighting)
        public var ids: Set<UUID>
        /// Relationship label for each person relative to person1
        public var labels: [UUID: String]
    }

    /// Find shortest path between two people via BFS on the family graph
    public func findPath(from person1Id: UUID, to person2Id: UUID) -> PathResult? {
        guard person1Id != person2Id else {
            return PathResult(path: [person1Id], ids: [person1Id], labels: [person1Id: "Я"])
        }
        
        // BFS
        var visited: Set<UUID> = [person1Id]
        var queue: [UUID] = [person1Id]
        var parent: [UUID: UUID] = [:]
        
        while !queue.isEmpty {
            let current = queue.removeFirst()
            
            for neighbor in neighbors(of: current) {
                guard !visited.contains(neighbor) else { continue }
                visited.insert(neighbor)
                parent[neighbor] = current
                
                if neighbor == person2Id {
                    // Reconstruct path
                    var path: [UUID] = [neighbor]
                    var node = neighbor
                    while let p = parent[node] {
                        path.append(p)
                        node = p
                    }
                    path.reverse()
                    
                    let ids = Set(path)
                    let labels = computeLabels(path: path, from: person1Id)
                    return PathResult(path: path, ids: ids, labels: labels)
                }
                
                queue.append(neighbor)
            }
        }
        
        return nil // No path found
    }
    
    /// Get all directly connected people (parents, children, spouses)
    private func neighbors(of personId: UUID) -> [UUID] {
        var result: [UUID] = []
        
        guard let person = index.byId[personId] else { return result }
        
        // Parents
        let parents = index.parentsOf(person)
        if let f = parents.father { result.append(f.id) }
        if let m = parents.mother { result.append(m.id) }
        
        // Children
        for child in index.childrenOf(person) {
            result.append(child.id)
        }
        
        // Spouses
        for spouse in index.spousesOf(person) {
            result.append(spouse.id)
        }
        
        return result
    }
    
    /// Compute relationship labels along the path relative to person1.
    /// Each label is computed with the shared RelationshipCalculator so the
    /// canvas dual-selection always agrees with the relationship dialog.
    private func computeLabels(path: [UUID], from person1Id: UUID) -> [UUID: String] {
        var labels: [UUID: String] = [:]
        guard let p1 = index.byId[person1Id] else { return labels }

        labels[person1Id] = "①"

        let calc = RelationshipCalculator(tree: index.tree)
        let lastId = path.last

        for personId in path where personId != person1Id {
            guard let p = index.byId[personId] else { continue }
            let name = calc.relationship(from: p1, to: p)?.name ?? "Родственник"
            if personId == lastId {
                labels[personId] = "② " + name
            } else {
                labels[personId] = name
            }
        }

        return labels
    }
}
