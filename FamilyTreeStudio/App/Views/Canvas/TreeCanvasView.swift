import AppKit
import FamilyTreeCore
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
    /// The tree is laid out and rasterized at this fixed multiple of its base size,
    /// then shown via a single `.scaleEffect(zoom / superSample)` transform. Zooming
    /// is therefore one cheap GPU transform (smooth, everything moves in lockstep —
    /// no per-frame relayout, no jitter), while the 2× bitmap keeps text crisp: the
    /// max zoom (2.0) lands at exactly 1:1, and every lower zoom is downsampled.
    private let superSample: CGFloat = 2
    private let zoomSensitivity: CGFloat = 0.5 // <1 makes pinch-zoom softer (0 = no zoom, 1 = 1:1 with fingers)
    private let wheelZoomSensitivity: CGFloat = 0.05 // mouse-wheel zoom step per scroll unit (soft)

    @State private var panOffset: CGSize = .zero
    @State private var dragStart: CGSize = .zero
    @State private var magnifyStart: CGFloat = 1.0
    @State private var panAtMagnifyStart: CGSize = .zero
    @State private var isMagnifying = false
    // Inertia / momentum scrolling
    @State private var velocity: CGSize = .zero
    @State private var lastDragValue: CGSize = .zero
    @State private var inertiaTimer: Timer?
    /// Layout only depends on tree structure + direction, so cache it and recompute
    /// only when those change — body re-runs on every pan/zoom frame otherwise.
    @State private var cachedLayout: TreeLayout?
    /// Bumped whenever `cachedLayout` is reassigned. Used as the cheap equality key for
    /// the isolated content/minimap layers, so they refresh exactly when the layout
    /// actually changes (not on every pan frame), and never miss a structural update.
    @State private var layoutGeneration = 0

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

                // Tree content — isolated in an Equatable layer so that pan/zoom (which
                // change panOffset/zoom every frame) only re-apply the .scaleEffect/.offset
                // transform on a cached layer tree, instead of re-running the whole card
                // ForEach each frame. The content re-renders only when selection/layout
                // actually change. This is what keeps panning and zooming smooth.
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
                // actually off-screen content worth an overview.
                if !layout.nodes.isEmpty,
                   layout.totalWidth * zoom > geo.size.width || layout.totalHeight * zoom > geo.size.height {
                    TreeMinimap(
                        layout: layout, generation: layoutGeneration, zoom: zoom, panOffset: panOffset, viewSize: geo.size,
                        selectedId: selectedPerson?.id, cardW: cardW, cardH: cardH,
                        onRecenter: { treePoint in recenter(onTreePoint: treePoint, viewSize: geo.size) }
                    )
                    .padding(12)
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: layout.totalWidth * zoom > geo.size.width || layout.totalHeight * zoom > geo.size.height)
            .background(
                // Mouse-wheel / scroll zoom, soft and anchored to the cursor.
                ScrollWheelZoom { deltaY, location in
                    var factor = 1 + deltaY * wheelZoomSensitivity
                    factor = min(1.25, max(0.8, factor))
                    let newZoom = min(2.0, max(0.2, zoom * factor))
                    guard newZoom != zoom else { return }
                    let ratio = newZoom / zoom
                    let newPan = CGSize(
                        width: location.x - (location.x - panOffset.width) * ratio,
                        height: location.y - (location.y - panOffset.height) * ratio
                    )
                    withAnimation(.interactiveSpring(response: 0.22, dampingFraction: 0.82)) {
                        zoom = newZoom
                        panOffset = newPan
                    }
                    dragStart = newPan
                }
            )
            .gesture(
                DragGesture()
                    .onChanged { value in
                        inertiaTimer?.invalidate()
                        let newOffset = CGSize(
                            width: dragStart.width + value.translation.width,
                            height: dragStart.height + value.translation.height
                        )
                        velocity = CGSize(
                            width: newOffset.width - panOffset.width,
                            height: newOffset.height - panOffset.height
                        )
                        panOffset = newOffset
                        lastDragValue = value.translation
                    }
                    .onEnded { _ in
                        dragStart = panOffset
                        startInertia()
                    }
            )
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        // Capture the zoom/pan baseline once at the start of the
                        // gesture. (value.magnification is cumulative from the
                        // gesture's start, so the baseline must NOT move mid-pinch
                        // — otherwise the zoom compounds and feels hypersensitive.)
                        if !isMagnifying {
                            isMagnifying = true
                            magnifyStart = zoom
                            panAtMagnifyStart = panOffset
                        }
                        // Soften the response for a gentle, map-like feel.
                        let damped = 1 + (value.magnification - 1) * zoomSensitivity
                        let newZoom = min(2.0, max(0.2, magnifyStart * damped))
                        // Zoom about the viewport centre so the content doesn't
                        // lurch toward a corner (the scaleEffect anchor is topLeading).
                        let ratio = newZoom / magnifyStart
                        let cx = geo.size.width / 2
                        let cy = geo.size.height / 2
                        panOffset = CGSize(
                            width: cx - (cx - panAtMagnifyStart.width) * ratio,
                            height: cy - (cy - panAtMagnifyStart.height) * ratio
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
                if cachedLayout == nil { cachedLayout = makeLayout() }
                fitToScreen(viewSize: geo.size, treeWidth: layout.totalWidth, treeHeight: layout.totalHeight)
            }
            .onChange(of: tree.layoutVersion) { _, _ in
                let l = makeLayout()
                cachedLayout = l
                layoutGeneration += 1
                fitToScreen(viewSize: geo.size, treeWidth: l.totalWidth, treeHeight: l.totalHeight)
            }
            .onChange(of: direction) { _, _ in
                let l = makeLayout()
                cachedLayout = l
                layoutGeneration += 1
                fitToScreen(viewSize: geo.size, treeWidth: l.totalWidth, treeHeight: l.totalHeight)
            }
            .onChange(of: fitRequest) { _, _ in
                fitToScreen(viewSize: geo.size, treeWidth: layout.totalWidth, treeHeight: layout.totalHeight)
            }
            .onChange(of: selectedPerson?.id) { _, newValue in
                // Selecting a person (canvas tap, search, or inspector link) glides the
                // canvas to center them, keeping the current zoom.
                if newValue != nil { centerOnSelected(viewSize: geo.size, layout: layout) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomInRequested)) { _ in
                applyZoomStep(delta: 0.1, viewSize: geo.size)
            }
            .onReceive(NotificationCenter.default.publisher(for: .zoomOutRequested)) { _ in
                applyZoomStep(delta: -0.1, viewSize: geo.size)
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

    /// Pan (keeping the current zoom) so the selected person's card is centered. Runs on
    /// every primary selection — canvas tap, search result, or inspector relative link.
    private func centerOnSelected(viewSize: CGSize, layout: TreeLayout) {
        guard let id = selectedPerson?.id,
              let n = layout.nodes.first(where: { $0.person.id == id }) else { return }
        recenter(onTreePoint: CGPoint(x: n.x + cardW / 2, y: n.y + cardH / 2), viewSize: viewSize)
    }

    /// Pan so a given point in tree coordinates sits at the viewport center.
    /// (screen = treePoint·zoom + panOffset, so panOffset = center − treePoint·zoom.)
    private func recenter(onTreePoint p: CGPoint, viewSize: CGSize) {
        withAnimation(.easeInOut(duration: 0.25)) {
            panOffset = CGSize(width: viewSize.width / 2 - p.x * zoom, height: viewSize.height / 2 - p.y * zoom)
            dragStart = panOffset
        }
    }

    // MARK: - Inertia (momentum scrolling)

    /// Zoom by `delta` anchored to the viewport centre (same math as scroll-wheel zoom).
    private func applyZoomStep(delta: CGFloat, viewSize: CGSize) {
        let newZoom = min(2.0, max(0.2, zoom + delta))
        guard newZoom != zoom else { return }
        let ratio = newZoom / zoom
        let cx = viewSize.width / 2
        let cy = viewSize.height / 2
        let newPan = CGSize(
            width: cx - (cx - panOffset.width) * ratio,
            height: cy - (cy - panOffset.height) * ratio
        )
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.8)) {
            zoom = newZoom
            panOffset = newPan
        }
        dragStart = newPan
    }

    private func startInertia() {
        inertiaTimer?.invalidate()
        let decay: CGFloat = 0.88 // fraction of velocity kept per frame (higher = slower decay)
        let cutoff: CGFloat = 0.5 // stop when velocity drops below this px/frame
        var v = velocity
        inertiaTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { t in
            v = CGSize(width: v.width * decay, height: v.height * decay)
            if abs(v.width) < cutoff && abs(v.height) < cutoff { t.invalidate(); return }
            panOffset = CGSize(width: panOffset.width + v.width, height: panOffset.height + v.height)
            dragStart = panOffset
        }
    }

    /// Build the tidy-tree layout via the pure engine in FamilyTreeCore.
    private func makeLayout() -> TreeLayout {
        TreeLayoutEngine().layout(tree: tree, direction: direction == .leftRight ? .leftRight : .topDown)
    }
}

