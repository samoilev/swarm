import Foundation

/// Calculates and names the relationship between two people in the family tree
struct RelationshipCalculator {
    let tree: FamilyTree
    private let idx: FamilyIndex
    
    init(tree: FamilyTree) {
        self.tree = tree
        self.idx = FamilyIndex(tree: tree)
    }
    
    struct RelationshipResult {
        let name: String
        let path: [UUID]
        let description: String
    }
    
    // MARK: - Public
    
    func relationship(from personA: Person, to personB: Person) -> RelationshipResult? {
        guard personA.id != personB.id else {
            return RelationshipResult(name: "Это тот же человек", path: [personA.id], description: "")
        }

        // Direct spouse — must be checked before anything else.
        if idx.spousesOf(personA).contains(where: { $0.id == personB.id }) {
            return RelationshipResult(name: personB.sex == .male ? "Муж" : "Жена",
                                      path: [personA.id, personB.id], description: "")
        }

        // Find path using BFS in family graph (used for the description / highlight)
        guard let path = findPath(from: personA.id, to: personB.id) else {
            return RelationshipResult(name: "Связь не найдена", path: [], description: "Эти люди не связаны в дереве")
        }

        // Blood relationship via lowest common ancestor.
        if let blood = bloodRelationship(from: personA, to: personB) {
            let desc = buildDescription(from: personA, to: personB, path: path)
            return RelationshipResult(name: blood.name, path: path, description: desc)
        }

        // Otherwise an in-law / spouse-based relationship.
        if let result = checkInLawRelationship(from: personA, to: personB, path: path) {
            return result
        }

        let desc = buildDescription(from: personA, to: personB, path: path)
        return RelationshipResult(name: "Родственник", path: path, description: desc)
    }

    /// Blood relationship only (via lowest common ancestor); nil if no common ancestor.
    /// Kept separate so in-law detection can use it without re-entering in-law logic.
    private func bloodRelationship(from personA: Person, to personB: Person) -> RelationshipResult? {
        if personA.id == personB.id {
            return RelationshipResult(name: "Это тот же человек", path: [personA.id], description: "")
        }
        let (upA, upB) = findCommonAncestorDistances(from: personA.id, to: personB.id)
        guard let up = upA, let down = upB else { return nil }
        let name = nameRelationship(stepsUp: up, stepsDown: down, from: personA, to: personB)
        return RelationshipResult(name: name, path: [], description: "")
    }
    
    // MARK: - Path Finding (BFS)
    
    private func findPath(from startId: UUID, to targetId: UUID) -> [UUID]? {
        var visited = Set<UUID>()
        var queue: [(id: UUID, path: [UUID])] = [(startId, [startId])]
        visited.insert(startId)
        
        while !queue.isEmpty {
            let (current, path) = queue.removeFirst()
            if current == targetId { return path }
            
            for neighbor in neighbors(of: current) {
                if !visited.contains(neighbor) {
                    visited.insert(neighbor)
                    queue.append((neighbor, path + [neighbor]))
                }
            }
        }
        return nil
    }
    
    private func neighbors(of personId: UUID) -> [UUID] {
        var result: [UUID] = []
        
        // Parents
        if let parentUnion = idx.childOf[personId] {
            result.append(contentsOf: parentUnion.partnerIds)
            // Siblings
            result.append(contentsOf: parentUnion.childrenIds.filter { $0 != personId })
        }
        
        // Spouses and children
        for union in idx.unionsOf[personId] ?? [] {
            result.append(contentsOf: union.partnerIds.filter { $0 != personId })
            result.append(contentsOf: union.childrenIds)
        }
        
        return result
    }
    
    // MARK: - Common Ancestor
    
    /// Returns (stepsUp from A to ancestor, stepsDown from ancestor to B)
    private func findCommonAncestorDistances(from aId: UUID, to bId: UUID) -> (Int?, Int?) {
        let ancestorsA = allAncestorsWithDepth(aId)
        let ancestorsB = allAncestorsWithDepth(bId)
        
        var bestSum = Int.max
        var bestUp = 0
        var bestDown = 0
        
        for (ancId, depthA) in ancestorsA {
            if let depthB = ancestorsB[ancId] {
                let sum = depthA + depthB
                if sum < bestSum {
                    bestSum = sum
                    bestUp = depthA
                    bestDown = depthB
                }
            }
        }
        
        if bestSum == Int.max { return (nil, nil) }
        return (bestUp, bestDown)
    }
    
    private func allAncestorsWithDepth(_ personId: UUID) -> [UUID: Int] {
        var result: [UUID: Int] = [personId: 0]
        var queue: [(UUID, Int)] = [(personId, 0)]
        
        while !queue.isEmpty {
            let (current, depth) = queue.removeFirst()
            if let parentUnion = idx.childOf[current] {
                for pid in parentUnion.partnerIds {
                    if result[pid] == nil {
                        result[pid] = depth + 1
                        queue.append((pid, depth + 1))
                    }
                }
            }
        }
        return result
    }
    
    // MARK: - Naming
    
