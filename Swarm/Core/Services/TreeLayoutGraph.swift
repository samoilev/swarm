import Foundation

/// Phase 1 of the tidy layout: the genealogy as a bipartite person/union graph with a
/// generation assigned to every person.
///
/// A genealogy is a DAG, not a tree — everyone has two parents, and a couple can appear
/// in several unions — so the layout models the union as a first-class node and never
/// connects two people directly. That is the structure layered graph drawing needs, and
/// the same one GEDCOM already uses (INDI records joined through FAM records).
///
/// Generations come from longest-path layering over *generation classes* rather than a
/// breadth-first walk. BFS fixes a depth on first visit, so whichever path happens to
/// arrive first wins and later constraints are silently dropped; longest path satisfies
/// every parent-before-child constraint at once.
struct LayoutGraph {
    struct UnionNode {
        let id: UUID
        /// 1 or 2 partner ids, ordered male-left / female-right when sex is known.
        let partners: [UUID]
        /// Children sorted oldest-first, per the genealogical convention.
        let children: [UUID]
        /// Row the partners sit on. When a merge was refused and the partners ended up on
        /// different rows — an uncle–niece marriage, say — this is the upper of the two,
        /// and routing draws the marriage through a lane rather than along the row.
        let generation: Int
    }

    private(set) var generationOf: [UUID: Int] = [:]
    private(set) var unions: [UnionNode] = []
    /// Person → indices into `unions`, in marriage order. Drives the spouse-chain layout.
    private(set) var unionIndicesOfPartner: [UUID: [Int]] = [:]
    /// Person → indices into `unions` that list them as a child.
    private(set) var unionIndicesOfChild: [UUID: [Int]] = [:]
    private(set) var peopleByGeneration: [Int: [UUID]] = [:]
    private(set) var maxGeneration = 0

    init(tree: FamilyTree, index: FamilyIndex) {
        // Only unions with at least one placeable partner take part; a childless,
        // partnerless record has nothing to draw.
        let rawUnions = tree.unions.filter { union in
            union.partnerIds.contains { index.byId[$0] != nil }
        }

        let fileOrder = Dictionary(uniqueKeysWithValues: rawUnions.enumerated().map { ($0.element.id, $0.offset) })
        let sortedUnions = rawUnions.sorted { lhs, rhs in
            let l = Self.marriageKey(lhs), r = Self.marriageKey(rhs)
            if l != r { return l < r }
            return fileOrder[lhs.id]! < fileOrder[rhs.id]!
        }

        generationOf = Self.assignGenerations(tree: tree, index: index, unions: sortedUnions)

        for union in sortedUnions {
            let partners = Self.orderedPartners(of: union, index: index)
            guard let first = partners.first else { continue }
            let children = union.childrenIds
                .filter { index.byId[$0] != nil }
                .sorted { Self.birthKey(index.byId[$0]!) < Self.birthKey(index.byId[$1]!) }

            let generation = partners.compactMap { generationOf[$0] }.min() ?? generationOf[first] ?? 0
            let node = UnionNode(
                id: union.id,
                partners: partners,
                children: children,
                generation: generation
            )
            let idx = unions.count
            unions.append(node)
            for partner in partners { unionIndicesOfPartner[partner, default: []].append(idx) }
            for child in children { unionIndicesOfChild[child, default: []].append(idx) }
        }

        for person in tree.people {
            let generation = generationOf[person.id] ?? 0
            generationOf[person.id] = generation
            peopleByGeneration[generation, default: []].append(person.id)
            maxGeneration = max(maxGeneration, generation)
        }
    }

    // MARK: - Generation assignment

