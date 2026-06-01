import SwiftUI

struct TreeCanvasView: View {
    let tree: FamilyTree
    let direction: MainWorkspace.TreeDirection
    @Binding var zoom: CGFloat
    @Binding var selectedPerson: Person?
    @Binding var secondaryPerson: Person?
    var highlightedIds: Set<UUID> = []
    var lineageLabels: [UUID: String] = [:]
    @Binding var fitRequest: Int
    var showPhotos: Bool = false
    
    private let cardW: CGFloat = 210
    private let cardH: CGFloat = 90
    private let spouseGap: CGFloat = 30   // gap between partners within a couple (kept tight)
    private let siblingGap: CGFloat = 110  // gap between separate couples / branches (wide, for visual separation)
    private let familyGap: CGFloat = 140   // gap between unrelated families / disconnected roots
    private let vGapTB: CGFloat = 110
    private let vGapLR: CGFloat = 150
    private let pad: CGFloat = 60
    private let busFraction: CGFloat = 0.5 // where every parent→children trunk sits within the generation gap
    
    @State private var panOffset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var magnifyStart: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geo in
            let layout = computeLayout()
            
            ZStack(alignment: .topLeading) {
                // Connectors
                Canvas { ctx, size in
                    for link in layout.links {
                        var path = Path()
                        for seg in link.segments {
                            path.move(to: seg.from)
                            path.addLine(to: seg.to)
                        }
                        let isHighlighted = !highlightedIds.isEmpty && link.personIds.allSatisfy { highlightedIds.contains($0) }
                        let color = highlightedIds.isEmpty ? SepiaTheme.line : (isHighlighted ? SepiaTheme.accent : SepiaTheme.line.opacity(0.25))
                        ctx.stroke(path, with: .color(color), lineWidth: isHighlighted ? 2.5 : 1.2)
                    }
                }
                .frame(width: layout.totalWidth, height: layout.totalHeight)
                
                // Cards
                ForEach(layout.nodes, id: \.person.id) { node in
                    let dimmed = !highlightedIds.isEmpty && !highlightedIds.contains(node.person.id)
                    let isPrimary = selectedPerson?.id == node.person.id
                    let isSecondary = secondaryPerson?.id == node.person.id
                    let label = lineageLabels[node.person.id]
                    PersonCardView(
                        person: node.person,
                        isSelected: isPrimary,
                        isSecondarySelected: isSecondary,
                        isHome: tree.homePersonId == node.person.id,
                        isHighlighted: highlightedIds.contains(node.person.id),
                        lineageLabel: label,
                        showPhoto: showPhotos
                    )
                    .equatable()
                    .opacity(dimmed ? 0.3 : 1.0)
                    .position(x: node.x + cardW / 2, y: node.y + cardH / 2)
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            // CMD+click: set as secondary (max 2)
                            if selectedPerson == nil {
                                selectedPerson = node.person
                            } else if node.person.id == selectedPerson?.id {
                                // Clicking primary again with CMD — ignore
                            } else {
                                secondaryPerson = node.person
                            }
                        } else {
                            // Normal click: set as primary, clear secondary
                            secondaryPerson = nil
                            selectedPerson = node.person
                        }
                    }
                }
            }
            .frame(width: layout.totalWidth, height: layout.totalHeight)
            .scaleEffect(zoom, anchor: .topLeading)
            .offset(x: panOffset.width, y: panOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        panOffset = CGSize(
                            width: dragStart.width + value.translation.width,
                            height: dragStart.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        dragStart = panOffset
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let newZoom = magnifyStart * value.magnification
                        zoom = min(2.0, max(0.2, newZoom))
                    }
                    .onEnded { _ in
                        magnifyStart = zoom
                    }
            )
            .onAppear {
                magnifyStart = zoom
                fitToScreen(viewSize: geo.size, treeWidth: layout.totalWidth, treeHeight: layout.totalHeight)
            }
            .onChange(of: zoom) { _, newVal in magnifyStart = newVal }
            .onChange(of: tree.layoutVersion) { _, _ in
                fitToScreen(viewSize: geo.size, treeWidth: layout.totalWidth, treeHeight: layout.totalHeight)
            }
            .onChange(of: fitRequest) { _, _ in
                fitToScreen(viewSize: geo.size, treeWidth: layout.totalWidth, treeHeight: layout.totalHeight)
            }
            .clipped()
            .background {
                // Dot grid background (Miro-style)
                Canvas { ctx, size in
                    let spacing: CGFloat = 20 * zoom
                    let dotRadius: CGFloat = max(1.0, 1.5 * zoom)
                    let offsetX = panOffset.width.truncatingRemainder(dividingBy: spacing)
                    let offsetY = panOffset.height.truncatingRemainder(dividingBy: spacing)
                    
                    let cols = Int(size.width / spacing) + 2
                    let rows = Int(size.height / spacing) + 2
                    
                    for col in 0...cols {
                        for row in 0...rows {
                            let x = CGFloat(col) * spacing + offsetX
                            let y = CGFloat(row) * spacing + offsetY
                            guard x >= -dotRadius, x <= size.width + dotRadius,
                                  y >= -dotRadius, y <= size.height + dotRadius else { continue }
                            let rect = CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2)
                            ctx.fill(Circle().path(in: rect), with: .color(SepiaTheme.ink.opacity(0.06)))
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPerson = nil
                    secondaryPerson = nil
                }
            }
        }
    }
    
    // MARK: - Fit to Screen
    
    private func fitToScreen(viewSize: CGSize, treeWidth: CGFloat, treeHeight: CGFloat) {
        guard treeWidth > 0, treeHeight > 0, viewSize.width > 0, viewSize.height > 0 else { return }
        
        let margin: CGFloat = 20
        let availW = viewSize.width - margin * 2
        let availH = viewSize.height - margin * 2
        
        let scaleW = availW / treeWidth
        let scaleH = availH / treeHeight
        let newZoom = min(min(scaleW, scaleH), 1.6) // don't exceed max zoom
        let clampedZoom = max(0.2, newZoom)
        
        // Center the tree in the viewport
        let scaledW = treeWidth * clampedZoom
        let scaledH = treeHeight * clampedZoom
        let offsetX = (viewSize.width - scaledW) / 2
        let offsetY = (viewSize.height - scaledH) / 2
        
        withAnimation(.easeInOut(duration: 0.3)) {
            zoom = clampedZoom
            panOffset = CGSize(width: offsetX, height: offsetY)
            dragStart = CGSize(width: offsetX, height: offsetY)
            magnifyStart = clampedZoom
        }
    }
    
    // MARK: - Layout (Buchheim-Jünger-Leipert algorithm adapted for family trees)
    //
    // The Buchheim algorithm is the O(n) state-of-the-art for tidy tree drawings.
    // Key properties:
    //   - Parents are centered over their children
    //   - Subtrees don't overlap (checked via contours)
    //   - Identical subtrees are drawn identically
    //   - Middle subtrees are evenly distributed when shifted
    //   - Uses "mod" accumulators to avoid O(n²) subtree shifts
    //   - Uses "threads" for O(n) contour traversal
    
    private func computeLayout() -> TreeLayout {
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
            for (key, val) in depths { depths[key] = val - minDepthVal }
        }
        
        // ─── STEP 2: Build a couple-anchored ancestor tree (LayoutNode) ───
        // Each LayoutNode is a "couple unit": the two partners drawn adjacently,
        // plus each partner's siblings on their outer side. The unit's tidy-tree
        // children are the ancestor units of each partner (drawn in the band above,
        // their generation given by the depths map). Because married partners are
        // always adjacent and subtrees never interleave, marriage lines stay short
        // and connectors don't cross between branches.

        class LayoutNode {
            var memberIds: [UUID] = []   // people on this row, left → right
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

            init() { self.ancestor = nil }

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

        // Parent/sibling lookups that merge across split GEDCOM families
        // (a person's father and mother can be recorded in separate partial unions).
        func parentUnionsOf(_ pid: UUID) -> [Union] {
            tree.unions.filter { $0.childrenIds.contains(pid) }
        }
        func mergedParents(_ pid: UUID) -> (father: UUID?, mother: UUID?) {
            var father: UUID? = nil
            var mother: UUID? = nil
            for u in parentUnionsOf(pid) {
                for ppid in u.partnerIds {
                    guard let p = idx.byId[ppid] else { continue }
                    if p.sex == .male { if father == nil { father = ppid } }
                    else if p.sex == .female { if mother == nil { mother = ppid } }
                    else if father == nil { father = ppid }
                    else if mother == nil { mother = ppid }
                }
            }
            return (father, mother)
        }
        func mergedSiblings(_ pid: UUID) -> [UUID] {
            var seen = Set<UUID>([pid])
            var result: [UUID] = []
            for u in parentUnionsOf(pid) {
                for c in u.childrenIds where !seen.contains(c) {
                    seen.insert(c)
                    result.append(c)
                }
            }
            return result
        }

        var placedPersons = Set<UUID>()
        var rootNodes: [LayoutNode] = []

        // Build a unit anchored on `leftId` (and optional `rightId` partner).
        // Recurses upward into each anchor's ancestry.
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
            for m in members { placedPersons.insert(m) }
            node.memberIds = members
            let n = max(members.count, 1)
            node.width = CGFloat(n) * nodeWidth + CGFloat(n - 1) * memberGap

            // Ancestor fans (tidy-tree children), one per anchor partner.
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
            for (i, k) in kids.enumerated() { k.parent = node; k.number = i + 1 }
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
                for c in n.children { findMin(c, modSum: modSum + n.mod) }
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
                for c in n.children { findMax(c, modSum: modSum + n.mod) }
            }
            findMax(root, modSum: treeShift)
            globalOffset = maxX
        }

        // ─── STEP 5: Convert to screen coordinates ───
        
        var nodes: [TreeNode] = []
        var minB: CGFloat = .infinity
        var maxB: CGFloat = -.infinity
        var maxDepth: Int = 0
        
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
            links.append(TreeLink(id: "marriage-\(union.id)", segments: segments, personIds: Set(validPartners)))
        }

        // ── Child connectors (uniform routing) ──
        //
        // The trunk ("bus") that links a couple to their children runs across the
        // gap between two generations. Every trunk sits at the same fraction
        // (busFraction) of its gap, giving all connectors one consistent shape.
        struct ChildBus {
            let id: String
            let depth: Int            // parent generation index
            let ax: CGFloat           // parent-side stem position (cross-axis)
            let childCoords: [CGFloat] // child stem positions (cross-axis)
            let lo: CGFloat           // trunk span min (cross-axis)
            let hi: CGFloat           // trunk span max (cross-axis)
            let parentEdge: CGFloat   // main-axis: bottom/right edge of parents
            let childEdge: CGFloat    // main-axis: top/left edge of children
            let personIds: Set<UUID>
        }

        var buses: [ChildBus] = []
        for union in tree.unions {
            let validPartners = union.partnerIds.filter { placements[$0] != nil }
            let kids = union.childrenIds.filter { placements[$0] != nil }
            guard !kids.isEmpty, !validPartners.isEmpty else { continue }

            let parentBcs = validPartners.compactMap { placements[$0]?.bc }
            let ax = parentBcs.reduce(0, +) / CGFloat(parentBcs.count) + bShift
            let depth = placements[validPartners[0]]!.depth
            let childCoords = kids.compactMap { placements[$0]?.bc }.map { $0 + bShift }
            let span = childCoords + [ax]

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
                id: "children-\(union.id)", depth: depth, ax: ax, childCoords: childCoords,
                lo: span.min()!, hi: span.max()!, parentEdge: parentEdge, childEdge: childEdge,
                personIds: Set(validPartners + kids)
            ))
        }

        for bus in buses {
            // Uniform routing: every trunk sits at the same fraction of its
            // inter-generation gap. Because partners are adjacent and Buchheim
            // keeps subtrees from interleaving, trunks at the same height never
            // overlap — so all connectors share one consistent shape.
            let busPos = bus.parentEdge + (bus.childEdge - bus.parentEdge) * busFraction

            var segments: [LinkSegment] = []
            if direction == .topDown {
                // Stem from couple centre down to the trunk.
                segments.append(LinkSegment(from: CGPoint(x: bus.ax, y: bus.parentEdge), to: CGPoint(x: bus.ax, y: busPos)))
                // Horizontal trunk.
                segments.append(LinkSegment(from: CGPoint(x: bus.lo, y: busPos), to: CGPoint(x: bus.hi, y: busPos)))
                // Drops to each child.
                for cx in bus.childCoords {
                    segments.append(LinkSegment(from: CGPoint(x: cx, y: busPos), to: CGPoint(x: cx, y: bus.childEdge)))
                }
            } else {
                segments.append(LinkSegment(from: CGPoint(x: bus.parentEdge, y: bus.ax), to: CGPoint(x: busPos, y: bus.ax)))
                segments.append(LinkSegment(from: CGPoint(x: busPos, y: bus.lo), to: CGPoint(x: busPos, y: bus.hi)))
                for cy in bus.childCoords {
                    segments.append(LinkSegment(from: CGPoint(x: busPos, y: cy), to: CGPoint(x: bus.childEdge, y: cy)))
                }
            }
            links.append(TreeLink(id: bus.id, segments: segments, personIds: bus.personIds))
        }
        
        let totalWidth = direction == .topDown ? (maxB - minB) + 2 * pad : CGFloat(maxDepth) * genStep + cardW + 2 * pad
        let totalHeight = direction == .topDown ? CGFloat(maxDepth) * genStep + cardH + 2 * pad : (maxB - minB) + 2 * pad
        
        return TreeLayout(nodes: nodes, links: links, totalWidth: max(totalWidth, 600), totalHeight: max(totalHeight, 400))
    }
}

