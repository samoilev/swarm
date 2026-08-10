import CoreGraphics
import Foundation

/// Phase 4 of the tidy layout: route every connector through reserved lanes so that no
/// line is ever drawn across a card.
///
/// Each inter-generation gap owns a band of horizontal lanes. A union claims **one** lane
/// for everything it needs to say — the marriage line when its partners are not
/// neighbours, and the bus out to its children — so a marriage and its descent share a
/// single horizontal instead of stacking two. Lanes are handed out by greedy interval
/// colouring. Because lanes live strictly between rows and cards live strictly inside
/// them, a line can only meet a card at its own endpoint.
///
/// The gap grows when a band needs more lanes than fit, which is why generation offsets
/// are a table rather than one constant step.
struct LayoutRouting {
    struct Metrics {
        /// Main-axis size of a card: `cardH` top-down, `cardW` left-right.
        var rowExtent: CGFloat
        /// Cross-axis size of a card.
        var crossExtent: CGFloat
        var minimumGap: CGFloat
        var pad: CGFloat
        /// Distance from the row edge to the first lane.
        var laneInset: CGFloat = 46
        var laneSpacing: CGFloat = 16
        /// Clearance between the last lane and the next row.
        var laneTail: CGFloat = 22
        /// Cross-axis gap two runs must leave between them to share a lane. Without it,
        /// one family's bus can end exactly where an unrelated family's begins and the two
        /// read as a single line — a sibling of the couple on the left appears to be a
        /// child of the couple on the right.
        var laneClearance: CGFloat = 30
    }

    /// Points are in layout space: `x` is the cross axis, `y` the generation axis. The
    /// engine maps them to screen coordinates, so routing never has to know the direction.
    private(set) var generationOffset: [CGFloat] = []
    private(set) var links: [TreeLink] = []
    private(set) var highlightRoutes: [TreeHighlightRoute] = []
    private(set) var unionAnchors: [TreeLayout.UnionAnchor] = []
    private(set) var totalExtent: CGFloat = 0

    private let graph: LayoutGraph
    private let ordering: LayoutOrdering
    private let metrics: Metrics

    private struct Run {
        let gap: Int
        let lo: CGFloat
        let hi: CGFloat
        /// Cross-axis positions where a line drops *into* this lane from the row above.
        let entries: [CGFloat]
        /// Positions where a line leaves this lane heading down to the next row.
        let exits: [CGFloat]
        var lane: Int = 0
    }

    /// One run per union carries its marriage line and its child bus on the same
    /// horizontal. Long edges add a leg in each further gap they cross.
    private var unionRun: [Int: Int] = [:]
    /// Spouse chain members → the run carrying that chain's shared marriage line.
    private var chainRun: [[UUID]: Int] = [:]
    private var edgeRun: [EdgeLeg: Int] = [:]
    private var runs: [Run] = []

    private struct EdgeLeg: Hashable {
        let edgeIndex: Int
        let gap: Int
    }

    init(graph: LayoutGraph, ordering: LayoutOrdering, metrics: Metrics) {
        self.graph = graph
        self.ordering = ordering
        self.metrics = metrics

        collectRuns()
        allocateLanes()
        computeGenerationOffsets()
        emitConnectors()
    }

    // MARK: - Runs