    /// Longest-path layering over generation classes.
    ///
    /// 1. Layer on parent→child edges alone (a DAG; any back edge is corrupt data and is
    ///    dropped, which `TreeValidator.ancestryCycles` reports separately).
    /// 2. Merge each union's partners into one class, strongest union first, but only when
    ///    the merge keeps the class graph acyclic. A merge that would create a cycle is
    ///    refused and the union is marked as spanning generations.
    /// 3. Longest-path layer the surviving class graph.
    ///
    /// Merges are attempted in a fixed order — most children, then earliest marriage, then
    /// file order — so the result is deterministic and the union that matters most to the
    /// drawing is the one that gets its partners aligned.
    private static func assignGenerations(
        tree: FamilyTree,
        index: FamilyIndex,
        unions: [Union]
    ) -> [UUID: Int] {
        var dsu = DisjointSet(tree.people.map(\.id))

        // Parent → child edges, deduplicated. These are the hard constraints.
        var childEdges: [(parent: UUID, child: UUID)] = []
        for union in unions {
            let partners = union.partnerIds.filter { index.byId[$0] != nil }
            for child in union.childrenIds where index.byId[child] != nil {
                for parent in partners where parent != child {
                    childEdges.append((parent, child))
                }
            }
        }

        // Step 2: greedy merges, each guarded by an acyclicity check. Two people share a
        // generation when they are married or when they are siblings — the sibling rule
        // matters because otherwise a brother who married into a shallower family drags
        // himself, and then his parents, off his sister's row.
        //
        // Siblings first: it is the constraint the reader is least willing to see broken,
        // and a refused merge only ever shows up as a routed marriage line.
        // Every child of one person is the same generation, half-siblings included — a
        // parent's two families belong on one row, not stepped.
        var merges: [(UUID, UUID)] = []
        var childrenOfParent: [UUID: [UUID]] = [:]
        for union in unions {
            let children = union.childrenIds.filter { index.byId[$0] != nil }
            guard !children.isEmpty else { continue }
            for parent in union.partnerIds where index.byId[parent] != nil {
                childrenOfParent[parent, default: []].append(contentsOf: children)
            }
            for sibling in children.dropFirst() { merges.append((children[0], sibling)) }
        }
        for (_, children) in childrenOfParent where children.count > 1 {
            for sibling in children.dropFirst() { merges.append((children[0], sibling)) }
        }
        let partnerMerges = unions
            .filter { $0.partnerIds.filter { index.byId[$0] != nil }.count == 2 }
            .sorted { $0.childrenIds.count > $1.childrenIds.count }
            .map { union -> (UUID, UUID) in
                let partners = union.partnerIds.filter { index.byId[$0] != nil }
                return (partners[0], partners[1])
            }
        merges.append(contentsOf: partnerMerges)

        for (a, b) in merges where a != b {
            guard dsu.find(a) != dsu.find(b) else { continue }
            // A refused merge leaves the two in different classes, which surfaces later as
            // differing generations — exactly what `spansGenerations` reports.
            var trial = dsu
            trial.union(a, b)
            if classGraphIsAcyclic(edges: childEdges, dsu: &trial) { dsu = trial }
        }

        // Step 3: longest path over the (now acyclic) class graph.
        var successors: [UUID: Set<UUID>] = [:]
        var indegree: [UUID: Int] = [:]
        var classes = Set<UUID>()
        for person in tree.people { classes.insert(dsu.find(person.id)) }
        for cls in classes { indegree[cls] = 0 }
        for edge in childEdges {
            let from = dsu.find(edge.parent), to = dsu.find(edge.child)
            guard from != to else { continue }
            if successors[from, default: []].insert(to).inserted {
                indegree[to, default: 0] += 1
            }
        }

        var generation: [UUID: Int] = [:]
        var queue = classes.filter { indegree[$0] == 0 }.sorted { $0.uuidString < $1.uuidString }
        for cls in queue { generation[cls] = 0 }
        var head = 0
        while head < queue.count {
            let cls = queue[head]; head += 1
            let base = generation[cls] ?? 0
            for next in (successors[cls] ?? []).sorted(by: { $0.uuidString < $1.uuidString }) {
                generation[next] = max(generation[next] ?? 0, base + 1)
                indegree[next]! -= 1
                if indegree[next] == 0 { queue.append(next) }
            }
        }
        // Anything left has indegree > 0 inside a residual cycle: place it below its
        // deepest reachable predecessor rather than dropping it.
        for cls in classes where generation[cls] == nil { generation[cls] = 0 }

        // Longest path only sets a *lower* bound, which strands a shallow branch at the
        // top of the drawing: a wife whose parents have no recorded ancestors would sit
        // her parents on row 0 while her husband's parents sit on row 5. Pull every class
        // down until it rests directly above its highest child, so both sets of
        // grandparents share a row. Monotone and bounded, so it always settles.
        let topological = queue // already in topological order from the walk above
        var settled = false
        while !settled {
            settled = true
            for cls in topological.reversed() {
                let children = successors[cls] ?? []
                guard !children.isEmpty else { continue }
                guard let lowest = children.compactMap({ generation[$0] }).min() else { continue }
                if lowest - 1 > generation[cls]! {
                    generation[cls] = lowest - 1
                    settled = false
                }
            }
        }

        var byPerson: [UUID: Int] = [:]
        for person in tree.people {
            byPerson[person.id] = generation[dsu.find(person.id)] ?? 0
        }
        // Pulling down can leave the top row empty; re-seat the drawing at row 0.
        if let top = byPerson.values.min(), top > 0 {
            for (person, row) in byPerson { byPerson[person] = row - top }
        }

        return byPerson
    }

