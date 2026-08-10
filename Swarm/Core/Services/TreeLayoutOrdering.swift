import CoreGraphics
import Foundation

/// Phases 2 and 3 of the tidy layout: decide the left-to-right order of every generation,
/// then give each person a cross-axis coordinate.
///
/// The atomic unit of a row is a *spouse block* — a connected component of the marriage
/// graph inside one generation. Keeping a block contiguous is what guarantees partners end
/// up beside each other; ordering blocks by barycenter is what keeps parents above their
/// children and edges short.
///
/// Long edges (a union whose child sits more than one generation below) are broken by dummy
/// vertices on the intervening rows, the standard layered-drawing device. A dummy takes part
/// in ordering and spacing like any other vertex, which reserves a clear vertical corridor
/// for the edge instead of letting it cut through whatever card happens to be in the way.
struct LayoutOrdering {
    struct Block {
        /// People on this row, left → right.
        var members: [UUID]
        let generation: Int
    }

    struct LongEdge {
        let unionIndex: Int
        let childId: UUID
        /// Dummy indices, top row first.
        var dummyIndices: [Int]
    }

    struct Dummy {
        let edgeIndex: Int
        let generation: Int
    }

    enum Vertex: Equatable {
        case block(Int)
        case dummy(Int)
    }

    struct Metrics {
        /// Cross-axis extent of one card: `cardW` top-down, `cardH` left-right.
        var nodeWidth: CGFloat
        var spouseGap: CGFloat
        var siblingGap: CGFloat
        var familyGap: CGFloat
        /// Cross-axis width reserved for a long edge passing through a row.
        var corridorWidth: CGFloat = 8
        /// Clearance either side of a corridor.
        var corridorGap: CGFloat = 40
    }

    private var blocks: [Block] = []
    private var dummies: [Dummy] = []
    private(set) var longEdges: [LongEdge] = []
    /// Ordered vertices per generation.
    private var layers: [[Vertex]] = []
    /// Cross-axis centre of every person's card.
    private(set) var centreOf: [UUID: CGFloat] = [:]
    /// Cross-axis centre of every dummy.
    private(set) var dummyCentre: [CGFloat] = []

    private let graph: LayoutGraph
    private let metrics: Metrics

    init(graph: LayoutGraph, index: FamilyIndex, metrics: Metrics) {
        self.graph = graph
        self.metrics = metrics

        buildBlocks(index: index)
        buildLongEdges()
        seedLayers(homePersonId: index.tree.homePersonId)
        minimizeCrossings()
        assignCoordinates()
    }

    // MARK: - Phase 2a: spouse blocks

    private mutating func buildBlocks(index: FamilyIndex) {
        for generation in 0 ... max(graph.maxGeneration, 0) {
            let people = (graph.peopleByGeneration[generation] ?? [])
                .sorted { lhs, rhs in
                    let l = LayoutGraph.birthKey(index.byId[lhs]!), r = LayoutGraph.birthKey(index.byId[rhs]!)
                    if l != r { return l < r }
                    return lhs.uuidString < rhs.uuidString
                }
            guard !people.isEmpty else { continue }

            // Partners inside this generation only. A union whose partners ended up on
            // different rows cannot be drawn as an adjacency, so it is left to routing.
            var partnersInRow: [UUID: [UUID]] = [:]
            for person in people {
                var neighbours: [(partner: UUID, order: Int)] = []
                for unionIndex in graph.unionIndicesOfPartner[person] ?? [] {
                    let union = graph.unions[unionIndex]
                    for partner in union.partners
                        where partner != person && graph.generationOf[partner] == generation {
                        neighbours.append((partner, unionIndex))
                    }
                }
                partnersInRow[person] = neighbours
                    .sorted { $0.order < $1.order }
                    .map(\.partner)
            }

            var unassigned = Set(people)
            for person in people where unassigned.contains(person) {
                // Grow the component, then order it.
                var component = Set<UUID>()
                var stack = [person]
                while let next = stack.popLast() {
                    guard component.insert(next).inserted else { continue }
                    for partner in partnersInRow[next] ?? [] where !component.contains(partner) {
                        stack.append(partner)
                    }
                }
                unassigned.subtract(component)
                blocks.append(Block(
                    members: orderBlock(component, partners: partnersInRow, index: index),
                    generation: generation
                ))
            }
        }
    }

