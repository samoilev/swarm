import Foundation

/// Finds the shortest family path between two people and labels each person's relationship to the first
struct RelationshipPathFinder {
    let index: FamilyIndex
    
    struct PathResult {
        /// Ordered list of person IDs from person1 to person2
        var path: [UUID]
        /// All IDs on the path (for highlighting)
        var ids: Set<UUID>
        /// Relationship label for each person relative to person1
        var labels: [UUID: String]
    }
    
    /// Find shortest path between two people via BFS on the family graph
    func findPath(from person1Id: UUID, to person2Id: UUID) -> PathResult? {
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
    
    /// Compute relationship labels along the path relative to person1
    private func computeLabels(path: [UUID], from person1Id: UUID) -> [UUID: String] {
        var labels: [UUID: String] = [:]
        guard path.count >= 1 else { return labels }
        
        labels[person1Id] = "①"
        
        // Walk the path and compute cumulative relationship
        // Track movement: up (to parent), down (to child), lateral (to spouse)
        var moves: [(UUID, Move)] = [] // each step in the path
        
        for i in 1..<path.count {
            let prev = path[i - 1]
            let curr = path[i]
            let move = classifyMove(from: prev, to: curr)
            moves.append((curr, move))
        }
        
        // Now label each person based on accumulated moves from person1
        for (i, (personId, _)) in moves.enumerated() {
            let movesUpToHere = moves[0...i].map { $0.1 }
            let label = relationshipFromMoves(movesUpToHere, personId: personId)
            labels[personId] = label
        }
        
        // Mark the last person as ②
        if let lastId = path.last, lastId != person1Id {
            let existingLabel = labels[lastId] ?? ""
            labels[lastId] = "② " + existingLabel
        }
        
        return labels
    }
    
    private enum Move {
        case up    // to parent
        case down  // to child
        case spouse // to spouse
    }
    
    private func classifyMove(from prevId: UUID, to currId: UUID) -> Move {
        guard let prev = index.byId[prevId] else { return .spouse }
        
        // Is currId a parent of prevId?
        let parents = index.parentsOf(prev)
        if parents.father?.id == currId || parents.mother?.id == currId {
            return .up
        }
        
        // Is currId a child of prevId?
        let children = index.childrenOf(prev)
        if children.contains(where: { $0.id == currId }) {
            return .down
        }
        
        // Otherwise it's a spouse
        return .spouse
    }
    
    private func relationshipFromMoves(_ moves: [Move], personId: UUID) -> String {
        let person = index.byId[personId]
        let sex = person?.sex ?? .unknown
        
        // Count ups, downs, and spouse transitions
        var ups = 0
        var downs = 0
        var hasSpouse = false
        // Track whether spouse comes BEFORE ups (in-law) or AFTER (spouse of ancestor)
        var spouseBeforeUps = false
        var spouseAfterUps = false
        var upsBeforeSpouse = 0
        
        var seenSpouse = false
        for move in moves {
            switch move {
            case .up:
                ups += 1
                if !seenSpouse { upsBeforeSpouse += 1 }
            case .down:
                downs += 1
            case .spouse:
                hasSpouse = true
                seenSpouse = true
                if ups == 0 && downs == 0 { spouseBeforeUps = true }
                else { spouseAfterUps = true }
            }
        }
        
        // If the last move is spouse only
        if moves.last == .spouse && ups == 0 && downs == 0 {
            return sex == .male ? "Муж" : "Жена"
        }
        
        // Pure ancestor path (only ups, NO spouse)
        if downs == 0 && ups > 0 && !hasSpouse {
            return ancestorLabel(generation: ups, sex: sex)
        }
        
        // Ancestor via spouse (in-law): spouse → up → up...
        // e.g., spouse's father = свёкор/тесть, spouse's grandfather = дед мужа/жены
        if downs == 0 && ups > 0 && spouseBeforeUps {
            return inLawAncestorLabel(generation: ups, sex: sex)
        }
        
        // Spouse of ancestor: up → up → spouse
        // e.g., grandfather's wife = бабушка
        if downs == 0 && ups > 0 && spouseAfterUps {
            return ancestorLabel(generation: upsBeforeSpouse, sex: sex)
        }
        
        // Pure descendant path (only downs)
        if ups == 0 && downs > 0 && !hasSpouse {
            return descendantLabel(generation: downs, sex: sex)
        }
        
        // Descendant via spouse: spouse → down
        if ups == 0 && downs > 0 && spouseBeforeUps {
            // Spouse's child from another marriage (пасынок/падчерица)
            return sex == .male ? "Пасынок" : "Падчерица"
        }
        
        // Spouse of descendant: down → spouse
        if ups == 0 && downs > 0 && spouseAfterUps {
            return sex == .female ? "Невестка" : "Зять"
        }
        
        // Sibling: 1 up + 1 down
        if ups == 1 && downs == 1 && !hasSpouse {
            return sex == .female ? "Сестра" : "Брат"
        }
        
        // Sibling via spouse: spouse → up → down (spouse's sibling)
        if ups == 1 && downs == 1 && spouseBeforeUps {
            return sex == .female ? "Золовка/Свояч." : "Деверь/Шурин"
        }
        
        // Spouse of sibling: up → down → spouse
        if ups == 1 && downs == 1 && spouseAfterUps {
            return sex == .female ? "Невестка" : "Зять"
        }
        
        // Uncle/aunt: 2 up + 1 down
        if ups == 2 && downs == 1 && !hasSpouse {
            return sex == .female ? "Тётя" : "Дядя"
        }
        
        // Uncle/aunt via spouse: spouse → 2 up → 1 down
        if ups == 2 && downs == 1 && spouseBeforeUps {
            return sex == .female ? "Тётя мужа/жены" : "Дядя мужа/жены"
        }
        
        // Spouse of uncle/aunt
        if ups == 2 && downs == 1 && spouseAfterUps {
            return sex == .female ? "Тётя" : "Дядя"
        }
        
        // Cousin: 2 up + 2 down
        if ups == 2 && downs == 2 {
            return sex == .female ? "Кузина" : "Кузен"
        }
        
        // Nephew/niece: 1 up + 2 down
        if ups == 1 && downs == 2 {
            return sex == .female ? "Племянница" : "Племянник"
        }
        
        // Great uncle/aunt: 3 up + 1 down
        if ups == 3 && downs == 1 {
            return sex == .female ? "Двоюр. баб." : "Двоюр. дед."
        }
        
        // Grand nephew/niece: 1 up + 3 down
        if ups == 1 && downs == 3 {
            return sex == .female ? "Внуч. плем." : "Внуч. плем."
        }
        
        // Second cousin: 3 up + 3 down
        if ups == 3 && downs == 3 {
            return sex == .female ? "Троюр. сестра" : "Троюр. брат"
        }
        
        // 3 up + 2 down
        if ups == 3 && downs == 2 {
            return sex == .female ? "Двоюр. тётя" : "Двоюр. дядя"
        }
        
        // 2 up + 3 down
        if ups == 2 && downs == 3 {
            return sex == .female ? "Двоюр. плем." : "Двоюр. плем."
        }
        
        // Generic: show distance with arrow notation
        if ups > 0 && downs > 0 {
            return "\(ups)↑\(downs)↓"
        }
        
        return "Родств."
    }
    
    private func ancestorLabel(generation: Int, sex: Person.Sex) -> String {
        switch generation {
        case 1: return sex == .female ? "Мать" : "Отец"
        case 2: return sex == .female ? "Бабушка" : "Дедушка"
        case 3: return sex == .female ? "Прабабушка" : "Прадедушка"
        case 4: return sex == .female ? "Прапрабаб." : "Прапрадед."
        default: return "\(generation)× пра"
        }
    }
    
    private func inLawAncestorLabel(generation: Int, sex: Person.Sex) -> String {
        switch generation {
        case 1: return sex == .female ? "Свекровь/Тёща" : "Свёкор/Тесть"
        case 2: return sex == .female ? "Баб. супруга" : "Дед супруга"
        case 3: return sex == .female ? "Прабаб. супр." : "Прадед супр."
        default: return "\(generation)× пра супр."
        }
    }
    
    private func descendantLabel(generation: Int, sex: Person.Sex) -> String {
        switch generation {
        case 1: return sex == .female ? "Дочь" : "Сын"
        case 2: return sex == .female ? "Внучка" : "Внук"
        case 3: return sex == .female ? "Правнучка" : "Правнук"
        default: return "\(generation)× потомок"
        }
    }
}
