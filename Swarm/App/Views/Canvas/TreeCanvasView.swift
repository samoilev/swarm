import AppKit
import SwarmCore
import SwiftUI

struct TreeCanvasView: View {
    let tree: FamilyTree
    let direction: MainWorkspace.TreeDirection
    @Binding var zoom: CGFloat
    @Binding var selectedPerson: Person?
    @Binding var secondaryPerson: Person?
    var highlightedIds: Set<UUID> = []
    var highlightedConnections: Set<FamilyConnection> = []
    var lineageLabels: [UUID: String] = [:]
    @Binding var fitRequest: Int
    @Binding var initialFocusCompleted: Bool
    var showPhotos: Bool = false
    /// Set while a library card is opening into this canvas. The cards for `morphNodeIDs`
    /// take their arrival geometry from the card's diagram instead of the entrance cascade.
    var morphNamespace: Namespace.ID?
    var morphNodeIDs: Set<UUID> = []

    private let cardW: CGFloat = 210
    private let cardH: CGFloat = 90
    private let initialFocusZoom: CGFloat = 0.8
    /// The record can move slightly beyond the viewport edge, but never disappear
    /// into unbounded empty canvas after an accidental drag or momentum fling.
    private let canvasOverscroll: CGFloat = 120
    /// Rasterize once at 2×, then zoom with one GPU transform. At maximum zoom the
    /// bitmap is 1:1; lower zoom levels downsample it.
    private let superSample: CGFloat = 2
    private let zoomSensitivity: CGFloat = 0.5 // <1 makes pinch-zoom softer (0 = no zoom, 1 = 1:1 with fingers)
    private let wheelZoomSensitivity: CGFloat = 0.05 // mouse-wheel zoom step per scroll unit (soft)

    @State private var panOffset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var magnifyStart: CGFloat = 1.0
    @State private var panAtMagnifyStart: CGSize = .zero
    @State private var isMagnifying = false
    /// Momentum scrolling: points per second, decayed on the display's own clock while
    /// non-zero (see `InertiaDriver`). Zero means the canvas is at rest and nothing ticks.
    @State private var coastVelocity: CGSize = .zero
    /// Layout only depends on tree structure + direction, so cache it and recompute
    /// only when those change — body re-runs on every pan/zoom frame otherwise.
    @State private var cachedLayout: TreeLayout?
    /// Equality key for cached content and minimap layers. Bumped with each layout.
    @State private var layoutGeneration = 0
    /// Connector paths can't interpolate between two layouts, so they fade out for the
    /// duration of a morph and fade back in against the new geometry.
    @State private var connectorOpacity: Double = 1
    @State private var initialFocusWorkItem: DispatchWorkItem?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Lets the canvas receive arrow keys for relationship traversal.
    @FocusState private var canvasFocused: Bool