    /// Order one spouse block.
    ///
    /// A person with N partners can be adjacent to at most two of them, so the pivot sits
    /// in the middle and its partners fan out alternately to either side in marriage order.
    /// That halves the routing work compared with a one-sided chain: the two innermost
    /// marriages need no lane at all, and each further pair shares one lane because the
    /// runs sit on opposite sides. Anyone with marriages of their own continues outward on
    /// the side they were placed, which keeps their own partners adjacent too.
    private func orderBlock(
        _ component: Set<UUID>,
        partners: [UUID: [UUID]],
        index: FamilyIndex
    ) -> [UUID] {
        guard component.count > 1 else { return Array(component) }

        // Male-left / female-right for the plain couple, per the genogram convention.
        if component.count == 2 {
            let pair = component.sorted { $0.uuidString < $1.uuidString }
            let first = index.byId[pair[0]]!, second = index.byId[pair[1]]!
            if first.sex == .female, second.sex == .male { return [pair[1], pair[0]] }
            if first.sex == .male, second.sex == .female { return pair }
            return LayoutGraph.birthKey(first) <= LayoutGraph.birthKey(second) ? pair : [pair[1], pair[0]]
        }

        let pivot = component.sorted { lhs, rhs in
            let degreeL = partners[lhs]?.count ?? 0, degreeR = partners[rhs]?.count ?? 0
            if degreeL != degreeR { return degreeL > degreeR }
            let birthL = LayoutGraph.birthKey(index.byId[lhs]!), birthR = LayoutGraph.birthKey(index.byId[rhs]!)
            if birthL != birthR { return birthL < birthR }
            return lhs.uuidString < rhs.uuidString
        }[0]

        var left: [UUID] = []
        var right: [UUID] = []
        var placed: Set<UUID> = [pivot]
        var frontier: [(person: UUID, toRight: Bool)] = []

        // A female pivot puts her first husband on her left, keeping male-left intact.
        let firstGoesRight = index.byId[pivot]?.sex != .female
        for (offset, partner) in (partners[pivot] ?? []).enumerated() where placed.insert(partner).inserted {
            let toRight = (offset % 2 == 0) == firstGoesRight
            if toRight { right.append(partner) } else { left.append(partner) }
            frontier.append((partner, toRight))
        }

        var head = 0
        while head < frontier.count {
            let (person, toRight) = frontier[head]; head += 1
            for partner in partners[person] ?? [] where placed.insert(partner).inserted {
                if toRight { right.append(partner) } else { left.append(partner) }
                frontier.append((partner, toRight))
            }
        }

        // Anything the marriage walk missed (shouldn't happen — the component is
        // connected through partners) trails on the right so nobody is dropped.
        let stragglers = component.subtracting(placed).sorted { $0.uuidString < $1.uuidString }
        return left.reversed() + [pivot] + right + stragglers
    }

    // MARK: - Phase 2b: long edges and dummy corridors

    private mutating func buildLongEdges() {
        for (unionIndex, union) in graph.unions.enumerated() {
            for child in union.children {
                let childGeneration = graph.generationOf[child] ?? union.generation + 1
                guard childGeneration > union.generation + 1 else { continue }
                var edge = LongEdge(unionIndex: unionIndex, childId: child, dummyIndices: [])
                for generation in (union.generation + 1) ..< childGeneration {
                    edge.dummyIndices.append(dummies.count)
                    dummies.append(Dummy(edgeIndex: longEdges.count, generation: generation))
                }
                longEdges.append(edge)
            }
        }
    }

    // MARK: - Phase 2c: initial layer order