    private mutating func collectRuns() {
        // One shared line per spouse chain. A hub with six marriages would otherwise stack
        // six horizontals under the row; merging them into a single line that every spouse
        // drops onto keeps the band readable and, just as importantly, draws all of that
        // person's marriages the same way instead of two on the row and four below it.
        for chain in ordering.spouseChains {
            let positions = chain.members.compactMap { ordering.centreOf[$0] }
            guard positions.count > 2 else { continue }
            chainRun[chain.members] = addRun(
                gap: chain.generation,
                lo: positions.min()!,
                hi: positions.max()!,
                entries: positions,
                exits: []
            )
        }

        for (unionIndex, union) in graph.unions.enumerated() {
            guard let anchor = ordering.unionAnchor(unionIndex) else { continue }
            let partnerPositions = union.partners.compactMap { ordering.centreOf[$0] }
            let inChain = ordering.spouseChain(ofUnion: unionIndex).flatMap { chainRun[$0] } != nil
            let routedMarriage = !inChain
                && union.partners.count == 2
                && partnerPositions.count == 2
                && !ordering.partnersAreAdjacent(unionIndex)

            // Everything this union's own line has to reach on the cross axis. A chained
            // marriage already has its line, so only the descent is left.
            var span: [CGFloat] = [anchor]
            if routedMarriage || union.partners.count == 1 {
                span.append(contentsOf: partnerPositions)
            }

            for child in union.children {
                if let edgeIndex = ordering.longEdgeIndex(unionIndex: unionIndex, childId: child) {
                    let edge = ordering.longEdges[edgeIndex]
                    let waypoints = legWaypoints(edge: edge)
                    if let first = waypoints.first { span.append(first) }
                    for offset in edge.dummyIndices.indices {
                        let gapIndex = union.generation + 1 + offset
                        let from = waypoints[offset], to = waypoints[offset + 1]
                        edgeRun[EdgeLeg(edgeIndex: edgeIndex, gap: gapIndex)] = addRun(
                            gap: gapIndex, lo: min(from, to), hi: max(from, to),
                            entries: [from], exits: [to]
                        )
                    }
                } else if let centre = ordering.centreOf[child] {
                    span.append(centre)
                }
            }

            // Neighbouring partners with no children say everything on the row itself.
            guard routedMarriage || !union.children.isEmpty else { continue }
            // Neighbouring partners feed the lane through one stem at the anchor; routed
            // ones drop in at each partner.
            let entries = routedMarriage || union.partners.count == 1 ? partnerPositions : [anchor]
            let exits = union.children.compactMap { child -> CGFloat? in
                if let index = ordering.longEdgeIndex(unionIndex: unionIndex, childId: child) {
                    return ordering.longEdges[index].dummyIndices.first.map { ordering.dummyCentre[$0] }
                }
                return ordering.centreOf[child]
            }
            unionRun[unionIndex] = addRun(
                gap: union.generation, lo: span.min()!, hi: span.max()!,
                entries: entries, exits: exits
            )
        }
    }

    /// Cross-axis positions a long edge passes through: each dummy, then the child.
    private func legWaypoints(edge: LayoutOrdering.LongEdge) -> [CGFloat] {
        var result = edge.dummyIndices.map { ordering.dummyCentre[$0] }
        result.append(ordering.centreOf[edge.childId] ?? result.last ?? 0)
        return result
    }

    private mutating func addRun(
        gap: Int, lo: CGFloat, hi: CGFloat, entries: [CGFloat], exits: [CGFloat]
    ) -> Int {
        runs.append(Run(gap: gap, lo: lo, hi: hi, entries: entries, exits: exits))
        return runs.count - 1
    }

    /// Greedy interval colouring. Two runs share a lane only when a clear gap separates
    /// them, so that a lane never reads as one continuous line joining two families.
    ///
    /// Lane order is what keeps a crowded band readable, and no single ordering rule wins:
    /// a run's *entries* come down from the row and want it shallow, its *exits* carry on
    /// to the next row and want it deep, and which pull dominates differs per family.
    /// Narrowest-first, widest-first and type-split orderings each fixed one example tree
    /// while making another worse.
    ///
    /// So seed greedily by width and then improve against the real objective: move one run
    /// at a time to the lane that leaves the fewest crossings, until nothing improves.
    /// Passes are bounded and every accepted move strictly lowers the count, so it settles.
    private mutating func allocateLanes() {
        var byGap: [Int: [Int]] = [:]
        for (index, run) in runs.enumerated() { byGap[run.gap, default: []].append(index) }

        for (_, indices) in byGap {
            let sorted = indices.sorted { lhs, rhs in
                let wl = runs[lhs].hi - runs[lhs].lo, wr = runs[rhs].hi - runs[rhs].lo
                if wl != wr { return wl < wr }
                if runs[lhs].lo != runs[rhs].lo { return runs[lhs].lo < runs[rhs].lo }
                return lhs < rhs
            }
            var lanes: [[(lo: CGFloat, hi: CGFloat)]] = []
            for index in sorted {
                let run = runs[index]
                var lane = 0
                while lane < lanes.count,
                      lanes[lane].contains(where: { $0.hi > run.lo && run.hi > $0.lo }) {
                    lane += 1
                }
                if lane == lanes.count { lanes.append([]) }
                lanes[lane].append((run.lo, run.hi))
                runs[index].lane = lane
            }
            refineLanes(sorted)
            repackLanes(sorted)
        }
    }

