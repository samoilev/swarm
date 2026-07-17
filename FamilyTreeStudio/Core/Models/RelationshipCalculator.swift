import Foundation

/// Calculates and names the relationship between two people in the family tree
public struct RelationshipCalculator {
    public let tree: FamilyTree
    private let idx: FamilyIndex

    public init(tree: FamilyTree) {
        self.tree = tree
        self.idx = FamilyIndex(tree: tree)
    }

    public struct RelationshipResult {
        public let name: String
        public let path: [UUID]
        public let description: String
    }

    // MARK: - Public

    public func relationship(from personA: Person, to personB: Person) -> RelationshipResult? {
        guard personA.id != personB.id else {
            return RelationshipResult(name: "Это тот же человек", path: [personA.id], description: "")
        }

        // Direct spouse — must be checked before anything else.
        if idx.spousesOf(personA).contains(where: { $0.id == personB.id }) {
            return RelationshipResult(name: gendered(personB, male: "Муж", female: "Жена", neutral: "Супруг/супруга"),
                                      path: [personA.id, personB.id], description: "")
        }

        if let link = tree.parentLinks.first(where: { $0.parentID == personB.id && $0.childID == personA.id }) {
            return RelationshipResult(
                name: parentName(personB, kind: link.kind),
                path: [personA.id, personB.id],
                description: link.kind.displayName
            )
        }
        if let link = tree.parentLinks.first(where: { $0.parentID == personA.id && $0.childID == personB.id }) {
            return RelationshipResult(
                name: childName(personB, kind: link.kind),
                path: [personA.id, personB.id],
                description: link.kind.displayName
            )
        }
        let parents = idx.parentsOf(personA)
        let parentPeople = [parents.father, parents.mother].compactMap { $0 }
        if !parentPeople.contains(where: { $0.id == personB.id }),
           parentPeople.contains(where: { parent in idx.spousesOf(parent).contains(where: { $0.id == personB.id }) }) {
            return RelationshipResult(
                name: gendered(personB, male: "Отчим", female: "Мачеха", neutral: "Неродной родитель"),
                path: [personA.id, personB.id],
                description: "Производная связь через союз с родителем"
            )
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

        // Parents + siblings (merged across split-family FAM records)
        let parents = idx.mergedParentIds(personId)
        if let f = parents.father { result.append(f) }
        if let m = parents.mother { result.append(m) }
        result.append(contentsOf: idx.mergedSiblingIds(personId))

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
            let parents = idx.mergedParentIds(current)
            for pid in [parents.father, parents.mother].compactMap({ $0 }) {
                if result[pid] == nil {
                    result[pid] = depth + 1
                    queue.append((pid, depth + 1))
                }
            }
        }
        return result
    }

    // MARK: - Naming

    /// Names a sibling, distinguishing full (2 shared parents) from half
    /// (1 shared parent → единокровный via father / единоутробный via mother).
    private func siblingName(from a: Person, to b: Person) -> String {
        let full = idx.sharedParentCount(a.id, b.id) >= 2
        if b.sex == .unknown {
            return full ? "Брат/сестра" : "Неполнородный брат/сестра"
        }
        let isF = b.sex == .female
        if full { return isF ? "Сестра" : "Брат" }
        let pa = idx.mergedParentIds(a.id)
        let pb = idx.mergedParentIds(b.id)
        let sameFather = pa.father != nil && pa.father == pb.father
        if sameFather { return isF ? "Единокровная сестра" : "Единокровный брат" }
        return isF ? "Единоутробная сестра" : "Единоутробный брат"
    }

