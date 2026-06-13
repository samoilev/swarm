import Foundation

/// Computes direct lineage and Russian kinship labels relative to a selected person
public struct LineageCalculator {
    public let index: FamilyIndex

    public init(index: FamilyIndex) {
        self.index = index
    }

    public struct LineageResult {
        /// All person IDs in the direct lineage
        public var ids: Set<UUID>
        /// Relationship label for each person relative to the selected one
        public var labels: [UUID: String]
    }

    /// Compute all direct ancestors and descendants of the given person, with kinship labels
    public func compute(for person: Person) -> LineageResult {
        var ids = Set<UUID>()
        var labels: [UUID: String] = [:]
        
        ids.insert(person.id)
        labels[person.id] = "Я"
        
        // Traverse ancestors
        computeAncestors(personId: person.id, generation: 1, ids: &ids, labels: &labels)
        
        // Traverse descendants
        computeDescendants(personId: person.id, generation: 1, ids: &ids, labels: &labels)
        
        // Add spouses
        for spouse in index.spousesOf(person) {
            ids.insert(spouse.id)
            labels[spouse.id] = spouse.sex == .male ? "Муж" : "Жена"
        }
        
        return LineageResult(ids: ids, labels: labels)
    }
    
    private func computeAncestors(personId: UUID, generation: Int, ids: inout Set<UUID>, labels: inout [UUID: String]) {
        guard let person = index.byId[personId] else { return }
        let parents = index.parentsOf(person)
        
        if let father = parents.father {
            ids.insert(father.id)
            labels[father.id] = ancestorLabel(generation: generation, sex: .male)
            computeAncestors(personId: father.id, generation: generation + 1, ids: &ids, labels: &labels)
        }
        if let mother = parents.mother {
            ids.insert(mother.id)
            labels[mother.id] = ancestorLabel(generation: generation, sex: .female)
            computeAncestors(personId: mother.id, generation: generation + 1, ids: &ids, labels: &labels)
        }
    }
    
    private func computeDescendants(personId: UUID, generation: Int, ids: inout Set<UUID>, labels: inout [UUID: String]) {
        guard let person = index.byId[personId] else { return }
        let children = index.childrenOf(person)
        
        for child in children {
            ids.insert(child.id)
            labels[child.id] = descendantLabel(generation: generation, sex: child.sex)
            
            // Add child's spouse
            let childSpouses = index.spousesOf(child)
            for spouse in childSpouses {
                ids.insert(spouse.id)
                labels[spouse.id] = childSpouseLabel(generation: generation, spouseSex: spouse.sex, descendantSex: child.sex)
            }
            
            computeDescendants(personId: child.id, generation: generation + 1, ids: &ids, labels: &labels)
        }
    }
    
    private func ancestorLabel(generation: Int, sex: Person.Sex) -> String {
        switch generation {
        case 1:
            return sex == .female ? "Мать" : "Отец"
        case 2:
            return sex == .female ? "Бабушка" : "Дедушка"
        case 3:
            return sex == .female ? "Прабабушка" : "Прадедушка"
        case 4:
            return sex == .female ? "Прапрабабушка" : "Прапрадедушка"
        default:
            let prefix = String(repeating: "пра", count: generation - 1)
            return sex == .female ? "\(prefix)бабушка" : "\(prefix)дедушка"
        }
    }
    
    private func descendantLabel(generation: Int, sex: Person.Sex) -> String {
        switch generation {
        case 1:
            return sex == .female ? "Дочь" : "Сын"
        case 2:
            return sex == .female ? "Внучка" : "Внук"
        case 3:
            return sex == .female ? "Правнучка" : "Правнук"
        case 4:
            return sex == .female ? "Праправнучка" : "Праправнук"
        default:
            let prefix = String(repeating: "пра", count: generation - 1)
            return sex == .female ? "\(prefix)внучка" : "\(prefix)внук"
        }
    }
    
    /// Label for the spouse of a descendant. Generation 1 keeps the traditional
    /// Зять/Невестка; deeper generations are qualified by whom they married,
    /// e.g. the husband of a granddaughter → «Муж внучки».
    private func childSpouseLabel(generation: Int, spouseSex: Person.Sex, descendantSex: Person.Sex) -> String {
        if generation == 1 {
            return spouseSex == .female ? "Невестка" : "Зять"
        }
        let prefix = spouseSex == .female ? "Жена" : "Муж"
        return "\(prefix) \(descendantGenitive(generation: generation, sex: descendantSex))"
    }

    /// Genitive form of a descendant term, for building spouse labels.
    private func descendantGenitive(generation: Int, sex: Person.Sex) -> String {
        let isF = sex == .female
        switch generation {
        case 1: return isF ? "дочери" : "сына"
        case 2: return isF ? "внучки" : "внука"
        case 3: return isF ? "правнучки" : "правнука"
        case 4: return isF ? "праправнучки" : "праправнука"
        default:
            let prefix = String(repeating: "пра", count: generation - 1)
            return isF ? "\(prefix)внучки" : "\(prefix)внука"
        }
    }
}