struct TreeNode: Equatable {
    let person: Person
    let x: CGFloat
    let y: CGFloat
    static func == (lhs: TreeNode, rhs: TreeNode) -> Bool {
        lhs.person.id == rhs.person.id && lhs.x == rhs.x && lhs.y == rhs.y
    }
}
struct TreeLink: Identifiable, Equatable {
    let id: String
    let segments: [LinkSegment]
    var personIds: Set<UUID> = []
}
struct LinkSegment: Equatable { let from: CGPoint; let to: CGPoint }
struct TreeLayout: Equatable { let nodes: [TreeNode]; let links: [TreeLink]; let totalWidth: CGFloat; let totalHeight: CGFloat }

struct PersonCardView: View, Equatable {
    let person: Person
    var isSelected: Bool = false
    var isSecondarySelected: Bool = false
    var isHome: Bool = false
    var isHighlighted: Bool = false
    var lineageLabel: String? = nil
    var showPhoto: Bool = false
    
    static func == (lhs: PersonCardView, rhs: PersonCardView) -> Bool {
        lhs.person.id == rhs.person.id &&
        lhs.person.givenNames == rhs.person.givenNames &&
        lhs.person.surname == rhs.person.surname &&
        lhs.person.maidenName == rhs.person.maidenName &&
        lhs.person.lifespan == rhs.person.lifespan &&
        lhs.isSelected == rhs.isSelected &&
        lhs.isSecondarySelected == rhs.isSecondarySelected &&
        lhs.isHome == rhs.isHome &&
        lhs.isHighlighted == rhs.isHighlighted &&
        lhs.lineageLabel == rhs.lineageLabel &&
        lhs.showPhoto == rhs.showPhoto
    }
    