    private func nameRelationship(stepsUp: Int, stepsDown: Int, from personA: Person, to personB: Person) -> String {
        // Direct ancestor/descendant
        if stepsDown == 0 {
            switch stepsUp {
            case 1: return gendered(personB, male: "Отец", female: "Мать", neutral: "Родитель")
            case 2: return gendered(personB, male: "Дед", female: "Бабушка", neutral: "Родитель родителя")
            case 3: return gendered(personB, male: "Прадед", female: "Прабабушка", neutral: "Прародитель")
            case 4: return gendered(personB, male: "Прапрадед", female: "Прапрабабушка", neutral: "Пра-прародитель")
            default: return "\(stepsUp)-й предок"
            }
        }

        if stepsUp == 0 {
            switch stepsDown {
            case 1: return gendered(personB, male: "Сын", female: "Дочь", neutral: "Ребёнок")
            case 2: return gendered(personB, male: "Внук", female: "Внучка", neutral: "Внук/внучка")
            case 3: return gendered(personB, male: "Правнук", female: "Правнучка", neutral: "Правнук/правнучка")
            case 4: return gendered(personB, male: "Праправнук", female: "Праправнучка", neutral: "Праправнук/праправнучка")
            default: return "\(stepsDown)-й потомок"
            }
        }

        // Siblings (distinguish full from half siblings)
        if stepsUp == 1 && stepsDown == 1 {
            return siblingName(from: personA, to: personB)
        }

        // Uncle/Aunt - Nephew/Niece
        if stepsUp == 1 && stepsDown == 2 {
            return gendered(personB, male: "Племянник", female: "Племянница", neutral: "Племянник/племянница")
        }
        if stepsUp == 2 && stepsDown == 1 {
            return gendered(personB, male: "Дядя", female: "Тётя", neutral: "Дядя/тётя")
        }

        // Great uncle/aunt - grand nephew/niece
        if stepsUp == 1 && stepsDown == 3 {
            return gendered(personB, male: "Внучатый племянник", female: "Внучатая племянница", neutral: "Внучатый племянник/племянница")
        }
        if stepsUp == 3 && stepsDown == 1 {
            return gendered(personB, male: "Двоюродный дед", female: "Двоюродная бабушка", neutral: "Двоюродный прародитель")
        }

        // Cousins
        if stepsUp == stepsDown {
            let degree = stepsUp - 1
            switch degree {
            case 1: return gendered(personB, male: "Двоюродный брат", female: "Двоюродная сестра", neutral: "Двоюродный брат/сестра")
            case 2: return gendered(personB, male: "Троюродный брат", female: "Троюродная сестра", neutral: "Троюродный брат/сестра")
            case 3: return gendered(personB, male: "Четвероюродный брат", female: "Четвероюродная сестра", neutral: "Четвероюродный брат/сестра")
            default: return "\(degree + 1)-юродный родственник"
            }
        }

        // Cousins removed
        if stepsUp >= 2 && stepsDown >= 2 {
            let degree = min(stepsUp, stepsDown) - 1
            let cousinName: String = switch degree {
            case 1: personB.sex == .male ? "Двоюродный" : personB.sex == .female ? "Двоюродная" : "Двоюродный/двоюродная"
            case 2: personB.sex == .male ? "Троюродный" : personB.sex == .female ? "Троюродная" : "Троюродный/троюродная"
            default: "\(degree + 1)-юродный"
            }
            let relType = gendered(personB, male: "племянник", female: "племянница", neutral: "племянник/племянница")
            if stepsDown > stepsUp {
                return "\(cousinName) \(relType)"
            } else {
                let relType2 = gendered(personB, male: "дядя", female: "тётя", neutral: "дядя/тётя")
                return "\(cousinName) \(relType2)"
            }
        }

        return "Дальний родственник"
    }

    private func parentName(_ person: Person, kind: ParentageKind) -> String {
        switch kind {
        case .biological: gendered(person, male: "Отец", female: "Мать", neutral: "Родитель")
        case .adoptive: gendered(person, male: "Приёмный отец", female: "Приёмная мать", neutral: "Приёмный родитель")
        case .foster: gendered(person, male: "Опекун", female: "Опекун", neutral: "Опекун")
        case .step: gendered(person, male: "Отчим", female: "Мачеха", neutral: "Неродной родитель")
        case .uncertain: gendered(person, male: "Предполагаемый отец", female: "Предполагаемая мать", neutral: "Предполагаемый родитель")
        }
    }

    private func childName(_ person: Person, kind: ParentageKind) -> String {
        let base = gendered(person, male: "сын", female: "дочь", neutral: "ребёнок")
        switch kind {
        case .biological: return base.prefix(1).uppercased() + String(base.dropFirst())
        case .adoptive: return "Приёмный \(base)"
        case .foster: return "Ребёнок под опекой"
        case .step: return gendered(person, male: "Пасынок", female: "Падчерица", neutral: "Неродной ребёнок")
        case .uncertain: return "Предполагаемый \(base)"
        }
    }

    private func gendered(_ person: Person, male: String, female: String, neutral: String) -> String {
        switch person.sex {
        case .male: male
        case .female: female
        case .unknown: neutral
        }
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
            sexB == .female ? "Невестка (жена брата)" : nil
        case "Сестра":
            // B is spouse of A's sister → B is зять for male
            sexB == .male ? "Зять (муж сестры)" : nil
        case "Сын":
            sexB == .female ? "Невестка (сноха)" : nil
        case "Дочь":
            sexB == .male ? "Зять (муж дочери)" : nil
        default:
            nil
        }
    }

    /// Names when B is blood relative of A's spouse
    private func inLawViaMySpouse(bloodRelName: String, sexA: Person.Sex, sexB: Person.Sex) -> String? {
        switch bloodRelName {
        case "Отец":
            // B is the spouse's father (always male); the term depends on the
            // subject's sex: the wife's side says свёкор, the husband's side тесть.
            sexA == .female ? "Свёкор" : "Тесть"
        case "Мать":
            sexB == .female ? (sexA == .female ? "Свекровь" : "Тёща") : nil
        case "Брат":
            if sexA == .female {
                sexB == .male ? "Деверь" : nil
            } else {
                sexB == .male ? "Шурин" : nil
            }
        case "Сестра":
            if sexA == .male {
                sexB == .female ? "Свояченица" : nil
            } else {
                sexB == .female ? "Золовка" : nil
            }
        default:
            nil
        }
    }

    // MARK: - Description

    private func buildDescription(from personA: Person, to personB: Person, path: [UUID]) -> String {
        guard path.count > 2 else { return "" }
        let names = path.compactMap { idx.byId[$0]?.listName }
        return "Через: " + names.dropFirst().dropLast().joined(separator: " → ")
    }
}