    var body: some View {
        GeometryReader { geo in
            let layout = cachedLayout ?? makeLayout()

            ZStack(alignment: .topLeading) {
                // Dot grid background (Miro-style) — fills the viewport, tap to deselect
                Canvas { ctx, size in
                    // Dot count is viewport_area / spacing², so an un-clamped 20·zoom
                    // spacing explodes when zoomed out (zoom 0.2 → ~4px spacing →
                    // ~65k dots/frame). Clamp the on-screen spacing to keep the count
                    // bounded (and the grid from turning into a haze when zoomed out).
                    let spacing: CGFloat = max(20, 20 * zoom)
                    let dotRadius: CGFloat = max(1.0, 1.5 * zoom)
                    let offsetX = panOffset.width.truncatingRemainder(dividingBy: spacing)
                    let offsetY = panOffset.height.truncatingRemainder(dividingBy: spacing)

                    let cols = Int(size.width / spacing) + 2
                    let rows = Int(size.height / spacing) + 2

                    // Accumulate every dot into one Path and fill once — a single batched
                    // draw call instead of thousands of per-dot fills keeps panning smooth.
                    var dots = Path()
                    for col in 0 ... cols {
                        for row in 0 ... rows {
                            let x = CGFloat(col) * spacing + offsetX
                            let y = CGFloat(row) * spacing + offsetY
                            guard x >= -dotRadius, x <= size.width + dotRadius,
                                  y >= -dotRadius, y <= size.height + dotRadius else { continue }
                            dots.addEllipse(in: CGRect(x: x - dotRadius, y: y - dotRadius, width: dotRadius * 2, height: dotRadius * 2))
                        }
                    }
                    ctx.fill(dots, with: .color(SepiaTheme.ink.opacity(0.06)))
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPerson = nil
                    secondaryPerson = nil
                }
                .accessibilityHidden(true)

                // Connectors — vector Path strokes at base resolution, not a giant
                // supersampled Canvas bitmap, which lagged a frame behind the cards and
                // made the lines "jump" during movement). Scaled by `zoom` (vs the cards'
                // `zoom/superSample`) so the two layers stay pixel-aligned at every frame.
                TreeConnectorsLayer(
                    layout: layout,
                    generation: layoutGeneration,
                    highlightedConnections: highlightedConnections
                )
                .equatable()
                .opacity(connectorOpacity)
                .scaleEffect(zoom, anchor: .topLeading)
                .offset(x: panOffset.width, y: panOffset.height)

                // Tree content — isolated in an Equatable layer so that pan/zoom (which
                // change panOffset/zoom every frame) only re-apply the .scaleEffect/.offset
                // transform on a cached layer tree, instead of re-running the whole card
                // ForEach each frame. It re-renders only when selection or layout changes.
                TreeContentLayer(
                    layout: layout,
                    generation: layoutGeneration,
                    selectedId: selectedPerson?.id,
                    secondaryId: secondaryPerson?.id,
                    homeId: tree.homePersonId,
                    highlightedIds: highlightedIds,
                    lineageLabels: lineageLabels,
                    showPhotos: showPhotos,
                    superSample: superSample,
                    cardW: cardW,
                    cardH: cardH,
                    isLeftRight: direction == .leftRight,
                    morphNamespace: morphNamespace,
                    morphNodeIDs: morphNodeIDs,
                    onSelect: { person, commandClick in
                        if commandClick {
                            // CMD+click: set as secondary (max 2)
                            if selectedPerson == nil {
                                selectedPerson = person
                            } else if person.id == selectedPerson?.id {
                                // Clicking primary again with CMD — ignore
                            } else {
                                secondaryPerson = person
                            }
                        } else {
                            secondaryPerson = nil
                            selectedPerson = person
                        }
                    }
                )
                .equatable()
                .scaleEffect(zoom / superSample, anchor: .topLeading)
                .offset(x: panOffset.width, y: panOffset.height)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                // Minimap — only once the tree is zoomed in past the viewport, so there's
                // enough off-screen content to need an overview.
                if !layout.nodes.isEmpty,
                   layout.totalWidth * zoom > geo.size.width || layout.totalHeight * zoom > geo.size.height {
                    TreeMinimap(
                        layout: layout, generation: layoutGeneration, zoom: zoom, panOffset: panOffset, viewSize: geo.size,
                        selectedId: selectedPerson?.id, cardW: cardW, cardH: cardH,
                        onRecenter: { treePoint in
                            recenter(
                                onTreePoint: treePoint,
                                viewSize: geo.size,
                                layout: layout,
                                animated: false
                            )
                        }
                    )
                    .padding(12)
                    .transition(.opacity)
                }
            }
            .sepiaMotion(SepiaMotion.crossfade, value: layout.totalWidth * zoom > geo.size.width || layout.totalHeight * zoom > geo.size.height)
            .background(
                // Mouse-wheel / scroll zoom, soft and anchored to the cursor.
                ScrollWheelZoom { deltaY, location in
                    cancelInitialFocus()
                    var factor = 1 + deltaY * wheelZoomSensitivity
                    factor = min(1.25, max(0.8, factor))
                    let newZoom = min(2.0, max(0.2, zoom * factor))
                    guard newZoom != zoom else { return }
                    let ratio = newZoom / zoom
                    let proposedPan = CGSize(
                        width: location.x - (location.x - panOffset.width) * ratio,
                        height: location.y - (location.y - panOffset.height) * ratio
                    )
                    let newPan = constrainedPan(
                        proposedPan,
                        viewSize: geo.size,
                        treeWidth: layout.totalWidth,
                        treeHeight: layout.totalHeight,
                        atZoom: newZoom
                    )
                    coastVelocity = .zero
                    withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.82)) {
                        zoom = newZoom
                        panOffset = newPan
                    }
                    dragStart = newPan
                }
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        cancelInitialFocus()
                        coastVelocity = .zero // grabbing the canvas stops the coast dead
                        let proposedPan = CGSize(
                            width: dragStart.width + value.translation.width,
                            height: dragStart.height + value.translation.height
                        )
                        panOffset = constrainedPan(
                            proposedPan,
                            viewSize: geo.size,
                            treeWidth: layout.totalWidth,
                            treeHeight: layout.totalHeight,
                            atZoom: zoom
                        )
                    }
                    .onEnded { value in
                        dragStart = panOffset
                        // `value.velocity` is points per second, measured by the system —
                        // more accurate than differencing our own frames, and it lets the
                        // decay below be expressed in real time rather than in frames.
                        coastVelocity = reduceMotion ? .zero : value.velocity
                    }
            )
            // Only present while the canvas is actually coasting, so nothing ticks at rest.
            .overlay {
                if coastVelocity != .zero {
                    InertiaDriver { dt in
                        coast(
                            dt,
                            viewSize: geo.size,
                            treeWidth: layout.totalWidth,
                            treeHeight: layout.totalHeight
                        )
                    }
                }
            }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        cancelInitialFocus()
                        // Capture the zoom/pan baseline once at the start of the
                        // gesture. (value.magnification is cumulative from the
                        // gesture's start, so the baseline must not move mid-pinch
                        // — otherwise the zoom compounds and feels hypersensitive.)
                        if !isMagnifying {
                            isMagnifying = true
                            magnifyStart = zoom
                            panAtMagnifyStart = panOffset
                            coastVelocity = .zero
                        }
                        // Soften the response for a gentle, map-like feel.
                        let damped = 1 + (value.magnification - 1) * zoomSensitivity
                        let newZoom = min(2.0, max(0.2, magnifyStart * damped))
                        // Zoom about the viewport centre so the content doesn't
                        // lurch toward a corner (the scaleEffect anchor is topLeading).
                        let ratio = newZoom / magnifyStart
                        let cx = geo.size.width / 2
                        let cy = geo.size.height / 2
                        let proposedPan = CGSize(
                            width: cx - (cx - panAtMagnifyStart.width) * ratio,
                            height: cy - (cy - panAtMagnifyStart.height) * ratio
                        )
                        panOffset = constrainedPan(
                            proposedPan,
                            viewSize: geo.size,
                            treeWidth: layout.totalWidth,
                            treeHeight: layout.totalHeight,
                            atZoom: newZoom
                        )
                        zoom = newZoom
                    }
                    .onEnded { _ in
                        isMagnifying = false
                        magnifyStart = zoom
                        dragStart = panOffset
                    }
            )
            .onAppear {
                magnifyStart = zoom
                let isNewCanvas = cachedLayout == nil
                if isNewCanvas { cachedLayout = makeLayout() }
                if !initialFocusCompleted {
                    fitToScreen(
                        viewSize: geo.size,
                        treeWidth: layout.totalWidth,
                        treeHeight: layout.totalHeight,
                        animated: false
                    )
                    initialFocusCompleted = true
                    scheduleInitialHomeFocus(viewSize: geo.size, layout: layout)
                } else if isNewCanvas {
                    // Re-entering the tree (for example after opening the inspector or
                    // visiting another view) keeps the user's zoom instead of replaying
                    // the opening fit. A fresh pan state is simply anchored on home.
                    focusHome(
                        viewSize: geo.size,
                        layout: layout,
                        targetZoom: zoom,
                        animated: false
                    )
                }
                canvasFocused = true
            }
            .onDisappear {
                cancelInitialFocus()
                coastVelocity = .zero
            }
            .onChange(of: tree.layoutVersion) { _, _ in
                cancelInitialFocus()
                // An edit shouldn't yank the viewport: re-fit only when the new layout no
                // longer fits at the current zoom. Direction changes and ⌘0 always re-fit.
                applyLayout(makeLayout(), viewSize: geo.size, refit: .ifOverflowing)
            }
            .onChange(of: direction) { _, _ in
                cancelInitialFocus()
                applyLayout(makeLayout(), viewSize: geo.size, refit: .always)
            }
            .onChange(of: fitRequest) { _, _ in
                cancelInitialFocus()
                fitToScreen(viewSize: geo.size, treeWidth: layout.totalWidth, treeHeight: layout.totalHeight)
            }
            .onChange(of: selectedPerson?.id) { _, newValue in
                // Selecting a person (canvas tap, search, inspector link, arrow key) glides
                // the canvas to center them when they're off-screen, keeping the zoom.
                if newValue != nil {
                    cancelInitialFocus()
                    centerOnSelected(viewSize: geo.size, layout: layout)
                    canvasFocused = true
                }
            }
            .onChange(of: geo.size) { _, newSize in
                let bounded = constrainedPan(
                    panOffset,
                    viewSize: newSize,
                    treeWidth: layout.totalWidth,
                    treeHeight: layout.totalHeight,
                    atZoom: zoom
                )
                panOffset = bounded
                dragStart = bounded
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomInRequested)) { _ in
                cancelInitialFocus()
                applyZoomStep(delta: 0.1, viewSize: geo.size, layout: layout)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOutRequested)) { _ in
                cancelInitialFocus()
                applyZoomStep(delta: -0.1, viewSize: geo.size, layout: layout)
            }
            // Arrow keys walk the tree by relationship: ↑ parent, ↓ child,
            // ←/→ spouses and siblings along their visual axis.
            .focusable()
            .focusEffectDisabled()
            .focused($canvasFocused)
            .onMoveCommand { direction in moveSelection(direction, layout: layout) }
        }
    }

    /// Move the selection to a connected person along the family graph. ↑ a parent,
    /// ↓ the first child, ←/→ the previous/next spouse or sibling in visual order.
    private func moveSelection(_ direction: MoveCommandDirection, layout: TreeLayout) {
        guard let current = selectedPerson else { return }
        let idx = FamilyIndex(tree: tree)
        let nodeOf: (Person) -> TreeNode? = { person in
            layout.nodes.first(where: { $0.person.id == person.id })
        }
        let lateralPosition: (Person) -> CGFloat = { person in
            guard let node = nodeOf(person) else { return 0 }
            return self.direction == .leftRight ? node.y : node.x
        }
        var next: Person?
        switch direction {
        case .up:
            let parents = idx.parentsOf(current)
            next = parents.father ?? parents.mother
        case .down:
            next = idx.childrenOf(current).min(by: { lateralPosition($0) < lateralPosition($1) })
        case .left, .right:
            var seen = Set<UUID>()
            var group = (idx.siblingsOf(current) + idx.spousesOf(current) + [current])
                .filter { seen.insert($0.id).inserted }
            group.sort {
                let lhs = lateralPosition($0)
                let rhs = lateralPosition($1)
                return lhs == rhs ? $0.id.uuidString < $1.id.uuidString : lhs < rhs
            }
            if let i = group.firstIndex(where: { $0.id == current.id }) {
                let j = direction == .left ? i - 1 : i + 1
                if group.indices.contains(j) { next = group[j] }
            }
        @unknown default:
            next = nil
        }
        if let next {
            secondaryPerson = nil
            selectedPerson = next
        }
    }

    // MARK: - Layout changes

    private enum RefitPolicy { case always, ifOverflowing }

    /// Swap in a freshly computed layout. Cards keep their identity across the swap (the
    /// `ForEach` is keyed by `person.id`) and are placed with `.position`, which SwiftUI
    /// interpolates — so doing this inside one transaction makes every card glide to its
    /// new seat instead of teleporting. The connectors are `Path` strokes and cannot
    /// interpolate between two geometries, so they duck out and back around the move.
    private func applyLayout(_ l: TreeLayout, viewSize: CGSize, refit: RefitPolicy) {
        let overflows = l.totalWidth * zoom > viewSize.width || l.totalHeight * zoom > viewSize.height
        let shouldRefit = refit == .always || overflows

        // Above this many cards the morph is N animated position changes per frame, which
        // is no longer free — a large tree gets the old instant swap.
        guard !reduceMotion, l.nodes.count <= 400 else {
            cachedLayout = l
            layoutGeneration += 1
            connectorOpacity = 1
            if shouldRefit {
                fitToScreen(viewSize: viewSize, treeWidth: l.totalWidth, treeHeight: l.totalHeight)
            } else {
                let bounded = constrainedPan(
                    panOffset,
                    viewSize: viewSize,
                    treeWidth: l.totalWidth,
                    treeHeight: l.totalHeight,
                    atZoom: zoom
                )
                panOffset = bounded
                dragStart = bounded
            }
            return
        }

        withAnimation(.easeOut(duration: 0.12)) { connectorOpacity = 0 }
        withAnimation(SepiaMotion.layout) {
            cachedLayout = l
            layoutGeneration += 1
        }
        if shouldRefit {
            // Same curve as the cards: the viewport and the tree move as one system rather
            // than as two timelines racing each other.
            fitToScreen(viewSize: viewSize, treeWidth: l.totalWidth, treeHeight: l.totalHeight, animation: SepiaMotion.layout)
        } else {
            let bounded = constrainedPan(
                panOffset,
                viewSize: viewSize,
                treeWidth: l.totalWidth,
                treeHeight: l.totalHeight,
                atZoom: zoom
            )
            panOffset = bounded
            dragStart = bounded
        }
        withAnimation(SepiaMotion.layout.delay(0.18)) { connectorOpacity = 1 }
    }

    // MARK: - Fit to Screen

    private func fitToScreen(
        viewSize: CGSize,
        treeWidth: CGFloat,
        treeHeight: CGFloat,
        animation: Animation? = nil,
        animated: Bool = true
    ) {
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

        coastVelocity = .zero // a fit overrides any momentum still in flight

        let fitAnimation: Animation? = animated && !reduceMotion
            ? (animation ?? .easeInOut(duration: 0.3))
            : nil
        withAnimation(fitAnimation) {
            zoom = clampedZoom
            panOffset = CGSize(width: offsetX, height: offsetY)
            dragStart = CGSize(width: offsetX, height: offsetY)
            magnifyStart = clampedZoom
        }
    }

    /// Show the whole record first, then move in on the home person at a stable 80%.
    /// A short pause lets the fitted overview register before the focused workspace takes
    /// over. Any direct manipulation cancels the pending move.
    private func scheduleInitialHomeFocus(viewSize: CGSize, layout: TreeLayout) {
        let focus = {
            focusHome(
                viewSize: viewSize,
                layout: layout,
                targetZoom: initialFocusZoom,
                animated: true
            )
            initialFocusWorkItem = nil
        }

        guard !reduceMotion else {
            focus()
            return
        }
        let workItem = DispatchWorkItem(block: focus)
        initialFocusWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55, execute: workItem)
    }

    private func focusHome(
        viewSize: CGSize,
        layout: TreeLayout,
        targetZoom: CGFloat,
        animated: Bool
    ) {
        guard let homeID = tree.homePersonId,
              let home = layout.nodes.first(where: { $0.person.id == homeID }) else { return }
        let center = CGPoint(x: home.x + cardW / 2, y: home.y + cardH / 2)
        let proposedPan = CGSize(
            width: viewSize.width / 2 - center.x * targetZoom,
            height: viewSize.height / 2 - center.y * targetZoom
        )
        let targetPan = constrainedPan(
            proposedPan,
            viewSize: viewSize,
            treeWidth: layout.totalWidth,
            treeHeight: layout.totalHeight,
            atZoom: targetZoom
        )
        coastVelocity = .zero
        let animation: Animation? = animated && !reduceMotion
            ? .easeInOut(duration: 1.2)
            : nil
        withAnimation(animation) {
            zoom = targetZoom
            panOffset = targetPan
        }
        dragStart = targetPan
        magnifyStart = targetZoom
    }

    private func cancelInitialFocus() {
        initialFocusWorkItem?.cancel()
        initialFocusWorkItem = nil
    }

    /// Pan (keeping the current zoom) so the selected card is centered — but only when
    /// it's off-screen or near an edge, so clicking a card already in view doesn't jolt
    /// the whole tree. Honors Reduce Motion (instant when set).
    private func centerOnSelected(viewSize: CGSize, layout: TreeLayout) {
        guard let id = selectedPerson?.id,
              let n = layout.nodes.first(where: { $0.person.id == id }) else { return }
        let centerPoint = CGPoint(x: n.x + cardW / 2, y: n.y + cardH / 2)
        // Where the card center currently sits on screen.
        let screenX = centerPoint.x * zoom + panOffset.width
        let screenY = centerPoint.y * zoom + panOffset.height
        let marginX = viewSize.width * 0.12
        let marginY = viewSize.height * 0.12
        let comfortablyVisible = screenX >= marginX && screenX <= viewSize.width - marginX
            && screenY >= marginY && screenY <= viewSize.height - marginY
        guard !comfortablyVisible else { return }
        recenter(onTreePoint: centerPoint, viewSize: viewSize, layout: layout)
    }

    /// Pan so a given point in tree coordinates sits at the viewport center.
    /// (screen = treePoint·zoom + panOffset, so panOffset = center − treePoint·zoom.)
    /// `animated` is forced off for Reduce Motion and for live minimap dragging.
    private func recenter(
        onTreePoint p: CGPoint,
        viewSize: CGSize,
        layout: TreeLayout,
        animated: Bool = true
    ) {
        let proposedPan = CGSize(
            width: viewSize.width / 2 - p.x * zoom,
            height: viewSize.height / 2 - p.y * zoom
        )
        let newPan = constrainedPan(
            proposedPan,
            viewSize: viewSize,
            treeWidth: layout.totalWidth,
            treeHeight: layout.totalHeight,
            atZoom: zoom
        )
        coastVelocity = .zero
        if animated, !reduceMotion {
            withAnimation(.easeInOut(duration: 0.25)) {
                panOffset = newPan
                dragStart = newPan
            }
        } else {
            panOffset = newPan
            dragStart = newPan
        }
    }

    // MARK: - Inertia (momentum scrolling)

    /// Zoom by `delta` anchored to the viewport centre (same math as scroll-wheel zoom).
    private func applyZoomStep(delta: CGFloat, viewSize: CGSize, layout: TreeLayout) {
        let newZoom = min(2.0, max(0.2, zoom + delta))
        guard newZoom != zoom else { return }
        let ratio = newZoom / zoom
        let cx = viewSize.width / 2
        let cy = viewSize.height / 2
        let proposedPan = CGSize(
            width: cx - (cx - panOffset.width) * ratio,
            height: cy - (cy - panOffset.height) * ratio
        )
        let newPan = constrainedPan(
            proposedPan,
            viewSize: viewSize,
            treeWidth: layout.totalWidth,
            treeHeight: layout.totalHeight,
            atZoom: newZoom
        )
        coastVelocity = .zero
        withAnimation(reduceMotion ? nil : .interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
            zoom = newZoom
            panOffset = newPan
        }
        dragStart = newPan
    }

    /// Advance the momentum coast by one display frame. Decay is expressed per *second*
    /// and raised to the elapsed time, so the glide is identical on a 60 Hz and a 120 Hz
    /// panel — the old fixed 1/60 timer beat against a ProMotion display and read as stutter.
    private func coast(
        _ dt: TimeInterval,
        viewSize: CGSize,
        treeWidth: CGFloat,
        treeHeight: CGFloat
    ) {
        let decayPerSecond = 0.0005 // ≈ the previous 0.88-per-frame feel, expressed in time
        let cutoff: CGFloat = 30 // points per second, below which the glide is over
        let k = CGFloat(pow(decayPerSecond, dt))
        var v = CGSize(width: coastVelocity.width * k, height: coastVelocity.height * k)

        if abs(v.width) < cutoff, abs(v.height) < cutoff { v = .zero }
        let proposedPan = CGSize(
            width: panOffset.width + v.width * CGFloat(dt),
            height: panOffset.height + v.height * CGFloat(dt)
        )
        let boundedPan = constrainedPan(
            proposedPan,
            viewSize: viewSize,
            treeWidth: treeWidth,
            treeHeight: treeHeight,
            atZoom: zoom
        )
        if boundedPan.width != proposedPan.width { v.width = 0 }
        if boundedPan.height != proposedPan.height { v.height = 0 }
        panOffset = boundedPan
        dragStart = panOffset
        coastVelocity = v
    }

    private func constrainedPan(
        _ proposed: CGSize,
        viewSize: CGSize,
        treeWidth: CGFloat,
        treeHeight: CGFloat,
        atZoom targetZoom: CGFloat
    ) -> CGSize {
        CGSize(
            width: constrainedAxis(
                proposed.width,
                viewportLength: viewSize.width,
                contentLength: treeWidth * targetZoom
            ),
            height: constrainedAxis(
                proposed.height,
                viewportLength: viewSize.height,
                contentLength: treeHeight * targetZoom
            )
        )
    }

    private func constrainedAxis(
        _ proposed: CGFloat,
        viewportLength: CGFloat,
        contentLength: CGFloat
    ) -> CGFloat {
        guard viewportLength > 0, contentLength > 0 else { return proposed }
        if contentLength <= viewportLength {
            let centered = (viewportLength - contentLength) / 2
            return min(centered + canvasOverscroll, max(centered - canvasOverscroll, proposed))
        }
        // When content overflows, allow enough edge space to bring an outermost
        // person near the viewport center, but cap it so the tree cannot be lost.
        let edgeFocusAllowance = min(360, max(canvasOverscroll, viewportLength * 0.45))
        let minimum = viewportLength - contentLength - edgeFocusAllowance
        let maximum = edgeFocusAllowance
        return min(maximum, max(minimum, proposed))
    }

    /// Build the tidy-tree layout via the pure engine in SwarmCore.
    private func makeLayout() -> TreeLayout {
        TreeLayoutEngine().layout(tree: tree, direction: direction == .leftRight ? .leftRight : .topDown)
    }
}

