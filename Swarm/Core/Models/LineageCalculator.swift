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
        public var connections: Set<FamilyConnection>
    }

    public func compute(
        for person: Person,
        language: AppLanguage = .current
    ) -> LineageResult {
        var ids: Set<UUID> = [person.id]
        var descriptors: [UUID: KinshipDescriptor] = [:]
        var connections: Set<FamilyConnection> = []
        var ancestorVisited: Set<UUID> = [person.id]
        var descendantVisited: Set<UUID> = [person.id]

        computeAncestors(
            personID: person.id,
            generation: 1,
            parentage: [],
            visited: &ancestorVisited,
            ids: &ids,
            descriptors: &descriptors,
            connections: &connections
        )
        computeDescendants(
            personID: person.id,
            generation: 1,
            parentage: [],
            visited: &descendantVisited,
            ids: &ids,
            descriptors: &descriptors,
            connections: &connections
        )

        for spouse in index.spousesOf(person) {
            ids.insert(spouse.id)
            descriptors[spouse.id] = .spouse(sex: spouse.sex)
            connections.insert(FamilyConnection(person.id, spouse.id))
        }

        // A pair of direct ancestors reads as one family unit in the drawing. Include
        // their marriage connector only when a traversed parent-child relationship
        // actually passes through that union; unrelated spouse branches stay out.
        for union in index.tree.unions {
            let partners = union.partnerIds.filter { ids.contains($0) }
            guard partners.count == 2 else { continue }
            let hasTraversedChild = union.childrenIds.contains { childID in
                partners.contains { parentID in
                    connections.contains(FamilyConnection(parentID, childID))
                }
            }
            if hasTraversedChild {
                connections.insert(FamilyConnection(partners[0], partners[1]))
            }
        }

        let formatter = KinshipFormatter(language: language, style: .lineage)
        var labels = descriptors.mapValues(formatter.label)
        labels[person.id] = L10n.tr("Я", language: language)
        return LineageResult(
            ids: ids,
            labels: labels,
            descriptors: descriptors,
            connections: connections
        )
    }

    private func computeAncestors(
        personID: UUID,
        generation: Int,
        parentage: [ParentageKind],
        visited: inout Set<UUID>,
        ids: inout Set<UUID>,
        descriptors: inout [UUID: KinshipDescriptor],
        connections: inout Set<FamilyConnection>
    ) {
        for edge in index.parentEdges(of: personID) {
            guard let parent = index.byId[edge.parentID],
                  visited.insert(parent.id).inserted else { continue }
            let pathKinds = uniqueParentage(
                parentage + (edge.kind == .biological ? [] : [edge.kind])
            )
            ids.insert(parent.id)
            connections.insert(FamilyConnection(parent.id, personID))
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
                descriptors: &descriptors,
                connections: &connections
            )
        }
    }

    private func computeDescendants(
        personID: UUID,
        generation: Int,
        parentage: [ParentageKind],
        visited: inout Set<UUID>,
        ids: inout Set<UUID>,
        descriptors: inout [UUID: KinshipDescriptor],
        connections: inout Set<FamilyConnection>
    ) {
        for edge in index.childEdges(of: personID) {
            guard let child = index.byId[edge.childID],
                  visited.insert(child.id).inserted else { continue }
            let pathKinds = uniqueParentage(
                parentage + (edge.kind == .biological ? [] : [edge.kind])
            )
            ids.insert(child.id)
            connections.insert(FamilyConnection(personID, child.id))
            descriptors[child.id] = generation == 1
                ? .child(sex: child.sex, kind: edge.kind)
                : qualified(
                    .descendant(generation: generation, sex: child.sex),
                    by: pathKinds
                )

            for spouse in index.spousesOf(child) {
                ids.insert(spouse.id)
                connections.insert(FamilyConnection(child.id, spouse.id))
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
                descriptors: &descriptors,
                connections: &connections
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