    private var cardBackground: Color {
        switch person.sex {
        case .male: return SepiaTheme.cardBgMale
        case .female: return SepiaTheme.cardBgFemale
        case .unknown: return SepiaTheme.cardBg
        }
    }
    
    private var cardBorder: Color {
        switch person.sex {
        case .male: return SepiaTheme.cardLineMale
        case .female: return SepiaTheme.cardLineFemale
        case .unknown: return SepiaTheme.cardLine
        }
    }
    
    var body: some View {
        HStack(spacing: 0) {
            if showPhoto {
                if let data = person.photoData, let nsImage = NSImage(data: data) {
                    Image(nsImage: nsImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 54, height: 88)
                        .clipped()
                } else {
                    ZStack {
                        Rectangle().fill(SepiaTheme.cardLine.opacity(0.2))
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundColor(SepiaTheme.inkSoft.opacity(0.4))
                    }
                    .frame(width: 54, height: 88)
                }
            }
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) {
                    HStack(spacing: 4) {
                        Text(person.displaySurname.uppercased())
                            .font(SepiaTheme.ui(size: 8.5))
                            .tracking(1.2)
                            .foregroundColor(SepiaTheme.inkSoft)
                            .lineLimit(1)
                        if let maiden = person.maidenName, !maiden.isEmpty, !person.surname.isEmpty {
                            Text("(\(maiden.uppercased()))")
                                .font(SepiaTheme.ui(size: 7.5))
                                .tracking(0.8)
                                .foregroundColor(SepiaTheme.inkSoft.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    if isHome {
                        Circle().fill(SepiaTheme.accent).frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 7)
                .padding(.bottom, 4)
                
                Divider().overlay(SepiaTheme.cardRule)
                
                VStack(alignment: .leading, spacing: 2) {
                    let nameDisplay = [person.givenNames, person.patronymic ?? ""]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    Text(nameDisplay.isEmpty ? "Неизвестно" : nameDisplay)
                        .font(SepiaTheme.display(size: 14))
                        .fontWeight(.semibold)
                        .foregroundColor(SepiaTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                    if !person.lifespan.isEmpty {
                        Text(person.lifespan)
                            .font(SepiaTheme.body(size: 11))
                            .foregroundColor(SepiaTheme.inkSoft)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 8)
            }
        }
        .frame(width: 210, height: 90)
        .background(isHighlighted ? SepiaTheme.accent.opacity(0.08) : cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(
                    isSelected ? SepiaTheme.accent :
                    isSecondarySelected ? SepiaTheme.accent :
                    (isHighlighted ? SepiaTheme.accent2 : cardBorder),
                    lineWidth: (isSelected || isSecondarySelected) ? 3 : (isHighlighted ? 1.5 : 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .shadow(color: (isSelected || isSecondarySelected) ? SepiaTheme.accent.opacity(0.3) : .black.opacity(0.06), radius: (isSelected || isSecondarySelected) ? 4 : 2, y: 1)
        .overlay(alignment: .topTrailing) {
            if let label = lineageLabel {
                Text(label)
                    .font(SepiaTheme.ui(size: 9))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(SepiaTheme.accent.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(x: -4, y: 4)
            }
        }
    }
}