    /// Seed each layer by walking outward from the home couple rather than by birth date.
    ///
    /// A pedigree is the common case and it has a shape the reader expects: the husband's
    /// ancestors all to one side, the wife's all to the other, each branch fanning out
    /// above its own descendant. Barycentre sweeps alone do not preserve that — they judge
    /// each layer on averages and happily interleave the two families, which is what makes
    /// a plain two-sided pedigree read as a jumble.
    ///
    /// Walking the block graph outward from the root and keying each block by its path
    /// makes the ordering hierarchical: sorting a layer by that key keeps every branch
    /// contiguous and the two sides apart. The sweeps then refine it and keep whichever is
    /// better, so this only ever sets a good starting point.
    private mutating func seedLayers(homePersonId: UUID?) {
        let layerCount = max(graph.maxGeneration + 1, 1)
        layers = Array(repeating: [], count: layerCount)

        var blockOf: [UUID: Int] = [:]
        for (index, block) in blocks.enumerated() {
            for member in block.members { blockOf[member] = index }
        }

        /// Parents first, in member order, then children — so a block's two ancestral
        /// branches are discovered left-to-right in the same order its members sit.
        func neighbours(of index: Int) -> [Int] {
            var result: [Int] = []
            var seen: Set<Int> = [index]
            for member in blocks[index].members {
                for unionIndex in graph.unionIndicesOfChild[member] ?? [] {
                    for parent in graph.unions[unionIndex].partners {
                        if let block = blockOf[parent], seen.insert(block).inserted { result.append(block) }
                    }
                }
            }
            for member in blocks[index].members {
                for unionIndex in graph.unionIndicesOfPartner[member] ?? [] {
                    for child in graph.unions[unionIndex].children {
                        if let block = blockOf[child], seen.insert(block).inserted { result.append(block) }
                    }
                }
            }
            return result
        }

        var key: [Int: [Int]] = [:]
        var visited = Set<Int>()
        var component = 0

        func walk(from root: Int) {
            key[root] = [component]
            visited.insert(root)
            var queue = [root]
            var head = 0
            while head < queue.count {
                let node = queue[head]; head += 1
                var rank = 0
                for neighbour in neighbours(of: node) where visited.insert(neighbour).inserted {
                    key[neighbour] = key[node]! + [rank]
                    rank += 1
                    queue.append(neighbour)
                }
            }
            component += 1
        }

        // Start from the home couple so the drawing fans out around the person the reader
        // opened the tree for.
        if let homePersonId, let home = blockOf[homePersonId] { walk(from: home) }
        for index in blocks.indices where !visited.contains(index) { walk(from: index) }

        func rank(_ vertex: Vertex) -> [Int] {
            switch vertex {
            case let .block(index):
                key[index] ?? [Int.max]
            case let .dummy(index):
                // Sit with the branch the edge belongs to.
                key[blockOf[graph.unions[longEdges[dummies[index].edgeIndex].unionIndex].partners[0]] ?? -1]
                    ?? [Int.max]
            }
        }
        func precedes(_ lhs: [Int], _ rhs: [Int]) -> Bool {
            for (l, r) in zip(lhs, rhs) where l != r { return l < r }
            return lhs.count < rhs.count
        }

        for (index, block) in blocks.enumerated() where block.generation < layerCount {
            layers[block.generation].append(.block(index))
        }
        for (index, dummy) in dummies.enumerated() where dummy.generation < layerCount {
            layers[dummy.generation].append(.dummy(index))
        }
        for layer in layers.indices {
            layers[layer].sort { precedes(rank($0), rank($1)) }
        }
    }

    // MARK: - Phase 2d: crossing minimization

