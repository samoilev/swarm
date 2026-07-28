import Foundation

/// Calculates relationship semantics independently of presentation language.
public struct RelationshipCalculator {
    public let tree: FamilyTree
    private let idx: FamilyIndex

    public init(tree: FamilyTree) {
        self.tree = tree
        idx = FamilyIndex(tree: tree)
    }

    public struct RelationshipResult {
        public let descriptor: KinshipDescriptor
        public let name: String
        public let path: [UUID]
        public let description: String
    }

    // MARK: - Public

    public func relationship(
        from personA: Person,
        to personB: Person,
        language: AppLanguage = .current
    ) -> RelationshipResult? {
        let formatter = KinshipFormatter(language: language)

        if personA.id == personB.id {
            return make(.samePerson, path: [personA.id], formatter: formatter)
        }

        if idx.spousesOf(personA).contains(where: { $0.id == personB.id }) {
            return make(.spouse(sex: personB.sex), path: [personA.id, personB.id], formatter: formatter)
        }

        if let edge = idx.parentEdges(of: personA.id).first(where: { $0.parentID == personB.id }) {
            return make(
                .parent(sex: personB.sex, kind: edge.kind),
                path: [personA.id, personB.id],
                description: parentageDescription(edge.kind, language: language),
                formatter: formatter
            )
        }
        if let edge = idx.parentEdges(of: personB.id).first(where: { $0.parentID == personA.id }) {
            return make(
                .child(sex: personB.sex, kind: edge.kind),
                path: [personA.id, personB.id],
                description: parentageDescription(edge.kind, language: language),
                formatter: formatter
            )
        }

        let parents = idx.parentsOf(personA)
        let parentPeople = [parents.father, parents.mother].compactMap { $0 }
        if !parentPeople.contains(where: { $0.id == personB.id }),
           parentPeople.contains(where: { parent in
               idx.spousesOf(parent).contains(where: { $0.id == personB.id })
           }) {
            return make(
                .stepParent(sex: personB.sex),
                path: [personA.id, personB.id],
                description: L10n.tr("Производная связь через союз с родителем", language: language),
                formatter: formatter
            )
        }

        guard let path = findPath(from: personA.id, to: personB.id) else {
            return make(
                .unconnected,
                path: [],
                description: L10n.tr("Эти люди не связаны в дереве", language: language),
                formatter: formatter
            )
        }

        if let descriptor = bloodDescriptor(from: personA, to: personB) {
            return make(
                descriptor,
                path: path,
                description: buildDescription(path: path, language: language),
                formatter: formatter
            )
        }

        if let descriptor = inLawDescriptor(from: personA, to: personB) {
            return make(
                descriptor,
                path: path,
                description: buildDescription(path: path, language: language),
                formatter: formatter
            )
        }

        return make(
            .relative,
            path: path,
            description: buildDescription(path: path, language: language),
            formatter: formatter
        )
    }

    private func make(
        _ descriptor: KinshipDescriptor,
        path: [UUID],
        description: String = "",
        formatter: KinshipFormatter
    ) -> RelationshipResult {
        RelationshipResult(
            descriptor: descriptor,
            name: formatter.label(for: descriptor),
            path: path,
            description: description
        )
    }

    // MARK: - Path finding

    private func findPath(from startID: UUID, to targetID: UUID) -> [UUID]? {
        var visited: Set<UUID> = [startID]
        var queue: [(id: UUID, path: [UUID])] = [(startID, [startID])]

        while !queue.isEmpty {
            let (current, path) = queue.removeFirst()
            if current == targetID { return path }

            for neighbor in neighbors(of: current) where !visited.contains(neighbor) {
                visited.insert(neighbor)
                queue.append((neighbor, path + [neighbor]))
            }
        }
        return nil
    }

    private func neighbors(of personID: UUID) -> [UUID] {
        var result: [UUID] = []
        result.append(contentsOf: idx.parentEdges(of: personID).map(\.parentID))
        result.append(contentsOf: idx.mergedSiblingIds(personID))

        for union in idx.unionsOf[personID] ?? [] {
            result.append(contentsOf: union.partnerIds.filter { $0 != personID })
            result.append(contentsOf: union.childrenIds)
        }
        if let person = idx.byId[personID] {
            result.append(contentsOf: idx.childrenOf(person).map(\.id))
        }
        var seen = Set<UUID>()
        return result.filter { seen.insert($0).inserted }
    }