/// Ticks once per display refresh and reports the elapsed time, so momentum scrolling runs
/// on the panel's own clock (120 Hz on ProMotion) rather than a fixed 60 Hz timer. Invisible
/// and non-interactive; the canvas only keeps one alive while it is actually coasting.
///
/// Panning stays outside any animation transaction, so `panOffset` is always the value the
/// user can see — grabbing the canvas mid-glide picks up exactly where it looks like it is.
private struct InertiaDriver: View {
    let onTick: (TimeInterval) -> Void
    @State private var lastTick: Date?

    var body: some View {
        TimelineView(.animation) { timeline in
            Color.clear
                .frame(width: 0, height: 0)
                .onChange(of: timeline.date) { _, now in
                    defer { lastTick = now }
                    guard let last = lastTick else { return }
                    let dt = now.timeIntervalSince(last)
                    // Skip an implausible gap (window occluded, app suspended) rather than
                    // flinging the canvas across the tree on the first frame back.
                    guard dt > 0, dt < 0.25 else { return }
                    onTick(dt)
                }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Connector lines as vector `Path` strokes at base resolution. Kept as its own
/// Equatable layer (separate from the cards), not a giant supersampled bitmap;
/// vector strokes transform in lockstep with the card layers, fixing the "lines jump"
/// lag during movement. Refreshes only when the layout or highlight changes.
private struct TreeConnectorsLayer: View, Equatable {
    let layout: TreeLayout
    let generation: Int
    let highlightedConnections: Set<FamilyConnection>

    static func == (l: TreeConnectorsLayer, r: TreeConnectorsLayer) -> Bool {
        l.generation == r.generation
            && l.highlightedConnections == r.highlightedConnections
    }

    private func path(for segments: [LinkSegment]) -> Path {
        var p = Path()
        for segment in segments {
            p.move(to: segment.from)
            p.addLine(to: segment.to)
        }
        return p
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            path(for: layout.links.flatMap(\.segments))
                .stroke(SepiaTheme.line, style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))

            if !highlightedConnections.isEmpty {
                let activeSegments = layout.highlightRoutes
                    .filter { !$0.connections.isDisjoint(with: highlightedConnections) }
                    .flatMap(\.segments)
                path(for: activeSegments)
                    .stroke(SepiaTheme.accent, style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
            }
        }
        .frame(width: layout.totalWidth, height: layout.totalHeight, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The person cards, built at superSample scale. Equatable on its value inputs (layout
/// version, selection, highlight, flags) so SwiftUI skips re-evaluating the whole card
/// ForEach during pan/zoom — only the parent's transform updates then.
private struct TreeContentLayer: View, Equatable {
    let layout: TreeLayout
    let generation: Int
    let selectedId: UUID?
    let secondaryId: UUID?
    let homeId: UUID?
    let highlightedIds: Set<UUID>
    let lineageLabels: [UUID: String]
    let showPhotos: Bool
    let superSample: CGFloat
    let cardW: CGFloat
    let cardH: CGFloat
    let isLeftRight: Bool
    var morphNamespace: Namespace.ID?
    var morphNodeIDs: Set<UUID> = []
    let onSelect: (Person, Bool) -> Void

    /// Flipped on the first frame so the tree cascades in rather than appearing all at once.
    /// The cards' resting opacity is 1 — this only pulls them back for the frame before
    /// `.onAppear` runs, so a cascade that somehow never fires still leaves a visible tree.
    @State private var didAppear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static func == (l: TreeContentLayer, r: TreeContentLayer) -> Bool {
        // generation stands in for the (expensive to compare) layout; it bumps whenever
        // the cached layout is rebuilt, so structural changes always refresh.
        l.generation == r.generation &&
            l.selectedId == r.selectedId &&
            l.secondaryId == r.secondaryId &&
            l.homeId == r.homeId &&
            l.showPhotos == r.showPhotos &&
            l.superSample == r.superSample &&
            l.isLeftRight == r.isLeftRight &&
            l.highlightedIds == r.highlightedIds &&
            l.lineageLabels == r.lineageLabels &&
            l.morphNodeIDs == r.morphNodeIDs
    }

    /// Entrance delay for a card, proportional to how far along the tree's growth axis it
    /// sits — so the cascade reads as the tree unfolding from its root. Capped, so a deep
    /// tree doesn't make the user wait.
    private func entranceDelay(_ node: TreeNode) -> Double {
        let t = isLeftRight
            ? node.x / max(layout.totalWidth, 1)
            : node.y / max(layout.totalHeight, 1)
        return SepiaMotion.stagger(fraction: Double(t))
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Cards (connectors are a separate sibling layer — see TreeConnectorsLayer).
            ForEach(layout.nodes, id: \.person.id) { node in
                let isPrimary = selectedId == node.person.id
                let isSecondary = secondaryId == node.person.id
                // A card the library drew arrives by growing out of the card, not by
                // cascading — it is already on screen, at a smaller size, somewhere else.
                let isMorphing = morphNodeIDs.contains(node.person.id)
                let shown = didAppear || reduceMotion || isMorphing
                PersonCardView(
                    person: node.person,
                    isSelected: isPrimary,
                    isSecondarySelected: isSecondary,
                    isHome: homeId == node.person.id,
                    isHighlighted: highlightedIds.contains(node.person.id),
                    lineageLabel: lineageLabels[node.person.id],
                    showPhoto: showPhotos,
                    scale: superSample
                )
                .equatable()
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown ? 1 : 0.94)
                .sepiaMotion(SepiaMotion.select.delay(entranceDelay(node)), value: shown)
                .position(x: (node.x + cardW / 2) * superSample, y: (node.y + cardH / 2) * superSample)
                // Applied after `.position` on purpose: while the morph runs, the card's
                // geometry comes from the diagram node it grew out of, not from the layout.
                .modifier(TreeMorphGeometry(
                    namespace: isMorphing ? morphNamespace : nil,
                    personId: node.person.id,
                    isSource: false
                ))
                // A person added or deleted rides the layout morph's transaction: the new
                // card scales in while its new neighbours glide aside, and a removed one
                // collapses as the tree closes the gap.
                .transition(.scale(scale: 0.9).combined(with: .opacity))
                .onTapGesture {
                    onSelect(node.person, NSEvent.modifierFlags.contains(.command))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(node.person.accessibilityDescription)
                .accessibilityHint(L10n.tr("Выбрать персону"))
                .accessibilityAddTraits((isPrimary || isSecondary) ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { onSelect(node.person, false) }
            }
        }
        .frame(width: layout.totalWidth * superSample, height: layout.totalHeight * superSample, alignment: .topLeading)
        .onAppear { didAppear = true }
    }
}

/// Overview of the whole tree with the current viewport drawn on top. Shown only when
/// the tree is zoomed past the viewport; tap or drag to pan there.
private struct TreeMinimap: View {
    let layout: TreeLayout
    let generation: Int
    let zoom: CGFloat
    let panOffset: CGSize
    let viewSize: CGSize
    let selectedId: UUID?
    let cardW: CGFloat
    let cardH: CGFloat
    let onRecenter: (CGPoint) -> Void

    private let maxW: CGFloat = 210
    private let maxH: CGFloat = 175

    var body: some View {
        let m = min(maxW / max(layout.totalWidth, 1), maxH / max(layout.totalHeight, 1))
        let mapW = layout.totalWidth * m
        let mapH = layout.totalHeight * m
        // Current viewport rectangle (visible tree region): screen = tree·zoom + pan,
        // so the visible tree origin is −pan/zoom and its size is viewSize/zoom.
        let rawX = (-panOffset.width / zoom) * m
        let rawY = (-panOffset.height / zoom) * m
        let viewportW = min(mapW, max(1, (viewSize.width / zoom) * m))
        let viewportH = min(mapH, max(1, (viewSize.height / zoom) * m))
        let viewportX = min(max(0, rawX), max(0, mapW - viewportW))
        let viewportY = min(max(0, rawY), max(0, mapH - viewportH))

        ZStack(alignment: .topLeading) {
            // Static card map — Equatable, so panning the main canvas doesn't redraw it.
            MinimapNodes(layout: layout, generation: generation, selectedId: selectedId, m: m, cardW: cardW, cardH: cardH)
                .equatable()
                .frame(width: mapW, height: mapH)

            // Viewport indicator — a cheap moving layer (no per-frame node redraw).
            RoundedRectangle(cornerRadius: 1)
                .fill(SepiaTheme.accent.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 1)
                        .strokeBorder(SepiaTheme.accent, lineWidth: 1)
                )
                .frame(width: viewportW, height: viewportH)
                .offset(x: viewportX, y: viewportY)
                .allowsHitTesting(false)
        }
        .frame(width: mapW, height: mapH, alignment: .topLeading)
        .clipped()
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    onRecenter(CGPoint(x: value.location.x / m, y: value.location.y / m))
                }
        )
        .padding(8)
        .background(
            SepiaTheme.paper.opacity(0.58),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .glassEffect(
            .regular.interactive(),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(SepiaTheme.cardLine.opacity(0.42), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .help(L10n.tr("Обзор дерева — нажмите, чтобы перейти"))
        .accessibilityHidden(true)
    }
}

/// The minimap's card rectangles, batched into one fill. Equatable on the layout
/// version + selection so it is drawn once and skipped while the main canvas pans.
private struct MinimapNodes: View, Equatable {
    let layout: TreeLayout
    let generation: Int
    let selectedId: UUID?
    let m: CGFloat
    let cardW: CGFloat
    let cardH: CGFloat

    static func == (l: MinimapNodes, r: MinimapNodes) -> Bool {
        l.generation == r.generation && l.selectedId == r.selectedId && l.m == r.m
    }

    var body: some View {
        Canvas { ctx, _ in
            var rects = Path()
            for n in layout.nodes where n.person.id != selectedId {
                rects.addRoundedRect(in: CGRect(x: n.x * m, y: n.y * m, width: cardW * m, height: cardH * m), cornerSize: CGSize(width: 1, height: 1))
            }
            ctx.fill(rects, with: .color(SepiaTheme.line.opacity(0.55)))
            if let sel = selectedId, let n = layout.nodes.first(where: { $0.person.id == sel }) {
                let r = CGRect(x: n.x * m, y: n.y * m, width: cardW * m, height: cardH * m)
                ctx.fill(Path(roundedRect: r, cornerRadius: 1), with: .color(SepiaTheme.accent))
            }
        }
    }
}

/// Reports mouse-wheel / scroll-wheel events over the canvas as a zoom delta.
/// It installs a local scroll-wheel event monitor and keeps itself transparent
/// to mouse clicks (`hitTest` returns nil), so card taps and dragging to pan are
/// untouched — only scrolling while the cursor is over the canvas is consumed.
struct ScrollWheelZoom: NSViewRepresentable {
    let onScroll: (_ deltaY: CGFloat, _ location: CGPoint) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let v = CatcherView()
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onScroll = onScroll
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat, CGPoint) -> Void)?
        private var monitor: Any?

        override var isFlipped: Bool {
            true
        } // top-left origin to match SwiftUI
        override func hitTest(_ point: NSPoint) -> NSView? {
            nil
        } // pass clicks through

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Always clear any existing monitor first so view recycling / window
            // changes can't leave duplicate monitors installed.
            if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
            if window != nil {
                if monitor == nil {
                    monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                        guard let self, let w = self.window, event.window === w else { return event }
                        let locView = self.convert(event.locationInWindow, from: nil)
                        guard self.bounds.contains(locView) else { return event }
                        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.deltaY
                        if dy != 0 {
                            self.onScroll?(dy, locView)
                            return nil // consume: we turned it into a zoom
                        }
                        return event
                    }
                }
            } else if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }

        deinit { if let m = monitor { NSEvent.removeMonitor(m) } }
    }
}

struct PersonCardView: View, Equatable {
    let person: Person
    var language: AppLanguage = .current
    var isSelected: Bool = false
    var isSecondarySelected: Bool = false
    var isHome: Bool = false
    var isHighlighted: Bool = false
    var lineageLabel: String?
    var showPhoto: Bool = false
    /// Zoom factor. The card renders at its real scaled size (fonts included) so the
    /// text stays crisp at any zoom, instead of being a 1× bitmap stretched by the canvas.
    var scale: CGFloat = 1