    /// Re-pack a gap so the clearance rule holds by construction.
    ///
    /// The greedy pass and the hill-climb both consult the rule, but they hand lanes out
    /// against a moving target and can still leave two runs meeting end to end. Repacking
    /// in the order they settled on keeps their intent and makes the guarantee absolute:
    /// each run takes the lowest lane that nothing on it is too close to.
    private mutating func repackLanes(_ indices: [Int]) {
        // A chain's shared marriage line sits above every descent that hangs off it, so it
        // is packed first and the buses fall in below.
        let chains = Set(chainRun.values)
        let order = indices.sorted { lhs, rhs in
            let cl = chains.contains(lhs), cr = chains.contains(rhs)
            if cl != cr { return cl }
            if runs[lhs].lane != runs[rhs].lane { return runs[lhs].lane < runs[rhs].lane }
            if runs[lhs].lo != runs[rhs].lo { return runs[lhs].lo < runs[rhs].lo }
            return lhs < rhs
        }
        var lanes: [[(lo: CGFloat, hi: CGFloat)]] = []
        for index in order {
            let run = runs[index]
            // Keep looking past the end of the band: a fresh lane still has to clear the
            // one above it, so the search cannot stop merely because the lane is new.
            var lane = 0
            while conflicts(lane: lane, with: run, in: lanes) { lane += 1 }
            while lanes.count <= lane { lanes.append([]) }
            lanes[lane].append((run.lo, run.hi))
            runs[index].lane = lane
        }
    }

    /// A lane is unusable when something on it is too close, and also when the lane just
    /// above ends near where this run would turn. Two runs of unrelated families whose
    /// corners land within a few points of each other read as one elbow joining the two —
    /// keeping them off neighbouring lanes puts visible air between the turns.
    private func conflicts(
        lane: Int,
        with run: Run,
        in lanes: [[(lo: CGFloat, hi: CGFloat)]]
    ) -> Bool {
        if lane < lanes.count, lanes[lane].contains(where: { overlaps($0, run) }) { return true }
        guard lane > 0, lane - 1 < lanes.count else { return false }
        return lanes[lane - 1].contains { neighbour in
            [neighbour.lo, neighbour.hi].contains { corner in
                abs(corner - run.lo) < metrics.laneClearance || abs(corner - run.hi) < metrics.laneClearance
            }
        }
    }

    /// Hill-climb the lane assignment of one gap against `crossings(in:)`.
    private mutating func refineLanes(_ indices: [Int]) {
        guard indices.count > 1 else { return }
        var best = crossings(in: indices)
        guard best > 0 else { return }

        for _ in 0 ..< 8 {
            var improved = false
            for index in indices {
                // Try every lane, then commit the best one — never leave the run parked on
                // a lane that was only being trialled. Restoring to a remembered "original"
                // instead would put it back on a lane a previous move may have taken,
                // which is how two families' buses ended up sharing one line.
                let start = runs[index].lane
                var bestLane = start
                let ceiling = indices.map { runs[$0].lane }.max()! + 1
                for candidate in 0 ... ceiling where candidate != start {
                    // A lane is only usable if nothing already on it is too close.
                    let clash = indices.contains { other in
                        other != index && runs[other].lane == candidate
                            && overlaps((runs[other].lo, runs[other].hi), runs[index])
                    }
                    guard !clash else { continue }
                    runs[index].lane = candidate
                    let score = crossings(in: indices)
                    if score < best {
                        best = score
                        bestLane = candidate
                    }
                }
                runs[index].lane = bestLane
                if bestLane != start { improved = true }
            }
            if !improved { break }
        }
        compactLanes(indices)
    }

