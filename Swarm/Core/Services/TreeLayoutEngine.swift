import CoreGraphics
import Foundation

/// Orientation for a tidy tree drawing.
public enum LayoutDirection: Equatable {
    case topDown
    case leftRight
}

/// A laid-out person card position (top-left origin).
public struct TreeNode: Equatable {
    public let person: Person
    public let x: CGFloat
    public let y: CGFloat
    public init(person: Person, x: CGFloat, y: CGFloat) {
        self.person = person; self.x = x; self.y = y
    }

    public static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        lhs.person.id == rhs.person.id && lhs.x == rhs.x && lhs.y == rhs.y
    }
}

public struct LinkSegment: Equatable {
    public let from: CGPoint
    public let to: CGPoint
    public init(from: CGPoint, to: CGPoint) {
        self.from = from; self.to = to
    }
}

public struct TreeLink: Identifiable, Equatable {
    public let id: String
    public let segments: [LinkSegment]
    public init(id: String, segments: [LinkSegment]) {
        self.id = id; self.segments = segments
    }
}

/// Geometry used only for the accent overlay. Unlike the neutral sibling bus, each
/// route follows one logical relationship branch and can be activated independently.
public struct TreeHighlightRoute: Identifiable, Equatable {
    public let id: String
    public let segments: [LinkSegment]
    public let connections: Set<FamilyConnection>

    public init(
        id: String,
        segments: [LinkSegment],
        connections: Set<FamilyConnection>
    ) {
        self.id = id
        self.segments = segments
        self.connections = connections
    }
}

public struct TreeLayout: Equatable {
    public let nodes: [TreeNode]
    public let links: [TreeLink]
    public let highlightRoutes: [TreeHighlightRoute]
    public let totalWidth: CGFloat
    public let totalHeight: CGFloat
    public init(
        nodes: [TreeNode],
        links: [TreeLink],
        highlightRoutes: [TreeHighlightRoute],
        totalWidth: CGFloat,
        totalHeight: CGFloat
    ) {
        self.nodes = nodes; self.links = links
        self.highlightRoutes = highlightRoutes
        self.totalWidth = totalWidth; self.totalHeight = totalHeight
    }
}

/// Card sizes and gaps the layout is built from. Defaults match the on-screen card
/// (210×90) so the engine and the view agree.
public struct LayoutConfig {
    public var cardW: CGFloat = 210
    public var cardH: CGFloat = 90
    public var spouseGap: CGFloat = 30 // gap between partners within a couple
    public var siblingGap: CGFloat = 110 // gap between separate couples / branches
    public var familyGap: CGFloat = 140 // gap between unrelated families / roots
    public var vGapTB: CGFloat = 110
    public var vGapLR: CGFloat = 150
    public var pad: CGFloat = 60
    public var busFraction: CGFloat = 0.5 // where each parent→children trunk sits in the gap
    public init() {}
}

/// Tidy family-tree layout using the O(n) Buchheim–Jünger–Leipert algorithm:
///   - parents are centered over their children
///   - subtrees don't overlap (contour checks via "threads")
///   - "mod" accumulators avoid O(n²) subtree shifts
///
/// Pure and side-effect-free: same tree + direction always yields the same layout,
/// which is what makes it unit-testable independently of SwiftUI.
public struct TreeLayoutEngine {
    private let config: LayoutConfig

    public init(config: LayoutConfig = LayoutConfig()) {
        self.config = config
    }