    /// Pointer feedback. Deliberately *local* state: it invalidates this one card only,
    /// so the `.equatable()` isolation that keeps pan/zoom from re-running the whole card
    /// `ForEach` (see `TreeContentLayer`) still holds.
    ///
    /// There is no press state here on purpose. Any gesture on the card that recognises on
    /// mouse-down — even a `simultaneousGesture` — swallows the tap that selects a person,
    /// and a `.gesture` would additionally stop the canvas being panned from a card. The
    /// hover lift is the affordance and the selection ring is the acknowledgement; both
    /// land well inside the 80 ms that reads as instant.
    @State private var isHovering = false

    static func == (lhs: PersonCardView, rhs: PersonCardView) -> Bool {
        lhs.person.id == rhs.person.id &&
            lhs.person.givenNames == rhs.person.givenNames &&
            lhs.person.surname == rhs.person.surname &&
            lhs.person.maidenName == rhs.person.maidenName &&
            lhs.person.lifespan == rhs.person.lifespan &&
            lhs.person.sex == rhs.person.sex &&
            lhs.language == rhs.language &&
            lhs.isSelected == rhs.isSelected &&
            lhs.isSecondarySelected == rhs.isSecondarySelected &&
            lhs.isHome == rhs.isHome &&
            lhs.isHighlighted == rhs.isHighlighted &&
            lhs.lineageLabel == rhs.lineageLabel &&
            lhs.showPhoto == rhs.showPhoto &&
            lhs.scale == rhs.scale
    }