    /// Alternating barycenter sweeps, the standard heuristic for the (NP-hard) layer
    /// ordering problem. Best ordering seen wins, so a sweep can never make things worse.
    ///
    /// Ties go to the swept ordering, not the seed. Crossing count alone cannot see that a
    /// brother placed to the right of his married sibling makes the parents' bus reach over
    /// the sister-in-law; the barycentre can, because it pulls him towards the parents he
    /// shares and leaves the spouse on the outside. Both orderings cost the same crossings,
    /// so without this the seed would keep him on the wrong side.
    private mutating func minimizeCrossings() {
        guard layers.count > 1 else { return }

        for round in 0 ..< 12 {
            let downward = round % 2 == 0
            let range = downward
                ? Array(1 ..< layers.count)
                : Array((0 ..< layers.count - 1).reversed())
            var improved = false

            for layerIndex in range {
                let slots = slotMap(layers)
                let reordered = layers[layerIndex].enumerated()
                    .map { ordinal, vertex -> (Vertex, CGFloat, Int) in
                        let bary = barycentre(
                            of: vertex,
                            layerIndex: layerIndex,
                            fromAbove: downward,
                            slots: slots
                        )
                        return (vertex, bary ?? CGFloat(ordinal), ordinal)
                    }
                    // Stable: vertices with no neighbours keep their place.
                    .sorted { lhs, rhs in
                        if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                        return lhs.2 < rhs.2
                    }
                    .map(\.0)
                guard reordered != layers[layerIndex] else { continue }

                let before = layers[layerIndex]
                let beforeCrossings = totalCrossings(layers)
                layers[layerIndex] = reordered
                let afterCrossings = totalCrossings(layers)
                if afterCrossings > beforeCrossings {
                    layers[layerIndex] = before
                } else if afterCrossings < beforeCrossings {
                    improved = true
                }
            }

            // Ordering blocks is not enough: the spouses *inside* a chain also have a
            // left-to-right order, and marriage date alone gets it wrong. A man's first
            // wife may have borne the elder son and his second the younger, in which case
            // seating the wives by date puts each one on the opposite side from her own
            // child and the two descents have to cross.
            if !downward {
                for layerIndex in range where reorderChains(inLayer: layerIndex) {
                    improved = true
                }
            }
            if !improved, round > 1 { break }
        }
    }

    /// Re-seat the members of every spouse chain in a layer so each spouse sits on the
    /// side its own children are on. Returns whether anything improved.
    private mutating func reorderChains(inLayer layerIndex: Int) -> Bool {
        var improved = false
        for vertex in layers[layerIndex] {
            guard case let .block(index) = vertex, blocks[index].members.count > 2 else { continue }
            let slots = slotMap(layers)
            let reordered = chainOrderedByDescendants(index, slots: slots)
            guard reordered != blocks[index].members else { continue }

            let before = blocks[index].members
            let beforeCrossings = totalCrossings(layers)
            blocks[index].members = reordered
            let afterCrossings = totalCrossings(layers)
            if afterCrossings > beforeCrossings {
                blocks[index].members = before
            } else if afterCrossings < beforeCrossings {
                improved = true
            }
        }
        return improved
    }

