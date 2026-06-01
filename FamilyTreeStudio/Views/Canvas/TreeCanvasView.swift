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
    private let spouseGap: CGFloat = 30
    private let siblingGap: CGFloat = 40
    private let familyGap: CGFloat = 60
    private let vGapTB: CGFloat = 110
    private let vGapLR: CGFloat = 150
    private let pad: CGFloat = 60
    
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
        
        // ─── STEP 2: Build a logical layout tree (LayoutNode) ───
        // Each LayoutNode represents a "family unit": a person (+ optional inline spouse)
        // with children as sub-nodes. This converts the graph into a proper tree
        // suitable for the Buchheim algorithm.
        
        class LayoutNode {
            let personId: UUID
            var spouseId: UUID? // inline spouse (placed adjacent, no parents in tree)
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
            
            // Width of this node (1 card or 2 cards + spouse gap)
            var width: CGFloat
            
            init(personId: UUID, nodeWidth: CGFloat, spouseGap: CGFloat) {
                self.personId = personId
                self.width = nodeWidth
                self.ancestor = nil // set to self after init
            }
            
            var leftSibling: LayoutNode? {
                guard let p = parent else { return nil }
                let idx = number - 1 // 0-based
                return idx > 0 ? p.children[idx - 1] : nil
            }
            
            var leftmostSibling: LayoutNode? {
                guard let p = parent else { return nil }
                let first = p.children[0]
                return first === self ? nil : first
            }
        }
        
        func hasParentsInTree(_ pid: UUID) -> Bool { idx.childOf[pid] != nil }
        
        func hasSpouseOnOtherSide(_ personId: UUID, mySide: Int) -> Bool {
            for union in idx.unionsOf[personId] ?? [] {
                for spouseId in union.partnerIds where spouseId != personId {
                    let spouseSide = side[spouseId] ?? 2
                    if spouseSide != mySide && spouseSide != 2 { return true }
                }
            }
            return false
        }
        
        var builtNodes: [UUID: LayoutNode] = [:]
        var rootNodes: [LayoutNode] = []
        
        // Recursive: build layout node for a person and their descendants
        func buildLayoutNode(_ personId: UUID) -> LayoutNode? {
            if builtNodes[personId] != nil { return nil } // already placed
            let node = LayoutNode(personId: personId, nodeWidth: nodeWidth, spouseGap: spouseGap)
            node.ancestor = node
            builtNodes[personId] = node
            
            let depth = depths[personId] ?? 0
            let unions = idx.unionsOf[personId] ?? []
            
            // Find inline spouse (no own parents → placed next to this person)
            var inlineSpouseId: UUID? = nil
            for union in unions {
                if let sid = union.partnerIds.first(where: { $0 != personId && builtNodes[$0] == nil && !hasParentsInTree($0) }) {
                    inlineSpouseId = sid
                    builtNodes[sid] = node // mark as placed (part of this node)
                    break
                }
            }
            node.spouseId = inlineSpouseId
            node.width = inlineSpouseId != nil ? (nodeWidth * 2 + spouseGap) : nodeWidth
            
            // Collect all children across all unions of this person (and inline spouse)
            var childIds: [UUID] = []
            for union in unions {
                let kids = union.childrenIds.filter { builtNodes[$0] == nil && depths[$0] == depth + 1 }
                childIds.append(contentsOf: kids)
            }
            // Also check unions of inline spouse
            if let sid = inlineSpouseId {
                for union in idx.unionsOf[sid] ?? [] {
                    let kids = union.childrenIds.filter { builtNodes[$0] == nil && depths[$0] == depth + 1 }
                    childIds.append(contentsOf: kids)
                }
            }
            // Deduplicate while preserving order
            var seen = Set<UUID>()
            childIds = childIds.filter { seen.insert($0).inserted }
            
            // Reorder: children who have a spouse on the "right side" go last (rightmost)
            // so they are adjacent to the right-side tree and don't cause overlap
            childIds.sort { c1, c2 in
                let c1HasRightSpouse = hasSpouseOnOtherSide(c1, mySide: side[personId] ?? 2)
                let c2HasRightSpouse = hasSpouseOnOtherSide(c2, mySide: side[personId] ?? 2)
                if c1HasRightSpouse && !c2HasRightSpouse { return false } // c1 goes last
                if !c1HasRightSpouse && c2HasRightSpouse { return true }  // c2 goes last
                return false // preserve order
            }
            
            // Build child layout nodes recursively
            for cid in childIds {
                if let childNode = buildLayoutNode(cid) {
                    childNode.parent = node
                    node.children.append(childNode)
                }
            }
            // Assign sibling numbers
            for (i, child) in node.children.enumerated() {
                child.number = i + 1
            }
            
            return node
        }
        
        // Build layout trees starting from the topmost generation
        // Separate into left side (partner 1's lineage) and right side (partner 2's lineage)
        // to prevent family lines from interleaving
        
        // Trace ancestors to determine which "side" each person belongs to
        var side: [UUID: Int] = [:] // 0 = left (partner1), 1 = right (partner2), 2 = shared/children
        
        func traceAncestors(from personId: UUID, sideValue: Int) {
            guard side[personId] == nil else { return }
            side[personId] = sideValue
            if let parentUnion = idx.childOf[personId] {
                for pid in parentUnion.partnerIds {
                    traceAncestors(from: pid, sideValue: sideValue)
                }
                // Siblings also belong to same side
                for sibId in parentUnion.childrenIds where sibId != personId {
                    if side[sibId] == nil { side[sibId] = sideValue }
                }
            }
        }
        
        if let rootUnion = tree.rootUnion {
            if let p1id = rootUnion.partner1Id {
                traceAncestors(from: p1id, sideValue: 0)
            }
            if let p2id = rootUnion.partner2Id {
                traceAncestors(from: p2id, sideValue: 1)
            }
            // Children of root union are shared — trace their spouses to appropriate side
            for childId in rootUnion.childrenIds {
                if side[childId] == nil { side[childId] = 2 }
                // Each child's spouse's ancestors go to the opposite side of that child
                for childUnion in idx.unionsOf[childId] ?? [] {
                    for spouseId in childUnion.partnerIds where spouseId != childId {
                        if side[spouseId] == nil {
                            // Spouse's ancestry traced to whichever side hasn't claimed them
                            let spouseSide = (side[childId] == 0) ? 1 : 0
                            traceAncestors(from: spouseId, sideValue: spouseSide)
                        }
                    }
                }
            }
        }
        
        // For deeper descendants, propagate side affinity
        func propagateSide(_ personId: UUID, sideValue: Int) {
            for union in idx.unionsOf[personId] ?? [] {
                for childId in union.childrenIds {
                    if side[childId] == nil {
                        side[childId] = sideValue
                        propagateSide(childId, sideValue: sideValue)
                    }
                }
                for spouseId in union.partnerIds where spouseId != personId {
                    if side[spouseId] == nil {
                        let spouseSide = (sideValue == 0) ? 1 : 0
                        side[spouseId] = spouseSide
                        traceAncestors(from: spouseId, sideValue: spouseSide)
                        propagateSide(spouseId, sideValue: spouseSide)
                    }
                }
            }
        }
        
        if let rootUnion = tree.rootUnion {
            if let p1id = rootUnion.partner1Id { propagateSide(p1id, sideValue: 0) }
            if let p2id = rootUnion.partner2Id { propagateSide(p2id, sideValue: 1) }
            for childId in rootUnion.childrenIds {
                propagateSide(childId, sideValue: side[childId] ?? 2)
            }
        }
        
        // Build layout trees: left side first, then right side
        let maxDepthVal = depths.values.max() ?? 0
        
        // Build left side (partner 1's ancestry)
        for gen in 0...maxDepthVal {
            let peopleAtGen = tree.people
                .filter { depths[$0.id] == gen && builtNodes[$0.id] == nil && (side[$0.id] ?? 2) == 0 }
                .sorted { ($0.id.uuidString) < ($1.id.uuidString) }
            for person in peopleAtGen {
                if let node = buildLayoutNode(person.id) {
                    rootNodes.append(node)
                }
            }
        }
        
        // Build right side (partner 2's ancestry)
        for gen in 0...maxDepthVal {
            let peopleAtGen = tree.people
                .filter { depths[$0.id] == gen && builtNodes[$0.id] == nil && (side[$0.id] ?? 2) == 1 }
                .sorted { ($0.id.uuidString) < ($1.id.uuidString) }
            for person in peopleAtGen {
                if let node = buildLayoutNode(person.id) {
                    rootNodes.append(node)
                }
            }
        }
        
        // Build any remaining (shared/unassigned)
        for gen in 0...maxDepthVal {
            let peopleAtGen = tree.people
                .filter { depths[$0.id] == gen && builtNodes[$0.id] == nil }
                .sorted { ($0.id.uuidString) < ($1.id.uuidString) }
            for person in peopleAtGen {
                if let node = buildLayoutNode(person.id) {
                    rootNodes.append(node)
                }
            }
        }
        
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
            let finalX = v.x + modSum
            let d = depths[v.personId] ?? depth
            positions[v.personId] = (finalX, d)
            
            // Place inline spouse centered within node width
            if let sid = v.spouseId {
                let halfOffset = (nodeWidth + spouseGap) / 2
                // Determine which side to place the spouse:
                // If person has a right sibling, spouse goes LEFT
                // If person has no right sibling (rightmost or only), spouse goes RIGHT
                let hasRightSibling = v.parent.map { p in
                    p.children.last !== v
                } ?? false
                
                if hasRightSibling {
                    // Spouse on the left, person on the right
                    positions[sid] = (finalX - halfOffset, d)
                    positions[v.personId] = (finalX + halfOffset, d)
                } else {
                    // Person on the left, spouse on the right
                    positions[v.personId] = (finalX - halfOffset, d)
                    positions[sid] = (finalX + halfOffset, d)
                }
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
        
        // ─── Post-process: Center children between cross-tree parents ───
        // When both parents have their own ancestry (separate layout trees),
        // shift the child subtree so it's centered between its two parents.
        for union in tree.unions {
            let validPartners = union.partnerIds.filter { placements[$0] != nil }
            guard validPartners.count == 2 else { continue }
            let kids = union.childrenIds.filter { placements[$0] != nil }
            guard !kids.isEmpty else { continue }
            
            // Only adjust if parents are in different sides
            let s0 = side[validPartners[0]] ?? 2
            let s1 = side[validPartners[1]] ?? 2
            guard s0 != s1 || (s0 == 2 && s1 == 2 && validPartners.count == 2) else { continue }
            // Only if no inline spouse (both have parents)
            guard hasParentsInTree(validPartners[0]) && hasParentsInTree(validPartners[1]) else { continue }
            
            let parentMid = (placements[validPartners[0]]!.bc + placements[validPartners[1]]!.bc) / 2
            
            // Find current midpoint of children
            let childBcs = kids.compactMap { placements[$0]?.bc }
            let childMid = (childBcs.min()! + childBcs.max()!) / 2
            let shift = parentMid - childMid
            
            guard abs(shift) > 1 else { continue }
            
            // Shift all descendants of these children
            func shiftSubtree(_ personId: UUID, by delta: CGFloat) {
                guard var pl = placements[personId] else { return }
                pl.bc += delta
                placements[personId] = pl
                // Shift inline spouse too
                if let node = builtNodes[personId], let sid = node.spouseId {
                    if var spl = placements[sid] {
                        spl.bc += delta
                        placements[sid] = spl
                    }
                }
                // Shift descendants
                for u in idx.unionsOf[personId] ?? [] {
                    for cid in u.childrenIds where cid != personId {
                        if let cpl = placements[cid], cpl.depth > pl.depth {
                            shiftSubtree(cid, by: delta)
                        }
                    }
                }
            }
            
            for kid in kids {
                shiftSubtree(kid, by: shift)
            }
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
        for union in tree.unions {
            let validPartners = union.partnerIds.filter { placements[$0] != nil }
            
            // Marriage line
            if validPartners.count == 2 {
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
            
            // Child connectors (T-junction)
            let kids = union.childrenIds.filter { placements[$0] != nil }
            if !kids.isEmpty && !validPartners.isEmpty {
                var segments: [LinkSegment] = []
                if direction == .topDown {
                    let parentBcs = validPartners.compactMap { placements[$0]?.bc }
                    let ax = parentBcs.reduce(0, +) / CGFloat(parentBcs.count) + bShift
                    let parentDepth = placements[validPartners[0]]!.depth
                    let parentBottom = CGFloat(parentDepth) * genStep + pad + cardH
                    let childTop = kids.compactMap { placements[$0]?.depth }.map { CGFloat($0) * genStep + pad }.min()!
                    // Route bus in the gap between parent and children (1/3 from parent)
                    let busY = parentBottom + (childTop - parentBottom) * 0.35
                    
                    // Vertical drop from couple center to bus
                    segments.append(LinkSegment(from: CGPoint(x: ax, y: parentBottom), to: CGPoint(x: ax, y: busY)))
                    // Horizontal bus
                    let childXs = kids.compactMap { placements[$0]?.bc }.map { $0 + bShift }
                    let allXs = childXs + [ax]
                    segments.append(LinkSegment(from: CGPoint(x: allXs.min()!, y: busY), to: CGPoint(x: allXs.max()!, y: busY)))
                    // Drops to each child
                    for cx in childXs {
                        segments.append(LinkSegment(from: CGPoint(x: cx, y: busY), to: CGPoint(x: cx, y: childTop)))
                    }
                } else {
                    let parentBcs = validPartners.compactMap { placements[$0]?.bc }
                    let ay = parentBcs.reduce(0, +) / CGFloat(parentBcs.count) + bShift
                    let parentDepth = placements[validPartners[0]]!.depth
                    let parentRight = CGFloat(parentDepth) * genStep + pad + cardW
                    let childLeft = kids.compactMap { placements[$0]?.depth }.map { CGFloat($0) * genStep + pad }.min()!
                    let busX = parentRight + (childLeft - parentRight) * 0.35
                    
                    segments.append(LinkSegment(from: CGPoint(x: parentRight, y: ay), to: CGPoint(x: busX, y: ay)))
                    let childYs = kids.compactMap { placements[$0]?.bc }.map { $0 + bShift }
                    let allYs = childYs + [ay]
                    segments.append(LinkSegment(from: CGPoint(x: busX, y: allYs.min()!), to: CGPoint(x: busX, y: allYs.max()!)))
                    for cy in childYs {
                        segments.append(LinkSegment(from: CGPoint(x: busX, y: cy), to: CGPoint(x: childLeft, y: cy)))
                    }
                }
                links.append(TreeLink(id: "children-\(union.id)", segments: segments, personIds: Set(validPartners + kids)))
            }
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