    /// A vertical crosses another run's horizontal when it passes its lane and that lane's
    /// run spans the vertical's position. Entries travel up from the lane to the row above,
    /// exits travel down from it to the row below.
    private func crossings(in indices: [Int]) -> Int {
        var total = 0
        for index in indices {
            let run = runs[index]
            for other in indices where other != index {
                let bar = runs[other]
                let above = bar.lane < run.lane
                let spans = { (x: CGFloat) in bar.lo < x && x < bar.hi }
                if above {
                    total += run.entries.filter(spans).count
                } else if bar.lane > run.lane {
                    total += run.exits.filter(spans).count
                }
            }
        }
        return total
    }

    /// Hill-climbing can leave a lane empty; close the gaps so the band stays as thin as
    /// the assignment allows.
    private mutating func compactLanes(_ indices: [Int]) {
        let used = Set(indices.map { runs[$0].lane }).sorted()
        let rank = Dictionary(uniqueKeysWithValues: used.enumerated().map { ($0.element, $0.offset) })
        for index in indices { runs[index].lane = rank[runs[index].lane]! }
    }

    /// Two spans conflict when they overlap or sit closer than the lane clearance.
    private func overlaps(_ span: (lo: CGFloat, hi: CGFloat), _ run: Run) -> Bool {
        span.hi + metrics.laneClearance > run.lo && run.hi + metrics.laneClearance > span.lo
    }

    private mutating func computeGenerationOffsets() {
        var laneCount = Array(repeating: 0, count: max(graph.maxGeneration + 1, 1))
        for run in runs where run.gap < laneCount.count {
            laneCount[run.gap] = max(laneCount[run.gap], run.lane + 1)
        }

        generationOffset = [metrics.pad]
        for generation in 0 ..< max(graph.maxGeneration, 0) {
            let lanes = laneCount[generation]
            let needed = metrics.laneInset
                + CGFloat(max(lanes - 1, 0)) * metrics.laneSpacing
                + metrics.laneTail
            generationOffset.append(generationOffset[generation] + metrics.rowExtent + max(metrics.minimumGap, needed))
        }
        totalExtent = (generationOffset.last ?? metrics.pad) + metrics.rowExtent
    }

    private func rowTop(_ generation: Int) -> CGFloat {
        generationOffset[min(max(generation, 0), generationOffset.count - 1)]
    }

    private func rowBottom(_ generation: Int) -> CGFloat {
        rowTop(generation) + metrics.rowExtent
    }

    private func rowCentre(_ generation: Int) -> CGFloat {
        rowTop(generation) + metrics.rowExtent / 2
    }

    private func laneY(_ runIndex: Int) -> CGFloat {
        let run = runs[runIndex]
        return rowBottom(run.gap) + metrics.laneInset + CGFloat(run.lane) * metrics.laneSpacing
    }

    // MARK: - Connectors