    /// Scale a base point value by the current zoom.
    private func s(_ v: CGFloat) -> CGFloat {
        v * scale
    }

    private var isChosen: Bool { isSelected || isSecondarySelected }

    /// Hover lifts a card toward white along *its own* hue (see the `*Hover` tokens): the
    /// pointer should raise the card off the paper, not restate the person's sex.
    private var cardBackground: Color {
        switch person.sex {
        case .male: isHovering ? SepiaTheme.cardBgMaleHover : SepiaTheme.cardBgMale
        case .female: isHovering ? SepiaTheme.cardBgFemaleHover : SepiaTheme.cardBgFemale
        case .unknown: isHovering ? SepiaTheme.cardBgHover : SepiaTheme.cardBg
        }
    }

    private var cardBorder: Color {
        if isHighlighted { return SepiaTheme.accent2 }
        switch person.sex {
        case .male: return isHovering ? SepiaTheme.cardLineMaleStrong : SepiaTheme.cardLineMale
        case .female: return isHovering ? SepiaTheme.cardLineFemaleStrong : SepiaTheme.cardLineFemale
        case .unknown: return isHovering ? SepiaTheme.cardLineStrong : SepiaTheme.cardLine
        }
    }

    private var shadowRadius: CGFloat {
        if isChosen { return s(5) }
        return isHovering ? s(5) : s(2)
    }