    private func nameRelationship(stepsUp: Int, stepsDown: Int, from personA: Person, to personB: Person) -> String {
        let sexB = personB.sex
        
        // Direct ancestor/descendant
        if stepsDown == 0 {
            switch stepsUp {
            case 1: return sexB == .male ? "Отец" : "Мать"
            case 2: return sexB == .male ? "Дед" : "Бабушка"
            case 3: return sexB == .male ? "Прадед" : "Прабабушка"
            case 4: return sexB == .male ? "Прапрадед" : "Прапрабабушка"
            default: return "\(stepsUp)-й предок"
            }
        }
        
        if stepsUp == 0 {
            switch stepsDown {
            case 1: return sexB == .male ? "Сын" : "Дочь"
            case 2: return sexB == .male ? "Внук" : "Внучка"
            case 3: return sexB == .male ? "Правнук" : "Правнучка"
            case 4: return sexB == .male ? "Праправнук" : "Праправнучка"
            default: return "\(stepsDown)-й потомок"
            }
        }
        
        // Siblings
        if stepsUp == 1 && stepsDown == 1 {
            return sexB == .male ? "Брат" : "Сестра"
        }
        
        // Uncle/Aunt - Nephew/Niece
        if stepsUp == 1 && stepsDown == 2 {
            return sexB == .male ? "Племянник" : "Племянница"
        }
        if stepsUp == 2 && stepsDown == 1 {
            return sexB == .male ? "Дядя" : "Тётя"
        }
        
        // Great uncle/aunt - grand nephew/niece
        if stepsUp == 1 && stepsDown == 3 {
            return sexB == .male ? "Внучатый племянник" : "Внучатая племянница"
        }
        if stepsUp == 3 && stepsDown == 1 {
            return sexB == .male ? "Двоюродный дед" : "Двоюродная бабушка"
        }
        
        // Cousins
        if stepsUp == stepsDown {
            let degree = stepsUp - 1
            switch degree {
            case 1: return sexB == .male ? "Двоюродный брат" : "Двоюродная сестра"
            case 2: return sexB == .male ? "Троюродный брат" : "Троюродная сестра"
            case 3: return sexB == .male ? "Четвероюродный брат" : "Четвероюродная сестра"
            default: return "\(degree + 1)-юродный \(sexB == .male ? "брат" : "сестра")"
            }
        }
        
        // Cousins removed
        if stepsUp >= 2 && stepsDown >= 2 {
            let degree = min(stepsUp, stepsDown) - 1
            let cousinName: String
            switch degree {
            case 1: cousinName = sexB == .male ? "Двоюродный" : "Двоюродная"
            case 2: cousinName = sexB == .male ? "Троюродный" : "Троюродная"
            default: cousinName = "\(degree + 1)-юродный"
            }
            let relType = sexB == .male ? "племянник" : "племянница"
            if stepsDown > stepsUp {
                return "\(cousinName) \(relType)"
            } else {
                let relType2 = sexB == .male ? "дядя" : "тётя"
                return "\(cousinName) \(relType2)"
            }
        }
        
        return "Дальний родственник"
    }
    
    // MARK: - In-Law Relationships
    
    private func checkInLawRelationship(from personA: Person, to personB: Person, path: [UUID]) -> RelationshipResult? {
        let sexA = personA.sex
        let sexB = personB.sex
        
        // Check if B is spouse of a blood relative of A
        let spousesOfB = idx.spousesOf(personB)
        for spouseOfB in spousesOfB where spouseOfB.id != personA.id {
            if let bloodRel = bloodRelationship(from: personA, to: spouseOfB) {
                if let name = inLawName(bloodRelName: bloodRel.name, sexA: sexA, sexB: sexB) {
                    let desc = buildDescription(from: personA, to: personB, path: path)
                    return RelationshipResult(name: name, path: path, description: desc)
                }
            }
        }

        // Check if A's spouse is blood relative of B
        let spousesOfA = idx.spousesOf(personA)
        for spouseOfA in spousesOfA where spouseOfA.id != personB.id {
            if let bloodRel = bloodRelationship(from: spouseOfA, to: personB) {
                if let n = inLawViaMySpouse(bloodRelName: bloodRel.name, sexA: sexA, sexB: sexB) {
                    let desc = buildDescription(from: personA, to: personB, path: path)
                    return RelationshipResult(name: n, path: path, description: desc)
                }
            }
        }

        return nil
    }
    
    /// Names in-law when B is the spouse of A's blood relative
    private func inLawName(bloodRelName: String, sexA: Person.Sex, sexB: Person.Sex) -> String? {
        switch bloodRelName {
        case "Брат":
            // B is spouse of A's brother → B is невестка/сноха for female, N/A for male
            return sexB == .female ? "Невестка (жена брата)" : nil
        case "Сестра":
            // B is spouse of A's sister → B is зять for male
            return sexB == .male ? "Зять (муж сестры)" : nil
        case "Сын":
            return sexB == .female ? "Невестка (сноха)" : nil
        case "Дочь":
            return sexB == .male ? "Зять (муж дочери)" : nil
        default:
            return nil
        }
    }
    
    /// Names when B is blood relative of A's spouse
    private func inLawViaMySpouse(bloodRelName: String, sexA: Person.Sex, sexB: Person.Sex) -> String? {
        switch bloodRelName {
        case "Отец":
            return sexB == .male ? "Свёкор" : "Тесть"
        case "Мать":
            return sexB == .female ? (sexA == .female ? "Свекровь" : "Тёща") : nil
        case "Брат":
            if sexA == .female {
                return sexB == .male ? "Деверь" : nil
            } else {
                return sexB == .male ? "Шурин" : nil
            }
        case "Сестра":
            if sexA == .male {
                return sexB == .female ? "Свояченица" : nil
            } else {
                return sexB == .female ? "Золовка" : nil
            }
        default:
            return nil
        }
    }
    
    // MARK: - Description
    
    private func buildDescription(from personA: Person, to personB: Person, path: [UUID]) -> String {
        guard path.count > 2 else { return "" }
        let names = path.compactMap { idx.byId[$0]?.listName }
        return "Через: " + names.dropFirst().dropLast().joined(separator: " → ")
    }
}