    private mutating func emitConnectors() {
        // Each spouse chain's shared marriage line, plus one drop per person onto it.
        for chain in ordering.spouseChains {
            guard let runIndex = chainRun[chain.members] else { continue }
            let y = laneY(runIndex)
            let run = runs[runIndex]
            var segments = [LinkSegment(
                from: CGPoint(x: run.lo, y: y),
                to: CGPoint(x: run.hi, y: y)
            )]
            for member in chain.members {
                guard let centre = ordering.centreOf[member] else { continue }
                segments.append(LinkSegment(
                    from: CGPoint(x: centre, y: rowBottom(chain.generation)),
                    to: CGPoint(x: centre, y: y)
                ))
            }
            links.append(TreeLink(id: "chain-\(chain.members[0])", segments: segments))
        }

        for (unionIndex, union) in graph.unions.enumerated() {
            guard let anchor = ordering.unionAnchor(unionIndex) else { continue }
            let positions = union.partners.compactMap { ordering.centreOf[$0] }
            // A marriage inside a spouse chain rides that chain's shared line; otherwise it
            // is drawn on the row when the partners are neighbours, and routed if not.
            let chainLane = ordering.spouseChain(ofUnion: unionIndex).flatMap { chainRun[$0] }
            let adjacent = chainLane == nil
                && union.partners.count == 2
                && positions.count == 2
                && ordering.partnersAreAdjacent(unionIndex)
            let marriageLane = chainLane ?? unionRun[unionIndex]

            // Where this union's connectors meet: on the row between neighbouring
            // partners, otherwise on the lane that carries the marriage.
            let source = if adjacent {
                CGPoint(x: anchor, y: rowCentre(union.generation))
            } else {
                CGPoint(x: anchor, y: marriageLane.map { laneY($0) } ?? rowBottom(union.generation))
            }

            // How a reader's eye gets from *each* partner's card to the point this union's
            // connectors leave from. Kept per partner, not pooled: a path that reaches a
            // child through the mother should light her leg of the couple and not the
            // father's. Every route starting at that point carries the leg it came in on,
            // or the highlight begins in mid air.
            var approach: [UUID: [LinkSegment]] = [:]

            if adjacent {
                let y = rowCentre(union.generation)
                let left = min(positions[0], positions[1]) + metrics.crossExtent / 2
                let right = max(positions[0], positions[1]) - metrics.crossExtent / 2
                append(
                    id: "marriage-\(union.id)",
                    segments: [LinkSegment(from: CGPoint(x: left, y: y), to: CGPoint(x: right, y: y))],
                    connections: [FamilyConnection(union.partners[0], union.partners[1])]
                )
                for (partner, centre) in zip(union.partners, positions) {
                    let edge = centre < anchor ? left : right
                    approach[partner] = [LinkSegment(from: CGPoint(x: edge, y: y), to: source)]
                }
            } else if let marriageLane {
                let y = laneY(marriageLane)
                var drops: [LinkSegment] = []
                for (partner, centre) in zip(union.partners, positions) {
                    let generation = graph.generationOf[partner] ?? union.generation
                    let edge = generation <= union.generation ? rowBottom(generation) : rowTop(generation)
                    drops.append(LinkSegment(from: CGPoint(x: centre, y: edge), to: CGPoint(x: centre, y: y)))
                }
                // A chain's drops are drawn once for the whole chain, below; a routed pair
                // draws its own. Either way the highlight carries the complete path,
                // including the stretch of lane between the partners — without it a
                // selected couple lights up as two disconnected stubs.
                if chainLane == nil { links.append(contentsOf: drops.map {
                    TreeLink(id: "marriage-\(union.id)", segments: [$0])
                }) }
                if union.partners.count == 2, positions.count == 2 {
                    highlightRoutes.append(TreeHighlightRoute(
                        id: "marriage-\(union.id)",
                        segments: drops + [LinkSegment(
                            from: CGPoint(x: positions.min()!, y: y),
                            to: CGPoint(x: positions.max()!, y: y)
                        )],
                        connections: [FamilyConnection(union.partners[0], union.partners[1])]
                    ))
                } else if chainLane == nil {
                    links.append(TreeLink(id: "parent-\(union.id)", segments: drops))
                }
                for (index, partner) in union.partners.enumerated() where index < drops.count {
                    approach[partner] = [
                        drops[index],
                        LinkSegment(
                            from: CGPoint(x: positions[index], y: y),
                            to: CGPoint(x: source.x, y: y)
                        ),
                    ]
                }
            }

            // The lane's own horizontal. Drawn for every union that claimed a lane, not
            // only those with children: a childless routed marriage is nothing but two
            // partner drops, and without this the pair dead-ends in mid-air.
            if let runIndex = unionRun[unionIndex] {
                let busY = laneY(runIndex)
                let run = runs[runIndex]
                var trunk: [LinkSegment] = []
                if source.y != busY {
                    trunk.append(LinkSegment(from: source, to: CGPoint(x: source.x, y: busY)))
                }
                if run.hi - run.lo > 0.5 {
                    trunk.append(LinkSegment(
                        from: CGPoint(x: run.lo, y: busY),
                        to: CGPoint(x: run.hi, y: busY)
                    ))
                }
                if !trunk.isEmpty {
                    links.append(TreeLink(id: "children-\(union.id)-trunk", segments: trunk))
                }
            }

            unionAnchors.append(TreeLayout.UnionAnchor(id: union.id, point: source))
            emitChildren(unionIndex: unionIndex, union: union, source: source, approach: approach)
        }
    }