    /// DFS cycle check over the class graph induced by `dsu`.
    private static func classGraphIsAcyclic(
        edges: [(parent: UUID, child: UUID)],
        dsu: inout DisjointSet
    ) -> Bool {
        var adjacency: [UUID: [UUID]] = [:]
        var nodes = Set<UUID>()
        for edge in edges {
            let from = dsu.find(edge.parent), to = dsu.find(edge.child)
            nodes.insert(from); nodes.insert(to)
            guard from != to else { return false } // a person in their own parent's class
            adjacency[from, default: []].append(to)
        }

        // 0 = unvisited, 1 = on stack, 2 = done. Iterative: deep pedigrees blow a
        // recursive DFS on large imports.
        var state: [UUID: Int] = [:]
        for start in nodes.sorted(by: { $0.uuidString < $1.uuidString }) where state[start] == nil {
            var stack: [(node: UUID, next: Int)] = [(start, 0)]
            state[start] = 1
            while let top = stack.last {
                let neighbours = adjacency[top.node] ?? []
                if top.next < neighbours.count {
                    stack[stack.count - 1].next += 1
                    let child = neighbours[top.next]
                    switch state[child] {
                    case 1: return false
                    case 2: continue
                    default:
                        state[child] = 1
                        stack.append((child, 0))
                    }
                } else {
                    state[top.node] = 2
                    stack.removeLast()
                }
            }
        }
        return true
    }

    // MARK: - Ordering keys

    /// Father-left / mother-right, matching the genogram convention. Unknown sex keeps
    /// the recorded order so imports stay stable.
    private static func orderedPartners(of union: Union, index: FamilyIndex) -> [UUID] {
        let partners = union.partnerIds.filter { index.byId[$0] != nil }
        guard partners.count == 2 else { return partners }
        let first = index.byId[partners[0]]!, second = index.byId[partners[1]]!
        if first.sex == .female, second.sex == .male { return [partners[1], partners[0]] }
        return partners
    }

    /// Sortable year-month-day. Missing or unparseable dates sort last so that dated
    /// records keep their true order and undated ones trail in file order.
    static func sortKey(_ date: GenealogyDate?) -> Int {
        guard let part = date?.start else { return .max }
        return part.year * 10000 + (part.month ?? 0) * 100 + (part.day ?? 0)
    }

    static func marriageKey(_ union: Union) -> Int {
        sortKey(union.event(ofKind: .marriage)?.date ?? union.marriageDate.map { GenealogyDate(userInput: $0) })
    }

    static func birthKey(_ person: Person) -> Int {
        sortKey(
            person.events.first { $0.kind == .birth }?.date
                ?? person.birthDate.map { GenealogyDate(userInput: $0) }
        )
    }
}

/// Union-find over person ids, used to group people who must share a generation.
struct DisjointSet {
    private var parent: [UUID: UUID] = [:]
    private var rank: [UUID: Int] = [:]

    init(_ elements: [UUID]) {
        for element in elements {
            parent[element] = element
            rank[element] = 0
        }
    }

    mutating func find(_ element: UUID) -> UUID {
        guard var root = parent[element] else {
            parent[element] = element
            rank[element] = 0
            return element
        }
        while root != parent[root]! { root = parent[root]! }
        // Path compression.
        var walk = element
        while walk != root {
            let next = parent[walk]!
            parent[walk] = root
            walk = next
        }
        return root
    }

    mutating func union(_ a: UUID, _ b: UUID) {
        let ra = find(a), rb = find(b)
        guard ra != rb else { return }
        let rankA = rank[ra]!, rankB = rank[rb]!
        if rankA < rankB {
            parent[ra] = rb
        } else if rankA > rankB {
            parent[rb] = ra
        } else {
            parent[rb] = ra
            rank[ra] = rankA + 1
        }
    }
}
