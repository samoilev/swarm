import Foundation

/// Computes direct lineage and language-neutral kinship descriptors relative to a person.
public struct LineageCalculator {
    public let index: FamilyIndex

    public init(index: FamilyIndex) {
        self.index = index
    }

    public struct LineageResult {
        public var ids: Set<UUID>
        public var labels: [UUID: String]
        public var descriptors: [UUID: KinshipDescriptor]
    }

    public func compute(
        for person: Person,
        language: AppLanguage = .current
    ) -> LineageResult {
        var ids: Set<UUID> = [person.id]
        var descriptors: [UUID: KinshipDescriptor] = [:]
        var ancestorVisited: Set<UUID> = [person.id]
        var descendantVisited: Set<UUID> = [person.id]

        computeAncestors(
            personID: person.id,
            generation: 1,
            parentage: [],
            visited: &ancestorVisited,
            ids: &ids,
            descriptors: &descriptors
        )
        computeDescendants(
            personID: person.id,
            generation: 1,
            parentage: [],
            visited: &descendantVisited,
            ids: &ids,
            descriptors: &descriptors
        )

        for spouse in index.spousesOf(person) {
            ids.insert(spouse.id)
            descriptors[spouse.id] = .spouse(sex: spouse.sex)
        }

        let formatter = KinshipFormatter(language: language, style: .lineage)
        var labels = descriptors.mapValues(formatter.label)
        labels[person.id] = L10n.tr("Я", language: language)
        return LineageResult(ids: ids, labels: labels, descriptors: descriptors)
    }

    private func computeAncestors(
        personID: UUID,
        generation: Int,
        parentage: [ParentageKind],
        visited: inout Set<UUID>,
        ids: inout Set<UUID>,
        descriptors: inout [UUID: KinshipDescriptor]
    ) {
        for edge in index.parentEdges(of: personID) {
            guard let parent = index.byId[edge.parentID],
                  visited.insert(parent.id).inserted else { continue }
            let pathKinds = uniqueParentage(
                parentage + (edge.kind == .biological ? [] : [edge.kind])
            )
            ids.insert(parent.id)
            descriptors[parent.id] = generation == 1
                ? .parent(sex: parent.sex, kind: edge.kind)
                : qualified(
                    .ancestor(generation: generation, sex: parent.sex),
                    by: pathKinds
                )
            computeAncestors(
                personID: parent.id,
                generation: generation + 1,
                parentage: pathKinds,
                visited: &visited,
                ids: &ids,
                descriptors: &descriptors
            )
        }
    }

    private func computeDescendants(
        personID: UUID,
        generation: Int,
        parentage: [ParentageKind],
        visited: inout Set<UUID>,
        ids: inout Set<UUID>,
        descriptors: inout [UUID: KinshipDescriptor]
    ) {
        for edge in index.childEdges(of: personID) {
            guard let child = index.byId[edge.childID],
                  visited.insert(child.id).inserted else { continue }
            let pathKinds = uniqueParentage(
                parentage + (edge.kind == .biological ? [] : [edge.kind])
            )
            ids.insert(child.id)
            descriptors[child.id] = generation == 1
                ? .child(sex: child.sex, kind: edge.kind)
                : qualified(
                    .descendant(generation: generation, sex: child.sex),
                    by: pathKinds
                )

            for spouse in index.spousesOf(child) {
                ids.insert(spouse.id)
                descriptors[spouse.id] = qualified(
                    .spouseOfDescendant(
                        generation: generation,
                        spouseSex: spouse.sex,
                        descendantSex: child.sex
                    ),
                    by: pathKinds
                )
            }

            computeDescendants(
                personID: child.id,
                generation: generation + 1,
                parentage: pathKinds,
                visited: &visited,
                ids: &ids,
                descriptors: &descriptors
            )
        }
    }

    private func qualified(
        _ descriptor: KinshipDescriptor,
        by kinds: [ParentageKind]
    ) -> KinshipDescriptor {
        kinds.reduce(descriptor) { .qualified(base: $0, kind: $1) }
    }

    private func uniqueParentage(_ kinds: [ParentageKind]) -> [ParentageKind] {
        var seen = Set<ParentageKind>()
        return kinds.filter { $0 != .biological && seen.insert($0).inserted }
    }
}