    /// A chain's members sorted by where their descendants sit. Anyone childless has no
    /// opinion, so they inherit the last position that did and keep their relative place.
    private func chainOrderedByDescendants(_ index: Int, slots: [SlotKey: CGFloat]) -> [UUID] {
        let members = blocks[index].members
        let generation = blocks[index].generation

        var keys: [UUID: CGFloat] = [:]
        for member in members {
            var samples: [CGFloat] = []
            for unionIndex in graph.unionIndicesOfPartner[member] ?? [] {
                for target in targets(ofUnion: unionIndex, atLayer: generation + 1) {
                    if let slot = slots[target] { samples.append(slot) }
                }
            }
            if !samples.isEmpty { keys[member] = samples.reduce(0, +) / CGFloat(samples.count) }
        }
        guard keys.count > 1 else { return members }

        var carried = keys[members[0]] ?? 0
        let ranked = members.enumerated().map { offset, member -> (UUID, CGFloat, Int) in
            if let key = keys[member] { carried = key }
            return (member, carried, offset)
        }
        return ranked.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return lhs.2 < rhs.2
        }.map(\.0)
    }

    /// Continuous position of every person and dummy within its layer, used as the
    /// barycentre coordinate. A person's slot is its block's index plus its offset inside
    /// the block, so a spouse chain contributes distinct positions.
    private func slotMap(_ layers: [[Vertex]]) -> [SlotKey: CGFloat] {
        var slots: [SlotKey: CGFloat] = [:]
        for layer in layers {
            for (ordinal, vertex) in layer.enumerated() {
                switch vertex {
                case let .block(index):
                    let members = blocks[index].members
                    for (offset, person) in members.enumerated() {
                        slots[.person(person)] = CGFloat(ordinal)
                            + (CGFloat(offset) + 0.5) / CGFloat(members.count)
                    }
                case let .dummy(index):
                    slots[.dummy(index)] = CGFloat(ordinal) + 0.5
                }
            }
        }
        return slots
    }

    enum SlotKey: Hashable {
        case person(UUID)
        case dummy(Int)
    }

    /// Where a union's connector meets the row its partners are on.
    private func unionSlot(_ unionIndex: Int, slots: [SlotKey: CGFloat]) -> CGFloat? {
        let positions = graph.unions[unionIndex].partners.compactMap { slots[.person($0)] }
        guard !positions.isEmpty else { return nil }
        return positions.reduce(0, +) / CGFloat(positions.count)
    }

    private func barycentre(
        of vertex: Vertex,
        layerIndex: Int,
        fromAbove: Bool,
        slots: [SlotKey: CGFloat]
    ) -> CGFloat? {
        var samples: [CGFloat] = []
        switch vertex {
        case let .block(index):
            for person in blocks[index].members {
                if fromAbove {
                    for unionIndex in graph.unionIndicesOfChild[person] ?? [] {
                        guard graph.unions[unionIndex].generation == layerIndex - 1 else { continue }
                        if let slot = unionSlot(unionIndex, slots: slots) { samples.append(slot) }
                    }
                } else {
                    for unionIndex in graph.unionIndicesOfPartner[person] ?? [] {
                        for target in targets(ofUnion: unionIndex, atLayer: layerIndex + 1) {
                            if let slot = slots[target] { samples.append(slot) }
                        }
                    }
                }
            }
        case let .dummy(index):
            let dummy = dummies[index]
            let edge = longEdges[dummy.edgeIndex]
            guard let position = edge.dummyIndices.firstIndex(of: index) else { return nil }
            if fromAbove {
                if position == 0 {
                    if let slot = unionSlot(edge.unionIndex, slots: slots) { samples.append(slot) }
                } else if let slot = slots[.dummy(edge.dummyIndices[position - 1])] {
                    samples.append(slot)
                }
            } else {
                if position == edge.dummyIndices.count - 1 {
                    if let slot = slots[.person(edge.childId)] { samples.append(slot) }
                } else if let slot = slots[.dummy(edge.dummyIndices[position + 1])] {
                    samples.append(slot)
                }
            }
        }
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0, +) / CGFloat(samples.count)
    }

    /// What a union connects down to on `layer` — the child itself, or the dummy standing
    /// in for it when the child is further below.
    private func targets(ofUnion unionIndex: Int, atLayer layer: Int) -> [SlotKey] {
        let union = graph.unions[unionIndex]
        guard union.generation + 1 == layer else { return [] }
        var result: [SlotKey] = []
        for child in union.children {
            if let edge = longEdges.first(where: { $0.unionIndex == unionIndex && $0.childId == child }),
               let first = edge.dummyIndices.first {
                result.append(.dummy(first))
            } else {
                result.append(.person(child))
            }
        }
        return result
    }

    private func totalCrossings(_ layers: [[Vertex]]) -> Int {
        let slots = slotMap(layers)
        var total = 0
        for layerIndex in 0 ..< max(layers.count - 1, 0) {
            var pairs: [(CGFloat, CGFloat)] = []
            for vertex in layers[layerIndex] {
                switch vertex {
                case let .block(index):
                    for person in blocks[index].members {
                        for unionIndex in graph.unionIndicesOfPartner[person] ?? [] {
                            guard let from = unionSlot(unionIndex, slots: slots) else { continue }
                            for target in targets(ofUnion: unionIndex, atLayer: layerIndex + 1) {
                                if let to = slots[target] { pairs.append((from, to)) }
                            }
                        }
                    }
                case let .dummy(index):
                    let dummy = dummies[index]
                    let edge = longEdges[dummy.edgeIndex]
                    guard let position = edge.dummyIndices.firstIndex(of: index),
                          let from = slots[.dummy(index)] else { continue }
                    let next: SlotKey = position == edge.dummyIndices.count - 1
                        ? .person(edge.childId)
                        : .dummy(edge.dummyIndices[position + 1])
                    if let to = slots[next] { pairs.append((from, to)) }
                }
            }
            pairs.sort { $0.0 < $1.0 }
            for i in 0 ..< pairs.count {
                for j in (i + 1) ..< pairs.count where pairs[j].1 < pairs[i].1 {
                    total += 1
                }
            }
        }
        return total
    }

    // MARK: - Phase 3: cross-axis coordinates

    private mutating func assignCoordinates() {
        dummyCentre = Array(repeating: 0, count: dummies.count)
        var centres: [[CGFloat]] = layers.map { Array(repeating: 0, count: $0.count) }

        // Pack every layer left to right at minimum separation.
        for (layerIndex, layer) in layers.enumerated() {
            var cursor: CGFloat = 0
            for (ordinal, vertex) in layer.enumerated() {
                let half = extent(of: vertex) / 2
                if ordinal > 0 {
                    cursor += separation(layer[ordinal - 1], vertex) + half
                } else {
                    cursor = half
                }
                centres[layerIndex][ordinal] = cursor
                cursor += half
            }
        }

        // Alternating refinement. Parents are pulled over their children and children
        // under their parents; the priority pass keeps every move inside the separation
        // constraints, so no amount of pulling can make two cards touch.
        for round in 0 ..< 8 {
            let downward = round % 2 == 0
            let range = downward
                ? Array(1 ..< max(layers.count, 1))
                : Array((0 ..< max(layers.count - 1, 0)).reversed())
            for layerIndex in range {
                publish(centres)
                let desired = desiredCentres(layerIndex: layerIndex, fromAbove: downward, current: centres)
                centres[layerIndex] = applyPriority(
                    layerIndex: layerIndex,
                    current: centres[layerIndex],
                    desired: desired
                )
            }
        }
        publish(centres)
    }

    /// Copy layer coordinates out to the person/dummy maps the rest of the engine reads.
    private mutating func publish(_ centres: [[CGFloat]]) {
        for (layerIndex, layer) in layers.enumerated() {
            for (ordinal, vertex) in layer.enumerated() {
                let centre = centres[layerIndex][ordinal]
                switch vertex {
                case let .block(index):
                    let members = blocks[index].members
                    let width = extent(of: vertex)
                    var cursor = centre - width / 2 + metrics.nodeWidth / 2
                    for person in members {
                        centreOf[person] = cursor
                        cursor += metrics.nodeWidth + metrics.spouseGap
                    }
                case let .dummy(index):
                    dummyCentre[index] = centre
                }
            }
        }
    }

    /// Target position for each vertex, expressed as the move that would centre its
    /// connectors. Using the connector offset rather than a raw barycentre is what makes a
    /// couple sit above the middle of *their* children even inside a longer spouse chain.
    private func desiredCentres(layerIndex: Int, fromAbove: Bool, current: [[CGFloat]]) -> [CGFloat] {
        var result = current[layerIndex]
        for (ordinal, vertex) in layers[layerIndex].enumerated() {
            var offsets: [CGFloat] = []
            switch vertex {
            case let .block(index):
                for person in blocks[index].members {
                    guard let personCentre = centreOf[person] else { continue }
                    if fromAbove {
                        for unionIndex in graph.unionIndicesOfChild[person] ?? [] {
                            guard graph.unions[unionIndex].generation == layerIndex - 1,
                                  let anchor = unionAnchor(unionIndex) else { continue }
                            offsets.append(anchor - personCentre)
                        }
                    } else {
                        for unionIndex in graph.unionIndicesOfPartner[person] ?? [] {
                            guard let anchor = unionAnchor(unionIndex),
                                  graph.unions[unionIndex].generation == layerIndex else { continue }
                            let below = descendantCentres(ofUnion: unionIndex)
                            guard !below.isEmpty else { continue }
                            offsets.append(below.reduce(0, +) / CGFloat(below.count) - anchor)
                        }
                    }
                }
            case let .dummy(index):
                let dummy = dummies[index]
                let edge = longEdges[dummy.edgeIndex]
                guard let position = edge.dummyIndices.firstIndex(of: index) else { continue }
                let neighbour: CGFloat? = if fromAbove {
                    position == 0
                        ? unionAnchor(edge.unionIndex)
                        : dummyCentre[edge.dummyIndices[position - 1]]
                } else {
                    position == edge.dummyIndices.count - 1
                        ? centreOf[edge.childId]
                        : dummyCentre[edge.dummyIndices[position + 1]]
                }
                if let neighbour { offsets.append(neighbour - dummyCentre[index]) }
            }
            guard !offsets.isEmpty else { continue }
            result[ordinal] += offsets.reduce(0, +) / CGFloat(offsets.count)
        }
        return result
    }

    private func descendantCentres(ofUnion unionIndex: Int) -> [CGFloat] {
        var result: [CGFloat] = []
        for child in graph.unions[unionIndex].children {
            if let edge = longEdges.first(where: { $0.unionIndex == unionIndex && $0.childId == child }),
               let first = edge.dummyIndices.first {
                result.append(dummyCentre[first])
            } else if let centre = centreOf[child] {
                result.append(centre)
            }
        }
        return result
    }

    /// Priority method: move vertices toward their targets in priority order, pushing
    /// lower-priority neighbours along but never crossing an already-settled one. Dummies
    /// go first so long edges stay straight instead of zig-zagging around cards.
    private func applyPriority(layerIndex: Int, current: [CGFloat], desired: [CGFloat]) -> [CGFloat] {
        let layer = layers[layerIndex]
        guard layer.count > 1 else { return desired }
        var x = current
        var settled = Set<Int>()

        let order = layer.indices.sorted { lhs, rhs in
            let pl = priority(of: layer[lhs]), pr = priority(of: layer[rhs])
            if pl != pr { return pl > pr }
            return lhs < rhs
        }

        for index in order {
            defer { settled.insert(index) }
            let delta = desired[index] - x[index]
            guard abs(delta) > 0.01 else { continue }

            if delta > 0 {
                // Slack available before the nearest settled vertex on the right.
                var slack: CGFloat = 0
                var blocked = false
                for j in (index + 1) ..< layer.count {
                    slack += x[j] - x[j - 1] - separation(layer[j - 1], layer[j])
                        - (extent(of: layer[j - 1]) + extent(of: layer[j])) / 2
                    if settled.contains(j) { blocked = true; break }
                }
                let move = blocked ? min(delta, max(0, slack)) : delta
                x[index] += move
                for j in (index + 1) ..< layer.count {
                    x[j] = max(x[j], x[j - 1] + minimumStride(layer[j - 1], layer[j]))
                }
            } else {
                var slack: CGFloat = 0
                var blocked = false
                for j in stride(from: index - 1, through: 0, by: -1) {
                    slack += x[j + 1] - x[j] - separation(layer[j], layer[j + 1])
                        - (extent(of: layer[j]) + extent(of: layer[j + 1])) / 2
                    if settled.contains(j) { blocked = true; break }
                }
                let move = blocked ? min(-delta, max(0, slack)) : -delta
                x[index] -= move
                for j in stride(from: index - 1, through: 0, by: -1) {
                    x[j] = min(x[j], x[j + 1] - minimumStride(layer[j], layer[j + 1]))
                }
            }
        }
        return x
    }

    private func priority(of vertex: Vertex) -> Int {
        switch vertex {
        case .dummy: 1_000_000
        case let .block(index):
            blocks[index].members.reduce(0) { total, person in
                total + (graph.unionIndicesOfPartner[person]?.count ?? 0)
                    + (graph.unionIndicesOfChild[person]?.count ?? 0)
            }
        }
    }

    private func minimumStride(_ left: Vertex, _ right: Vertex) -> CGFloat {
        (extent(of: left) + extent(of: right)) / 2 + separation(left, right)
    }

    private func extent(of vertex: Vertex) -> CGFloat {
        switch vertex {
        case .dummy: return metrics.corridorWidth
        case let .block(index):
            let count = CGFloat(max(blocks[index].members.count, 1))
            return count * metrics.nodeWidth + (count - 1) * metrics.spouseGap
        }
    }

    /// Siblings pack tighter than strangers, so a sibling set reads as one group. A
    /// corridor only needs enough clearance that its line does not graze a card.
    private func separation(_ left: Vertex, _ right: Vertex) -> CGFloat {
        guard case let .block(l) = left, case let .block(r) = right else {
            return metrics.corridorGap
        }
        let leftUnions = Set(blocks[l].members.flatMap { graph.unionIndicesOfChild[$0] ?? [] })
        let rightUnions = Set(blocks[r].members.flatMap { graph.unionIndicesOfChild[$0] ?? [] })
        return leftUnions.isDisjoint(with: rightUnions) ? metrics.familyGap : metrics.siblingGap
    }

    // MARK: - Read-out

    /// Cross-axis centre of a union's connector: the midpoint of its partners.
    func unionAnchor(_ unionIndex: Int) -> CGFloat? {
        let positions = graph.unions[unionIndex].partners.compactMap { centreOf[$0] }
        guard !positions.isEmpty else { return nil }
        return positions.reduce(0, +) / CGFloat(positions.count)
    }

    /// True when a union's partners are neighbours in their block, which is what lets its
    /// marriage line and glyph sit on the row instead of being routed through a lane.
    func partnersAreAdjacent(_ unionIndex: Int) -> Bool {
        let partners = graph.unions[unionIndex].partners
        guard partners.count == 2 else { return true }
        for block in blocks {
            guard let first = block.members.firstIndex(of: partners[0]),
                  let second = block.members.firstIndex(of: partners[1]) else { continue }
            return abs(first - second) == 1
        }
        return false
    }

    /// The spouse chain a union sits in, when that chain holds more than one marriage.
    ///
    /// Everything in such a chain is routed the same way: a person with several spouses
    /// should not have one marriage drawn as a line between cards and the rest as elbows
    /// through the band. Returns nil for a plain couple, which keeps its line on the row.
    func spouseChain(ofUnion unionIndex: Int) -> [UUID]? {
        let partners = graph.unions[unionIndex].partners
        guard partners.count == 2 else { return nil }
        guard let block = blocks.first(where: { block in
            partners.allSatisfy(block.members.contains)
        }), block.members.count > 2 else { return nil }
        return block.members
    }

    /// Every spouse chain that carries more than one marriage, as (generation, members).
    var spouseChains: [(generation: Int, members: [UUID])] {
        blocks.filter { $0.members.count > 2 }.map { ($0.generation, $0.members) }
    }

    /// Index of the long edge from a union to one of its children, when that child sits
    /// more than one row below. Callers want the index as well as the edge, so they
    /// subscript `longEdges` with it.
    func longEdgeIndex(unionIndex: Int, childId: UUID) -> Int? {
        longEdges.firstIndex { $0.unionIndex == unionIndex && $0.childId == childId }
    }
}