    public func layout(tree: FamilyTree, direction: LayoutDirection) -> TreeLayout {
        // Bind config to locals so the algorithm body reads as a self-contained unit.
        let cardW = config.cardW
        let cardH = config.cardH
        let spouseGap = config.spouseGap
        let siblingGap = config.siblingGap
        let familyGap = config.familyGap
        let vGapTB = config.vGapTB
        let vGapLR = config.vGapLR
        let pad = config.pad
        let busFraction = config.busFraction

        let idx = FamilyIndex(tree: tree)
        let nodeWidth = direction == .leftRight ? cardH : cardW
        let genStep = direction == .leftRight ? (cardW + vGapLR) : (cardH + vGapTB)
        let minSep: CGFloat = siblingGap // minimum gap between sibling subtrees
        let familySep: CGFloat = familyGap // gap between unrelated families

        // ─── STEP 1: Assign generation depths via BFS ───
        var depths: [UUID: Int] = [:]

        func assignDepths(startingFrom startId: UUID, atDepth startDepth: Int) {
            var queue: [(UUID, Int)] = [(startId, startDepth)]
            depths[startId] = startDepth
            while !queue.isEmpty {
                let (personId, depth) = queue.removeFirst()
                for union in idx.unionsOf[personId] ?? [] {
                    for pid in union.partnerIds where pid != personId {
                        if depths[pid] == nil {
                            depths[pid] = depth
                            queue.append((pid, depth))
                        }
                    }
                    for cid in union.childrenIds {
                        if depths[cid] == nil {
                            depths[cid] = depth + 1
                            queue.append((cid, depth + 1))
                        }
                    }
                }
                if let parentUnion = idx.childOf[personId] {
                    for pid in parentUnion.partnerIds {
                        if depths[pid] == nil {
                            depths[pid] = depth - 1
                            queue.append((pid, depth - 1))
                        }
                    }
                    for sibId in parentUnion.childrenIds where sibId != personId {
                        if depths[sibId] == nil {
                            depths[sibId] = depth
                            queue.append((sibId, depth))
                        }
                    }
                }
            }
        }

        if let rootUnion = tree.rootUnion {
            if let p1id = rootUnion.partner1Id { assignDepths(startingFrom: p1id, atDepth: 0) }
            if let p2id = rootUnion.partner2Id, depths[p2id] == nil { assignDepths(startingFrom: p2id, atDepth: 0) }
        } else if let homeId = tree.homePersonId {
            assignDepths(startingFrom: homeId, atDepth: 0)
        } else if let first = tree.people.first {
            assignDepths(startingFrom: first.id, atDepth: 0)
        }
        for person in tree.people where depths[person.id] == nil {
            assignDepths(startingFrom: person.id, atDepth: 0)
        }
        let minDepthVal = depths.values.min() ?? 0
        if minDepthVal < 0 {
            for (key, val) in depths {
                depths[key] = val - minDepthVal
            }
        }

        // ─── STEP 2: Build a couple-anchored ancestor tree (LayoutNode) ───
        // Each LayoutNode is a "couple unit": the two partners drawn adjacently,
        // plus each partner's siblings on their outer side. The unit's tidy-tree
        // children are the ancestor units of each partner (drawn in the band above,
        // their generation given by the depths map). Because married partners are
        // always adjacent and subtrees never interleave, marriage lines stay short
        // and connectors don't cross between branches.

        class LayoutNode {
            var memberIds: [UUID] = [] // people on this row, left → right
            var children: [LayoutNode] = []
            var parent: LayoutNode?

            // Buchheim state
            var x: CGFloat = 0
            var mod: CGFloat = 0
            var shift: CGFloat = 0
            var change: CGFloat = 0
            var thread: LayoutNode?
            var ancestor: LayoutNode?
            var number: Int = 1 // 1-based index among siblings

            var width: CGFloat = 0

            init() {
                self.ancestor = nil
            }

            var leftSibling: LayoutNode? {
                guard let p = parent else { return nil }
                let i = number - 1 // 0-based
                return i > 0 ? p.children[i - 1] : nil
            }

            var leftmostSibling: LayoutNode? {
                guard let p = parent else { return nil }
                let first = p.children[0]
                return first === self ? nil : first
            }
        }

        let memberGap = spouseGap // gap between adjacent cards within a unit

        /// Parent/sibling lookups merge across split GEDCOM families (a person's
        /// father and mother can be in separate FAM records). Backed by the
        /// precomputed FamilyIndex maps — O(1) per call instead of scanning unions.
        func mergedParents(_ pid: UUID) -> (father: UUID?, mother: UUID?) {
            idx.mergedParentIds(pid)
        }
        func mergedSiblings(_ pid: UUID) -> [UUID] {
            idx.mergedSiblingIds(pid)
        }

        var placedPersons = Set<UUID>()
        var rootNodes: [LayoutNode] = []

        /// Build a unit anchored on `leftId` (and optional `rightId` partner).
        /// Recurses upward into each anchor's ancestry.
        func buildUnit(_ leftId: UUID, _ rightId: UUID?) -> LayoutNode {
            let node = LayoutNode()
            node.ancestor = node

            // Members: [left's siblings][left][right][right's siblings]
            var members: [UUID] = []
            let leftSibs = mergedSiblings(leftId).filter { $0 != rightId && !placedPersons.contains($0) }
            members.append(contentsOf: leftSibs)
            members.append(leftId)
            if let rightId { members.append(rightId) }
            if let rightId {
                let rightSibs = mergedSiblings(rightId).filter { $0 != leftId && !placedPersons.contains($0) }
                members.append(contentsOf: rightSibs)
            }
            // Deduplicate, mark placed
            var seen = Set<UUID>()
            members = members.filter { seen.insert($0).inserted && idx.byId[$0] != nil }
            for m in members {
                placedPersons.insert(m)
            }
            node.memberIds = members
            let n = max(members.count, 1)
            node.width = CGFloat(n) * nodeWidth + CGFloat(n - 1) * memberGap

            /// Ancestor fans (tidy-tree children), one per anchor partner.
            func ancestorUnit(of pid: UUID) -> LayoutNode? {
                let (f, m) = mergedParents(pid)
                let fOpen = (f != nil && !placedPersons.contains(f!)) ? f : nil
                let mOpen = (m != nil && !placedPersons.contains(m!)) ? m : nil
                if fOpen == nil && mOpen == nil { return nil }
                // Father on the left, mother on the right
                if let fOpen { return buildUnit(fOpen, mOpen) }
                return buildUnit(mOpen!, nil)
            }

            var kids: [LayoutNode] = []
            if let fan = ancestorUnit(of: leftId) { kids.append(fan) }
            if let rightId, let fan = ancestorUnit(of: rightId) { kids.append(fan) }
            for (i, k) in kids.enumerated() {
                k.parent = node; k.number = i + 1
            }
            node.children = kids
            return node
        }

        // Anchor: the home person's marriage (else the root union, else first person).
        func anchorCouple() -> (UUID, UUID?)? {
            func unionPartner(_ pid: UUID) -> UUID? {
                for u in idx.unionsOf[pid] ?? [] {
                    if let other = u.partnerIds.first(where: { $0 != pid }) { return other }
                }
                return nil
            }
            if let homeId = tree.homePersonId, idx.byId[homeId] != nil {
                let partner = unionPartner(homeId)
                // Order male-left / female-right for stable orientation
                if let partner, idx.byId[homeId]?.sex == .female, idx.byId[partner]?.sex == .male {
                    return (partner, homeId)
                }
                return (homeId, partner)
            }
            if let ru = tree.rootUnion, let p1 = ru.partner1Id { return (p1, ru.partner2Id) }
            if let first = tree.people.first { return (first.id, nil) }
            return nil
        }

        if let (l, r) = anchorCouple() {
            rootNodes.append(buildUnit(l, r))
        }

        // Any remaining people (disconnected components / descendants not on the
        // ancestor closure) become their own root units, placed beside the main tree.
        for person in tree.people where !placedPersons.contains(person.id) {
            let partner = (idx.unionsOf[person.id] ?? []).compactMap { u in
                u.partnerIds.first(where: { $0 != person.id && !placedPersons.contains($0) })
            }.first
            rootNodes.append(buildUnit(person.id, partner))
        }

        let maxDepthVal = depths.values.max() ?? 0
        _ = maxDepthVal

        // ─── STEP 3: Buchheim first walk (post-order) ───
        // Assigns preliminary x and mod values

        func firstWalk(_ v: LayoutNode) {
            if v.children.isEmpty {
                // Leaf: place next to left sibling
                if let ls = v.leftSibling {
                    let sep = (ls.width + v.width) / 2 + minSep
                    v.x = ls.x + sep
                } else {
                    v.x = 0
                }
            } else {
                var defaultAncestor = v.children[0]
                for w in v.children {
                    firstWalk(w)
                    defaultAncestor = apportion(w, defaultAncestor: defaultAncestor)
                }
                executeShifts(v)

                let midpoint = (v.children[0].x + v.children[v.children.count - 1].x) / 2

                if let ls = v.leftSibling {
                    let sep = (ls.width + v.width) / 2 + minSep
                    v.x = ls.x + sep
                    v.mod = v.x - midpoint
                } else {
                    v.x = midpoint
                }
            }
        }

        // Apportion: the core of Buchheim — check contours and shift subtrees
        func apportion(_ v: LayoutNode, defaultAncestor: LayoutNode) -> LayoutNode {
            guard let w = v.leftSibling else { return defaultAncestor }

            var vInnerRight = v
            var vOuterRight = v
            var vInnerLeft = w
            var vOuterLeft = v.leftmostSibling ?? v

            var sInnerRight = v.mod
            var sOuterRight = v.mod
            var sInnerLeft = vInnerLeft.mod
            var sOuterLeft = vOuterLeft.mod

            while let nilr = nextRight(vInnerLeft), let nirl = nextLeft(vInnerRight) {
                vInnerLeft = nilr
                vInnerRight = nirl
                vOuterLeft = nextLeft(vOuterLeft) ?? vOuterLeft
                vOuterRight = nextRight(vOuterRight) ?? vOuterRight
                vOuterRight.ancestor = v

                let sep = (vInnerLeft.width + vInnerRight.width) / 2 + minSep
                let shift = (vInnerLeft.x + sInnerLeft) - (vInnerRight.x + sInnerRight) + sep
                if shift > 0 {
                    let a = ancestorOf(vInnerLeft, v: v, defaultAncestor: defaultAncestor)
                    moveSubtree(a, wr: v, shift: shift)
                    sInnerRight += shift
                    sOuterRight += shift
                }

                sInnerLeft += vInnerLeft.mod
                sInnerRight += vInnerRight.mod
                sOuterLeft += vOuterLeft.mod
                sOuterRight += vOuterRight.mod
            }

            // Set threads
            if let nr = nextRight(vInnerLeft), nextRight(vOuterRight) == nil {
                vOuterRight.thread = nr
                vOuterRight.mod += sInnerLeft - sOuterRight
            }
            if let nl = nextLeft(vInnerRight), nextLeft(vOuterLeft) == nil {
                vOuterLeft.thread = nl
                vOuterLeft.mod += sInnerRight - sOuterLeft
                return v
            }
            return defaultAncestor
        }

        func nextLeft(_ v: LayoutNode) -> LayoutNode? {
            v.children.first ?? v.thread
        }

        func nextRight(_ v: LayoutNode) -> LayoutNode? {
            v.children.last ?? v.thread
        }

        func moveSubtree(_ wl: LayoutNode, wr: LayoutNode, shift: CGFloat) {
            let subtrees = CGFloat(wr.number - wl.number)
            guard subtrees > 0 else { return }
            wr.change -= shift / subtrees
            wr.shift += shift
            wl.change += shift / subtrees
            wr.x += shift
            wr.mod += shift
        }

        func executeShifts(_ v: LayoutNode) {
            var shift: CGFloat = 0
            var change: CGFloat = 0
            for w in v.children.reversed() {
                w.x += shift
                w.mod += shift
                change += w.change
                shift += w.shift + change
            }
        }

        func ancestorOf(_ vil: LayoutNode, v: LayoutNode, defaultAncestor: LayoutNode) -> LayoutNode {
            guard let vilAnc = vil.ancestor, let vParent = v.parent else { return defaultAncestor }
            if vParent.children.contains(where: { $0 === vilAnc }) {
                return vilAnc
            }
            return defaultAncestor
        }

        // ─── STEP 4: Second walk (pre-order) — apply mod accumulator ───

        func secondWalk(_ v: LayoutNode, modSum: CGFloat, depth: Int, positions: inout [UUID: (bc: CGFloat, depth: Int)]) {
            let centerX = v.x + modSum
            // Lay out this unit's members left → right, centered on centerX.
            var cursor = centerX - v.width / 2 + nodeWidth / 2
            for m in v.memberIds {
                let d = depths[m] ?? depth
                positions[m] = (cursor, d)
                cursor += nodeWidth + memberGap
            }
            for child in v.children {
                secondWalk(child, modSum: modSum + v.mod, depth: depth + 1, positions: &positions)
            }
        }

        // ─── Execute Buchheim on each root ───

        var placements: [UUID: (bc: CGFloat, depth: Int)] = [:]
        var globalOffset: CGFloat = 0

        for (i, root) in rootNodes.enumerated() {
            // First walk
            firstWalk(root)

            // Find leftmost position in this tree
            var minX: CGFloat = .infinity
            func findMin(_ n: LayoutNode, modSum: CGFloat) {
                let fx = n.x + modSum
                let half = n.width / 2
                minX = min(minX, fx - half)
                for c in n.children {
                    findMin(c, modSum: modSum + n.mod)
                }
            }
            findMin(root, modSum: 0)

            // Shift so this tree starts after previous trees
            let treeShift = globalOffset - minX + (i > 0 ? familySep : 0)

            // Second walk with offset
            secondWalk(root, modSum: treeShift, depth: 0, positions: &placements)

            // Find rightmost position to update globalOffset
            var maxX: CGFloat = -.infinity
            func findMax(_ n: LayoutNode, modSum: CGFloat) {
                let fx = n.x + modSum
                let half = n.width / 2
                maxX = max(maxX, fx + half)
                for c in n.children {
                    findMax(c, modSum: modSum + n.mod)
                }
            }
            findMax(root, modSum: treeShift)
            globalOffset = maxX
        }

        // ─── STEP 5: Convert to screen coordinates ───

        var nodes: [TreeNode] = []
        var minB: CGFloat = .infinity
        var maxB: CGFloat = -.infinity
        var maxDepth = 0

        for (_, pl) in placements {
            minB = min(minB, pl.bc - nodeWidth / 2)
            maxB = max(maxB, pl.bc + nodeWidth / 2)
            maxDepth = max(maxDepth, pl.depth)
        }
        if minB == .infinity { minB = 0; maxB = 200 }

        let bShift = pad - minB

        for person in tree.people {
            guard let pl = placements[person.id] else { continue }
            let depthPos = CGFloat(pl.depth) * genStep + pad
            let x: CGFloat, y: CGFloat
            if direction == .topDown {
                x = pl.bc + bShift - cardW / 2
                y = depthPos
            } else {
                x = depthPos
                y = pl.bc + bShift - cardH / 2
            }
            nodes.append(TreeNode(person: person, x: x, y: y))
        }

        // ─── STEP 6: Build connector lines ───

        var links: [TreeLink] = []
        var highlightRoutes: [TreeHighlightRoute] = []

        // ── Marriage lines ──
        for union in tree.unions {
            let validPartners = union.partnerIds.filter { placements[$0] != nil }
            guard validPartners.count == 2 else { continue }
            guard let pl1 = placements[validPartners[0]], let pl2 = placements[validPartners[1]] else { continue }
            var segments: [LinkSegment] = []
            if direction == .topDown {
                let y = CGFloat(pl1.depth) * genStep + pad + cardH / 2
                let x1 = min(pl1.bc, pl2.bc) + bShift + cardW / 2
                let x2 = max(pl1.bc, pl2.bc) + bShift - cardW / 2
                segments.append(LinkSegment(from: CGPoint(x: x1, y: y), to: CGPoint(x: x2, y: y)))
            } else {
                let x = CGFloat(pl1.depth) * genStep + pad + cardW / 2
                let y1 = min(pl1.bc, pl2.bc) + bShift + cardH / 2
                let y2 = max(pl1.bc, pl2.bc) + bShift - cardH / 2
                segments.append(LinkSegment(from: CGPoint(x: x, y: y1), to: CGPoint(x: x, y: y2)))
            }
            links.append(TreeLink(id: "marriage-\(union.id)", segments: segments))
            highlightRoutes.append(TreeHighlightRoute(
                id: "marriage-\(union.id)",
                segments: segments,
                connections: [FamilyConnection(validPartners[0], validPartners[1])]
            ))
        }

        // ── Child connectors (uniform routing) ──
        //
        // The trunk ("bus") that links a couple to their children runs across the
        // gap between two generations. Every trunk sits at the same fraction
        // (busFraction) of its gap, giving all connectors one consistent shape.
        struct ChildBus {
            let id: String
            let depth: Int // parent generation index
            let ax: CGFloat // parent-side stem position (cross-axis)
            let children: [(id: UUID, coord: CGFloat)] // child stem positions (cross-axis)
            let lo: CGFloat // trunk span min (cross-axis)
            let hi: CGFloat // trunk span max (cross-axis)
            let parentEdge: CGFloat // main-axis: bottom/right edge of parents
            let childEdge: CGFloat // main-axis: top/left edge of children
            let partnerIds: Set<UUID>
        }

        var buses: [ChildBus] = []
        for union in tree.unions {
            let validPartners = union.partnerIds.filter { placements[$0] != nil }
            let kids = union.childrenIds.filter { placements[$0] != nil }
            guard !kids.isEmpty, !validPartners.isEmpty else { continue }

            let parentBcs = validPartners.compactMap { placements[$0]?.bc }
            let ax = parentBcs.reduce(0, +) / CGFloat(parentBcs.count) + bShift
            let depth = placements[validPartners[0]]!.depth
            let children = kids.compactMap { childID -> (id: UUID, coord: CGFloat)? in
                guard let coordinate = placements[childID]?.bc else { return nil }
                return (childID, coordinate + bShift)
            }
            let span = children.map(\.coord) + [ax]

            let parentEdge: CGFloat
            let childEdge: CGFloat
            if direction == .topDown {
                parentEdge = CGFloat(depth) * genStep + pad + cardH
                childEdge = kids.compactMap { placements[$0]?.depth }.map { CGFloat($0) * genStep + pad }.min()!
            } else {
                parentEdge = CGFloat(depth) * genStep + pad + cardW
                childEdge = kids.compactMap { placements[$0]?.depth }.map { CGFloat($0) * genStep + pad }.min()!
            }

            buses.append(ChildBus(
                id: "children-\(union.id)", depth: depth, ax: ax, children: children,
                lo: span.min()!, hi: span.max()!, parentEdge: parentEdge, childEdge: childEdge,
                partnerIds: Set(validPartners)
            ))
        }

        for bus in buses {
            // Uniform routing: every trunk sits at the same fraction of its
            // inter-generation gap. Because partners are adjacent and Buchheim
            // keeps subtrees from interleaving, trunks at the same height never
            // overlap — so all connectors share one consistent shape.
            let busPos = bus.parentEdge + (bus.childEdge - bus.parentEdge) * busFraction

            var trunkSegments: [LinkSegment] = []
            if direction == .topDown {
                // Stem from couple centre down to the trunk.
                trunkSegments.append(LinkSegment(from: CGPoint(x: bus.ax, y: bus.parentEdge), to: CGPoint(x: bus.ax, y: busPos)))
                // Horizontal trunk.
                trunkSegments.append(LinkSegment(from: CGPoint(x: bus.lo, y: busPos), to: CGPoint(x: bus.hi, y: busPos)))
                links.append(TreeLink(
                    id: "\(bus.id)-trunk",
                    segments: trunkSegments
                ))
                // Each child drop carries only that child's identity. A sibling outside
                // the selected lineage can no longer suppress the chosen child's branch.
                for child in bus.children {
                    let segment = LinkSegment(
                        from: CGPoint(x: child.coord, y: busPos),
                        to: CGPoint(x: child.coord, y: bus.childEdge)
                    )
                    links.append(TreeLink(
                        id: "\(bus.id)-child-\(child.id)",
                        segments: [segment]
                    ))

                    let routeSegments = [
                        LinkSegment(
                            from: CGPoint(x: bus.ax, y: bus.parentEdge),
                            to: CGPoint(x: bus.ax, y: busPos)
                        ),
                        LinkSegment(
                            from: CGPoint(x: bus.ax, y: busPos),
                            to: CGPoint(x: child.coord, y: busPos)
                        ),
                        segment,
                    ]
                    highlightRoutes.append(TreeHighlightRoute(
                        id: "\(bus.id)-route-\(child.id)",
                        segments: routeSegments,
                        connections: Set(bus.partnerIds.map {
                            FamilyConnection($0, child.id)
                        })
                    ))
                }
            } else {
                trunkSegments.append(LinkSegment(from: CGPoint(x: bus.parentEdge, y: bus.ax), to: CGPoint(x: busPos, y: bus.ax)))
                trunkSegments.append(LinkSegment(from: CGPoint(x: busPos, y: bus.lo), to: CGPoint(x: busPos, y: bus.hi)))
                links.append(TreeLink(
                    id: "\(bus.id)-trunk",
                    segments: trunkSegments
                ))
                for child in bus.children {
                    let segment = LinkSegment(
                        from: CGPoint(x: busPos, y: child.coord),
                        to: CGPoint(x: bus.childEdge, y: child.coord)
                    )
                    links.append(TreeLink(
                        id: "\(bus.id)-child-\(child.id)",
                        segments: [segment]
                    ))

                    let routeSegments = [
                        LinkSegment(
                            from: CGPoint(x: bus.parentEdge, y: bus.ax),
                            to: CGPoint(x: busPos, y: bus.ax)
                        ),
                        LinkSegment(
                            from: CGPoint(x: busPos, y: bus.ax),
                            to: CGPoint(x: busPos, y: child.coord)
                        ),
                        segment,
                    ]
                    highlightRoutes.append(TreeHighlightRoute(
                        id: "\(bus.id)-route-\(child.id)",
                        segments: routeSegments,
                        connections: Set(bus.partnerIds.map {
                            FamilyConnection($0, child.id)
                        })
                    ))
                }
            }
        }

        let totalWidth = direction == .topDown ? (maxB - minB) + 2 * pad : CGFloat(maxDepth) * genStep + cardW + 2 * pad
        let totalHeight = direction == .topDown ? CGFloat(maxDepth) * genStep + cardH + 2 * pad : (maxB - minB) + 2 * pad

        return TreeLayout(
            nodes: nodes,
            links: links,
            highlightRoutes: highlightRoutes,
            totalWidth: max(totalWidth, 600),
            totalHeight: max(totalHeight, 400)
        )
    }
}