    // MARK: - Blood relationships

    private func bloodDescriptor(from personA: Person, to personB: Person) -> KinshipDescriptor? {
        if personA.id == personB.id { return .samePerson }
        guard let match = findCommonAncestor(from: personA.id, to: personB.id) else {
            return nil
        }
        let base = descriptor(
            stepsUp: match.stepsUp,
            stepsDown: match.stepsDown,
            from: personA,
            to: personB
        )
        return match.parentage.reduce(base) {
            .qualified(base: $0, kind: $1)
        }
    }

    private struct AncestorPath {
        let depth: Int
        let parentage: [ParentageKind]
    }

    private func findCommonAncestor(
        from firstID: UUID,
        to secondID: UUID
    ) -> (stepsUp: Int, stepsDown: Int, parentage: [ParentageKind])? {
        let firstAncestors = allAncestors(firstID)
        let secondAncestors = allAncestors(secondID)
        var best: (
            stepsUp: Int,
            stepsDown: Int,
            parentage: [ParentageKind],
            ancestorID: UUID
        )?

        for (ancestorID, firstPath) in firstAncestors {
            guard let secondPath = secondAncestors[ancestorID] else { continue }
            let parentage = uniqueParentage(firstPath.parentage + secondPath.parentage)
            let candidate = (
                stepsUp: firstPath.depth,
                stepsDown: secondPath.depth,
                parentage: parentage,
                ancestorID: ancestorID
            )
            if best == nil || commonAncestorKey(candidate) < commonAncestorKey(best!) {
                best = candidate
            }
        }
        guard let best else { return nil }
        return (best.stepsUp, best.stepsDown, best.parentage)
    }

    private func allAncestors(_ personID: UUID) -> [UUID: AncestorPath] {
        var result: [UUID: AncestorPath] = [
            personID: AncestorPath(depth: 0, parentage: []),
        ]
        var queue: [(UUID, AncestorPath)] = [(personID, result[personID]!)]

        while !queue.isEmpty {
            let (current, path) = queue.removeFirst()
            for edge in idx.parentEdges(of: current) {
                let parentage = uniqueParentage(
                    path.parentage + (edge.kind == .biological ? [] : [edge.kind])
                )
                let candidate = AncestorPath(depth: path.depth + 1, parentage: parentage)
                if let existing = result[edge.parentID],
                   ancestorPathKey(existing) <= ancestorPathKey(candidate) {
                    continue
                }
                result[edge.parentID] = candidate
                queue.append((edge.parentID, candidate))
            }
        }
        return result
    }

    private func uniqueParentage(_ kinds: [ParentageKind]) -> [ParentageKind] {
        var seen = Set<ParentageKind>()
        return kinds.filter { $0 != .biological && seen.insert($0).inserted }
    }

    private func ancestorPathKey(_ path: AncestorPath) -> String {
        [
            String(format: "%08d", path.depth),
            String(format: "%08d", path.parentage.count),
            path.parentage.map(\.rawValue).joined(separator: ","),
        ].joined(separator: "|")
    }

    private func commonAncestorKey(
        _ match: (
            stepsUp: Int,
            stepsDown: Int,
            parentage: [ParentageKind],
            ancestorID: UUID
        )
    ) -> String {
        let total = match.stepsUp + match.stepsDown
        return [
            String(format: "%08d", total),
            String(format: "%08d", match.parentage.count),
            String(format: "%08d", match.stepsUp),
            String(format: "%08d", match.stepsDown),
            match.parentage.map(\.rawValue).joined(separator: ","),
            match.ancestorID.uuidString,
        ].joined(separator: "|")
    }

    private func descriptor(
        stepsUp: Int,
        stepsDown: Int,
        from personA: Person,
        to personB: Person
    ) -> KinshipDescriptor {
        if stepsDown == 0 {
            return .ancestor(generation: stepsUp, sex: personB.sex)
        }
        if stepsUp == 0 {
            return .descendant(generation: stepsDown, sex: personB.sex)
        }
        if stepsUp == 1, stepsDown == 1 {
            return .sibling(sex: personB.sex, kind: siblingKind(from: personA, to: personB))
        }
        if stepsUp == 1, stepsDown >= 2 {
            return .nieceOrNephew(greats: stepsDown - 2, sex: personB.sex)
        }
        if stepsDown == 1, stepsUp >= 2 {
            return .auntOrUncle(greats: stepsUp - 2, sex: personB.sex)
        }
        if stepsUp >= 2, stepsDown >= 2 {
            let removed = abs(stepsUp - stepsDown)
            let direction: KinshipDescriptor.CousinDirection = if stepsDown > stepsUp {
                .younger
            } else if stepsUp > stepsDown {
                .older
            } else {
                .sameGeneration
            }
            return .cousin(
                degree: min(stepsUp, stepsDown) - 1,
                removed: removed,
                direction: direction,
                sex: personB.sex
            )
        }
        return .distantRelative
    }