    /// Non-color sex cue so sex reads independent of the card tint (color-blind / low contrast).
    private var sexGlyph: String? {
        switch person.sex {
        case .male: "♂"
        case .female: "♀"
        case .unknown: nil
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            if showPhoto {
                Group {
                    if let data = person.photoData, let nsImage = NSImage(data: data) {
                        Image(nsImage: nsImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: s(66), height: s(88)) // 3:4 portrait, matches the inspector
                            .clipped()
                    } else {
                        ZStack {
                            Rectangle().fill(SepiaTheme.cardLine.opacity(0.2))
                            Image(systemName: "person.fill")
                                .font(.system(size: s(20)))
                                .foregroundColor(SepiaTheme.inkSoft.opacity(0.4))
                        }
                        .frame(width: s(66), height: s(88))
                    }
                }
                .transition(.opacity)
            }

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Surname — allow up to 2 lines so long names are never truncated.
                        // The maiden name sits on its own line below (1-line, clipped if needed).
                        Text(person.displaySurname.uppercased())
                            .font(SepiaTheme.ui(size: s(8)))
                            .tracking(s(1.0))
                            .foregroundColor(SepiaTheme.inkSoft)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        if let maiden = person.maidenName, !maiden.isEmpty, !person.surname.isEmpty {
                            Text("(\(maiden.uppercased()))")
                                .font(SepiaTheme.ui(size: s(7)))
                                .tracking(s(0.6))
                                .foregroundColor(SepiaTheme.inkSoft.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: s(4))
                    if let glyph = sexGlyph {
                        Text(glyph)
                            .font(SepiaTheme.ui(size: s(9)))
                            .foregroundColor(SepiaTheme.inkSoft)
                            .padding(.trailing, isHome ? s(3) : 0)
                    }
                    if isHome {
                        Circle().fill(SepiaTheme.accent).frame(width: s(6), height: s(6))
                    }
                }
                .padding(.horizontal, s(10))
                .padding(.top, s(6))
                .padding(.bottom, s(2))

                Rectangle().fill(SepiaTheme.cardRule).frame(height: max(0.5, s(1)))

                VStack(alignment: .leading, spacing: s(1)) {
                    let nameDisplay = [person.givenNames, person.patronymic ?? ""]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    Text(nameDisplay.isEmpty ? L10n.tr("Неизвестно") : nameDisplay)
                        .font(SepiaTheme.display(size: s(13.5)))
                        .fontWeight(.semibold)
                        .foregroundColor(SepiaTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if !person.lifespan.isEmpty {
                        Text(person.lifespan)
                            .font(SepiaTheme.body(size: s(10.5)))
                            .foregroundColor(SepiaTheme.inkSoft)
                    }
                }
                .padding(.horizontal, s(10))
                .padding(.top, s(4))
                .padding(.bottom, s(6))
            }
        }
        .frame(width: s(210), height: s(90))
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: s(4))
                .strokeBorder(cardBorder, lineWidth: isHighlighted ? s(1.5) : s(1))
        )
        // The selection ring is its own layer rather than a thicker border: SwiftUI does
        // not interpolate `strokeBorder` line width, but it does interpolate opacity and
        // scale — so the ring settles onto the card instead of snapping to 3pt.
        .overlay(
            RoundedRectangle(cornerRadius: s(4))
                .strokeBorder(SepiaTheme.accent, lineWidth: s(3))
                .opacity(isChosen ? 1 : 0)
                .scaleEffect(isChosen ? 1 : 1.06)
        )
        .clipShape(RoundedRectangle(cornerRadius: s(4)))
        .shadow(
            color: isChosen ? SepiaTheme.accent.opacity(0.3) : .black.opacity(isHovering ? 0.14 : 0.06),
            radius: shadowRadius,
            y: isHovering || isChosen ? s(2.5) : s(1)
        )
        .overlay(alignment: .topTrailing) {
            if let label = lineageLabel {
                Text(label)
                    .font(SepiaTheme.ui(size: s(9)))
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, s(5))
                    .padding(.vertical, s(2))
                    .background(SepiaTheme.accent)
                    .clipShape(RoundedRectangle(cornerRadius: s(3)))
                    .shadow(color: .black.opacity(0.18), radius: s(1.5), y: s(0.5))
                    // Float just above the card's top-right edge so it never collides with
                    // the sex glyph / home dot inside the header.
                    .offset(x: 0, y: -s(15))
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .scaleEffect(isHovering ? 1.012 : 1.0)
        .onHover { hovering in
            isHovering = hovering
            // The cards are the canvas's primary affordance and had no cursor cue at all.
            // `.set()` rather than push/pop for the same reason as the inspector's resize
            // handle: a card can be removed mid-hover (a delete, a layout morph), and a
            // missed hover-exit would then leak a cursor onto the stack forever.
            if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
        }
        .sepiaMotion(SepiaMotion.hover, value: isHovering)
        .sepiaMotion(SepiaMotion.select, value: [isSelected, isSecondarySelected, isHighlighted])
        .sepiaMotion(SepiaMotion.state, value: lineageLabel)
    }
}