    private mutating func emitChildren(
        unionIndex: Int,
        union: LayoutGraph.UnionNode,
        source: CGPoint,
        approach: [UUID: [LinkSegment]]
    ) {
        guard !union.children.isEmpty, let runIndex = unionRun[unionIndex] else { return }
        let busY = laneY(runIndex)

        for child in union.children {
            let waypoints = childWaypoints(unionIndex: unionIndex, union: union, child: child)
            guard !waypoints.isEmpty else { continue }
            // Along, then down, for each waypoint. The first along-leg runs inside the
            // trunk that was just drawn, so the neutral rendering skips it rather than
            // stroking the same pixels twice; the highlight overlay keeps it, because a
            // single branch has to read as one continuous route on its own.
            var segments: [LinkSegment] = []
            var routeSegments = [LinkSegment(from: source, to: CGPoint(x: source.x, y: busY))]
            var cursor = CGPoint(x: source.x, y: busY)
            for (step, point) in waypoints.enumerated() {
                let corner = CGPoint(x: point.x, y: cursor.y)
                routeSegments.append(LinkSegment(from: cursor, to: corner))
                routeSegments.append(LinkSegment(from: corner, to: point))
                if step > 0 { segments.append(LinkSegment(from: cursor, to: corner)) }
                segments.append(LinkSegment(from: corner, to: point))
                cursor = point
            }

            links.append(TreeLink(id: "children-\(union.id)-child-\(child)", segments: segments))
            // One route per parent. Sharing a single route between both would light the
            // whole couple whenever either of them is on the path.
            for partner in union.partners {
                highlightRoutes.append(TreeHighlightRoute(
                    id: "children-\(union.id)-route-\(child.uuidString)-\(partner.uuidString)",
                    segments: (approach[partner] ?? []) + routeSegments,
                    connections: [FamilyConnection(partner, child)]
                ))
            }
        }
    }

    /// The corner points a child's connector turns at, starting from the bus lane. A child
    /// on the next row is one drop; a child further down steps through the corridors its
    /// dummies reserved.
    private func childWaypoints(
        unionIndex: Int,
        union: LayoutGraph.UnionNode,
        child: UUID
    ) -> [CGPoint] {
        let childGeneration = graph.generationOf[child] ?? union.generation + 1
        guard let edgeIndex = ordering.longEdgeIndex(unionIndex: unionIndex, childId: child) else {
            guard let centre = ordering.centreOf[child] else { return [] }
            return [CGPoint(x: centre, y: rowTop(childGeneration))]
        }
        let edge = ordering.longEdges[edgeIndex]

        var result: [CGPoint] = []
        let waypoints = legWaypoints(edge: edge)
        for offset in edge.dummyIndices.indices {
            let gapIndex = union.generation + 1 + offset
            let x = waypoints[offset]
            // Down the reserved corridor, through the row, into the next band.
            result.append(CGPoint(x: x, y: rowTop(gapIndex)))
            if let legRun = edgeRun[EdgeLeg(edgeIndex: edgeIndex, gap: gapIndex)] {
                result.append(CGPoint(x: x, y: laneY(legRun)))
            } else {
                result.append(CGPoint(x: x, y: rowBottom(gapIndex)))
            }
        }
        if let centre = ordering.centreOf[child] {
            result.append(CGPoint(x: centre, y: rowTop(childGeneration)))
        }
        return result
    }

    private mutating func append(id: String, segments: [LinkSegment], connections: Set<FamilyConnection>) {
        links.append(TreeLink(id: id, segments: segments))
        highlightRoutes.append(TreeHighlightRoute(id: id, segments: segments, connections: connections))
    }
}