/// The connectors + person cards, built at superSample scale. Equatable on its value
/// inputs (layout version, selection, highlight, flags) so SwiftUI skips re-evaluating
/// the whole card ForEach during pan/zoom — only the parent's transform updates then.
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
    let onSelect: (Person, Bool) -> Void

    static func == (l: TreeContentLayer, r: TreeContentLayer) -> Bool {
        // generation stands in for the (expensive to compare) layout; it bumps whenever
        // the cached layout is rebuilt, so structural changes always refresh.
        l.generation == r.generation &&
            l.selectedId == r.selectedId &&
            l.secondaryId == r.secondaryId &&
            l.homeId == r.homeId &&
            l.showPhotos == r.showPhotos &&
            l.superSample == r.superSample &&
            l.highlightedIds == r.highlightedIds &&
            l.lineageLabels == r.lineageLabels
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Connectors — drawn at the supersample scale (matching the cards).
            Canvas { ctx, _ in
                ctx.scaleBy(x: superSample, y: superSample)
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
            .frame(width: layout.totalWidth * superSample, height: layout.totalHeight * superSample)
            // Decorative only — let clicks on empty space pass through to the
            // background's tap-to-deselect instead of being swallowed here.
            .allowsHitTesting(false)
            .accessibilityHidden(true)

            // Cards
            ForEach(layout.nodes, id: \.person.id) { node in
                let dimmed = !highlightedIds.isEmpty && !highlightedIds.contains(node.person.id)
                let isPrimary = selectedId == node.person.id
                let isSecondary = secondaryId == node.person.id
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
                .opacity(dimmed ? 0.3 : 1.0)
                .position(x: (node.x + cardW / 2) * superSample, y: (node.y + cardH / 2) * superSample)
                .onTapGesture {
                    onSelect(node.person, NSEvent.modifierFlags.contains(.command))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(node.person.accessibilityDescription)
                .accessibilityHint("Выбрать персону")
                .accessibilityAddTraits((isPrimary || isSecondary) ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { onSelect(node.person, false) }
            }
        }
        .frame(width: layout.totalWidth * superSample, height: layout.totalHeight * superSample, alignment: .topLeading)
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
        let vx = (-panOffset.width / zoom) * m, vy = (-panOffset.height / zoom) * m
        let vw = (viewSize.width / zoom) * m, vh = (viewSize.height / zoom) * m

        ZStack(alignment: .topLeading) {
            // Static card map — Equatable, so panning the main canvas doesn't redraw it.
            MinimapNodes(layout: layout, generation: generation, selectedId: selectedId, m: m, cardW: cardW, cardH: cardH)
                .equatable()
                .frame(width: mapW, height: mapH)

            // Viewport indicator — a cheap moving layer (no per-frame node redraw).
            Rectangle()
                .fill(SepiaTheme.accent.opacity(0.08))
                .overlay(Rectangle().strokeBorder(SepiaTheme.accent, lineWidth: 1.5))
                .frame(width: vw, height: vh)
                .offset(x: vx, y: vy)
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
        .padding(6)
        .background(SepiaTheme.paper.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(SepiaTheme.cardLine, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .help("Обзор дерева — нажмите, чтобы перейти")
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
    var isSelected: Bool = false
    var isSecondarySelected: Bool = false
    var isHome: Bool = false
    var isHighlighted: Bool = false
    var lineageLabel: String?
    var showPhoto: Bool = false
    /// Zoom factor. The card renders at its real scaled size (fonts included) so the
    /// text stays crisp at any zoom, instead of being a 1× bitmap stretched by the canvas.
    var scale: CGFloat = 1

    static func == (lhs: PersonCardView, rhs: PersonCardView) -> Bool {
        lhs.person.id == rhs.person.id &&
            lhs.person.givenNames == rhs.person.givenNames &&
            lhs.person.surname == rhs.person.surname &&
            lhs.person.maidenName == rhs.person.maidenName &&
            lhs.person.lifespan == rhs.person.lifespan &&
            lhs.person.sex == rhs.person.sex &&
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

    private var cardBackground: Color {
        switch person.sex {
        case .male: SepiaTheme.cardBgMale
        case .female: SepiaTheme.cardBgFemale
        case .unknown: SepiaTheme.cardBg
        }
    }

    private var cardBorder: Color {
        switch person.sex {
        case .male: SepiaTheme.cardLineMale
        case .female: SepiaTheme.cardLineFemale
        case .unknown: SepiaTheme.cardLine
        }
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
                    Text(nameDisplay.isEmpty ? "Неизвестно" : nameDisplay)
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
        .background(isHighlighted ? SepiaTheme.accent.opacity(0.08) : cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: s(4))
                .strokeBorder(
                    isSelected ? SepiaTheme.accent :
                        isSecondarySelected ? SepiaTheme.accent :
                        (isHighlighted ? SepiaTheme.accent2 : cardBorder),
                    lineWidth: (isSelected || isSecondarySelected) ? s(3) : (isHighlighted ? s(1.5) : s(1))
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: s(4)))
        .shadow(color: (isSelected || isSecondarySelected) ? SepiaTheme.accent.opacity(0.3) : .black.opacity(0.06), radius: (isSelected || isSecondarySelected) ? s(4) : s(2), y: s(1))
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
            }
        }
    }
}
