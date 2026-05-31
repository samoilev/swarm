import Foundation

/// Computes direct lineage and Russian kinship labels relative to a selected person
struct LineageCalculator {
    let index: FamilyIndex
    
    struct LineageResult {
        /// All person IDs in the direct lineage
        var ids: Set<UUID>
        /// Relationship label for each person relative to the selected one
        var labels: [UUID: String]
    }
    
    /// Compute all direct ancestors and descendants of the given person, with kinship labels
    func compute(for person: Person) -> LineageResult {
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
                labels[spouse.id] = childSpouseLabel(generation: generation, sex: spouse.sex)
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
    
    private func childSpouseLabel(generation: Int, sex: Person.Sex) -> String {
        switch generation {
        case 1:
            return sex == .female ? "Невестка" : "Зять"
        default:
            return sex == .female ? "Жена" : "Муж"
        }
    }
}
