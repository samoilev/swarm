import SwiftUI
import FamilyTreeCore
import AppKit

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
    // Layout only depends on tree structure + direction, so cache it and recompute
    // only when those change — body re-runs on every pan/zoom frame otherwise.
    @State private var cachedLayout: TreeLayout?

    var body: some View {
        GeometryReader { geo in
            let layout = cachedLayout ?? makeLayout()

            ZStack(alignment: .topLeading) {
                // Dot grid background (Miro-style) — fills the viewport, tap to deselect
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
                .frame(width: geo.size.width, height: geo.size.height)
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedPerson = nil
                    secondaryPerson = nil
                }

                // Tree content — may be larger than the viewport; the outer
                // frame+clip below keeps it from overflowing onto the toolbar
                // (which would otherwise swallow toolbar button clicks).
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
                .frame(width: layout.totalWidth, height: layout.totalHeight, alignment: .topLeading)
                .scaleEffect(zoom, anchor: .topLeading)
                .offset(x: panOffset.width, y: panOffset.height)
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .contentShape(Rectangle())
            .clipped()
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
                fitToScreen(viewSize: geo.size, treeWidth: l.totalWidth, treeHeight: l.totalHeight)
            }
            .onChange(of: direction) { _, _ in
                let l = makeLayout()
                cachedLayout = l
                fitToScreen(viewSize: geo.size, treeWidth: l.totalWidth, treeHeight: l.totalHeight)
            }
            .onChange(of: fitRequest) { _, _ in
                fitToScreen(viewSize: geo.size, treeWidth: layout.totalWidth, treeHeight: layout.totalHeight)
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
        let decay: CGFloat = 0.88       // fraction of velocity kept per frame (higher = slower decay)
        let cutoff: CGFloat = 0.5       // stop when velocity drops below this px/frame
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

        override var isFlipped: Bool { true } // top-left origin to match SwiftUI
        override func hitTest(_ point: NSPoint) -> NSView? { nil } // pass clicks through

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
                        .frame(width: 66, height: 88) // 3:4 portrait, matches the inspector
                        .clipped()
                } else {
                    ZStack {
                        Rectangle().fill(SepiaTheme.cardLine.opacity(0.2))
                        Image(systemName: "person.fill")
                            .font(.system(size: 20))
                            .foregroundColor(SepiaTheme.inkSoft.opacity(0.4))
                    }
                    .frame(width: 66, height: 88)
                }
            }
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        // Surname — allow up to 2 lines so long names are never truncated.
                        // The maiden name sits on its own line below (1-line, clipped if needed).
                        Text(person.displaySurname.uppercased())
                            .font(SepiaTheme.ui(size: 8))
                            .tracking(1.0)
                            .foregroundColor(SepiaTheme.inkSoft)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        if let maiden = person.maidenName, !maiden.isEmpty, !person.surname.isEmpty {
                            Text("(\(maiden.uppercased()))")
                                .font(SepiaTheme.ui(size: 7))
                                .tracking(0.6)
                                .foregroundColor(SepiaTheme.inkSoft.opacity(0.7))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                    Spacer(minLength: 4)
                    if isHome {
                        Circle().fill(SepiaTheme.accent).frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 2)
                
                Divider().overlay(SepiaTheme.cardRule)
                
                VStack(alignment: .leading, spacing: 1) {
                    let nameDisplay = [person.givenNames, person.patronymic ?? ""]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    Text(nameDisplay.isEmpty ? "Неизвестно" : nameDisplay)
                        .font(SepiaTheme.display(size: 13.5))
                        .fontWeight(.semibold)
                        .foregroundColor(SepiaTheme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if !person.lifespan.isEmpty {
                        Text(person.lifespan)
                            .font(SepiaTheme.body(size: 10.5))
                            .foregroundColor(SepiaTheme.inkSoft)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 6)
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