    private func siblingKind(from first: Person, to second: Person) -> KinshipDescriptor.SiblingKind {
        if idx.sharedParentCount(first.id, second.id) >= 2 { return .full }
        let firstParents = Set(idx.parentEdges(of: first.id).map(\.parentID))
        let secondParents = Set(idx.parentEdges(of: second.id).map(\.parentID))
        let shared = firstParents.intersection(secondParents)
        if shared.contains(where: { idx.byId[$0]?.sex == .male }) { return .paternalHalf }
        if shared.contains(where: { idx.byId[$0]?.sex == .female }) { return .maternalHalf }
        return .halfUnknown
    }

    // MARK: - In-laws

    private func inLawDescriptor(from personA: Person, to personB: Person) -> KinshipDescriptor? {
        for spouseOfB in idx.spousesOf(personB) where spouseOfB.id != personA.id {
            guard let blood = bloodDescriptor(from: personA, to: spouseOfB) else { continue }
            if let result = inLawForSpouseOfBloodRelative(blood, spouseSex: personB.sex) {
                return result
            }
        }

        for spouseOfA in idx.spousesOf(personA) where spouseOfA.id != personB.id {
            guard let blood = bloodDescriptor(from: spouseOfA, to: personB) else { continue }
            if let result = inLawViaSpouse(blood, subjectSex: personA.sex, relativeSex: personB.sex) {
                return result
            }
        }
        return nil
    }

    private func inLawForSpouseOfBloodRelative(
        _ blood: KinshipDescriptor,
        spouseSex: Person.Sex
    ) -> KinshipDescriptor? {
        switch blood {
        case let .sibling(relativeSex, _):
            if relativeSex == .male, spouseSex == .female { return .inLaw(.brothersWife) }
            if relativeSex == .female, spouseSex == .male { return .inLaw(.sistersHusband) }
        case let .descendant(generation, relativeSex) where generation == 1:
            if relativeSex == .male, spouseSex == .female { return .inLaw(.sonsWife) }
            if relativeSex == .female, spouseSex == .male { return .inLaw(.daughtersHusband) }
        default:
            break
        }
        return nil
    }

    private func inLawViaSpouse(
        _ blood: KinshipDescriptor,
        subjectSex: Person.Sex,
        relativeSex: Person.Sex
    ) -> KinshipDescriptor? {
        let husbandsSide = subjectSex == .female
        switch blood {
        case let .ancestor(generation, _) where generation == 1:
            if relativeSex == .male {
                return .inLaw(husbandsSide ? .fatherHusbandsSide : .fatherWifesSide)
            }
            if relativeSex == .female {
                return .inLaw(husbandsSide ? .motherHusbandsSide : .motherWifesSide)
            }
        case .sibling:
            if relativeSex == .male {
                return .inLaw(husbandsSide ? .brotherHusbandsSide : .brotherWifesSide)
            }
            if relativeSex == .female {
                return .inLaw(husbandsSide ? .sisterHusbandsSide : .sisterWifesSide)
            }
        default:
            break
        }
        return nil
    }

    // MARK: - Descriptions

    private func buildDescription(path: [UUID], language: AppLanguage) -> String {
        guard path.count > 2 else { return "" }
        let names = path.compactMap { idx.byId[$0]?.displayName(language: language) }
        return L10n.tr("Через: \(names.dropFirst().dropLast().joined(separator: " → "))", language: language)
    }

    private func parentageDescription(_ kind: ParentageKind, language: AppLanguage) -> String {
        switch kind {
        case .biological: L10n.tr("Биологическая", language: language)
        case .adoptive: L10n.tr("Приёмная", language: language)
        case .foster: L10n.tr("Опекунская", language: language)
        case .step: L10n.tr("Сводная", language: language)
        case .uncertain: L10n.tr("Предполагаемая", language: language)
        }
    }
}
