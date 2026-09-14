import AppKit
import SwarmCore
import SwiftUI

/// Network-free map surface. It deliberately has no MapKit dependency and renders a
/// compact bundled world outline plus the tree's stored coordinates with SwiftUI Canvas.
///
/// All projection and camera math lives in `OfflineMapProjection` so it can be tested
/// without driving the UI.
struct OfflineVectorMapView: View {
    let tree: FamilyTree
    @Binding var zoom: CGFloat
    @Binding var selectedPerson: Person?
    @Binding var fitRequest: Int
    let focus: MapFocus
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let zoomSensitivity: CGFloat = 0.3 // <1 makes pinch-zoom softer (0 = no zoom, 1 = 1:1 with fingers)

    @State private var annotations: [OfflineMapAnnotation] = []
    @State private var routes: [OfflineMapRoute] = []
    @State private var center = CGPoint(x: 0.61, y: 0.31)
    @State private var mapScale: CGFloat = 2.4
    @State private var scaleAtGestureStart: CGFloat = 2.4
    @State private var expandedClusterID: String?
    @State private var placeIndexRevision = 0

    /// Parsed once on appear. Reading `OfflineMapVectorData.shared` from inside the
    /// `Canvas` closure took an `NSLock` on every frame of every pan.
    @State private var vectors: OfflineMapVectorData?
    /// Gazetteer labels for the current viewport, refreshed by `labelTask` rather than
    /// re-queried per frame. The per-frame query walked up to 27,000 rows in the dense
    /// buckets around Moscow, St Petersburg and Kyiv — copying a multi-string struct
    /// for each — which is what made panning stutter worst where the data is richest.
    @State private var labels: [PlaceEntry] = []
    /// `.global` frame, needed both for the label query and to place scroll events.
    @State private var mapFrame: CGRect = .zero
    @State private var centerAtDragStart: CGPoint?
    @State private var pointer: CGPoint?
    @State private var scrollMonitor: Any?
    /// Mirrors `AppleMapChartView.lastZoom`. Without it `fit()` corrupted its own
    /// result: it set `mapScale`, then assigned `zoom = 0.85`, and the `onChange`
    /// below re-scaled by the ratio of that assignment.
    @State private var lastZoom: CGFloat = 0.85

    private var viewSize: CGSize { mapFrame.size }

    private var labelTier: PlaceLabelTier {
        if mapScale <= 1.4 {
            .world
        } else if mapScale <= 4 {
            .regional
        } else if mapScale <= 12 {
            .city
        } else {
            .close
        }
    }

    /// Quantised so a small pan does not re-run the query. The centre is rounded to
    /// eighths of the visible span, so the gazetteer is read roughly once per
    /// half-screen of movement instead of once per frame.
    private var labelKey: LabelKey {
        let quantum = max(0.000_01, 1 / Double(mapScale) / 8)
        return LabelKey(
            tier: labelTier,
            centerX: Int((Double(center.x) / quantum).rounded()),
            centerY: Int((Double(center.y) / quantum).rounded()),
            width: Int(viewSize.width),
            height: Int(viewSize.height),
            language: languageRaw,
            revision: placeIndexRevision
        )
    }

    struct LabelKey: Equatable {
        let tier: PlaceLabelTier
        let centerX: Int
        let centerY: Int
        let width: Int
        let height: Int
        let language: String
        let revision: Int
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    drawBackground(context: &context, size: size)
                    drawRoutes(context: &context, size: size)
                }
                .id("\(languageRaw)-\(placeIndexRevision)")
                .contentShape(Rectangle())
                .gesture(dragGesture(size: proxy.size))
                .simultaneousGesture(magnificationGesture(size: proxy.size))
                .simultaneousGesture(doubleTapGesture(size: proxy.size))

                ForEach(clusters(in: proxy.size)) { cluster in
                    clusterButton(cluster)
                        .position(cluster.point)
                }

                if annotations.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.slash")
                            .font(SepiaTheme.icon(size: 28))
                        Text(L10n.tr("Нет мест с координатами"))
                            .font(SepiaTheme.body(size: 14))
                        Text(L10n.tr("Выберите место из справочника или укажите координаты вручную"))
                            .font(SepiaType.label)
                    }
                    .foregroundColor(SepiaTheme.inkSoft)
                    .multilineTextAlignment(.center)
                }
            }
            .clipped()
            .background(SepiaTheme.mapSea)
            .animation(reduceMotion ? nil : SepiaMotion.select, value: focus)
            .onContinuousHover { phase in
                switch phase {
                case let .active(location): pointer = location
                case .ended: pointer = nil
                @unknown default: pointer = nil
                }
            }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { mapFrame = $0 }
            .overlay(alignment: .topLeading) {
                Label(L10n.tr("Офлайн"), systemImage: "network.slash")
                    .font(SepiaType.micro)
                    .foregroundColor(SepiaTheme.inkSoft)
                    .padding(7)
                    .background(SepiaTheme.paper.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(12)
            }
            .overlay(alignment: .bottomLeading) { legend }
            .overlay(alignment: .bottomTrailing) { scaleBar }
            .onAppear {
                if vectors == nil { vectors = OfflineMapVectorData.shared }
                installScrollMonitor()
                resolveAnnotations()
                fit(size: proxy.size)
                PlacesDatabase.shared.whenReady {
                    placeIndexRevision += 1
                    resolveAnnotations()
                    fit(size: proxy.size)
                }
            }
            .onDisappear {
                if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
                scrollMonitor = nil
            }
            .task(id: labelKey) { await refreshLabels() }
            .onChange(of: tree.layoutVersion) { _, _ in
                resolveAnnotations()
                fit(size: proxy.size)
            }
            .onChange(of: languageRaw) { _, _ in resolveAnnotations() }
            .onChange(of: fitRequest) { _, _ in fit(size: proxy.size) }
            .onChange(of: zoom) { _, newValue in
                guard abs(newValue - lastZoom) > 0.001, lastZoom > 0 else { return }
                let factor = newValue / lastZoom
                lastZoom = newValue
                zoomBy(
                    factor: factor,
                    anchor: CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2),
                    size: proxy.size
                )
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tr("Офлайн-карта мест семьи"))
        .accessibilityRepresentation {
            VStack {
                Text(L10n.tr("Места семьи"))
                // The overlays sit inside the subtree this representation replaces, so
                // without this line the distance reading exists only for sighted users.
                if let bar = currentScaleBar {
                    Text(L10n.tr("Масштаб: \(scaleLabel(bar.kilometres))"))
                }
                ForEach(annotations) { annotation in
                    Button("\(annotation.personName): \(annotation.placeName), \(annotation.kind.label)") {
                        selectedPerson = tree.person(byId: annotation.personID)
                    }
                }
            }
        }
    }

    // MARK: - Labels

    private func refreshLabels() async {
        let size = viewSize
        guard size.width > 0, size.height > 0, PlacesDatabase.shared.isReady else { return }
        let tier = labelTier
        let bounds = OfflineMapProjection.visibleBounds(center: center, scale: mapScale, size: size)
        let language = AppLanguage(rawValue: languageRaw) ?? .default
        let result = await Task.detached(priority: .userInitiated) {
            PlacesDatabase.shared.mapLabels(tier: tier, bounds: bounds, language: language)
        }.value
        guard !Task.isCancelled else { return }
        labels = result
    }

    // MARK: - Pins

    private func clusterButton(_ cluster: OfflineMapCluster) -> some View {
        let presented = Binding(
            get: { expandedClusterID == cluster.id },
            set: { if !$0 { expandedClusterID = nil } }
        )
        return Button {
            if cluster.annotations.count == 1 {
                selectedPerson = tree.person(byId: cluster.annotations[0].personID)
            } else {
                expandedClusterID = cluster.id
            }
        } label: {
            ZStack {
                Circle()
                    .fill(cluster.color)
                    .frame(width: cluster.annotations.count > 1 ? 24 : 16, height: cluster.annotations.count > 1 ? 24 : 16)
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
                if cluster.annotations.count > 1 {
                    Text("\(cluster.annotations.count)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                }
            }
            .opacity(focus.emphasis(forAny: cluster.annotations.map(\.personID)).pinOpacity)
            .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(cluster.accessibilityLabel)
        .popover(isPresented: presented) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(cluster.annotations) { annotation in
                    Button {
                        selectedPerson = tree.person(byId: annotation.personID)
                        expandedClusterID = nil
                    } label: {
                        HStack(spacing: 7) {
                            Circle().fill(annotation.kind.color).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(annotation.personName).font(SepiaTheme.body(size: 12))
                                Text(annotation.placeName).font(SepiaTheme.ui(size: 9)).foregroundColor(SepiaTheme.inkSoft)
                            }
                        }
                        .opacity(focus.emphasis(for: annotation.personID).pinOpacity)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }

    // MARK: - Drawing

    private func drawBackground(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SepiaTheme.mapSea))
        drawGraticule(context: &context, size: size)

        guard let vectors else { return }
        let bounds = OfflineMapProjection.visibleBounds(center: center, scale: mapScale, size: size)
        for ring in vectors.land(intersecting: bounds) {
            guard let path = path(for: ring, size: size, closed: true) else { continue }
            context.fill(path, with: .color(SepiaTheme.mapLand))
            context.stroke(path, with: .color(SepiaTheme.inkSoft.opacity(0.45)), lineWidth: 0.8)
        }
        for ring in vectors.borders(intersecting: bounds) {
            guard let path = path(for: ring, size: size, closed: false) else { continue }
            context.stroke(path, with: .color(SepiaTheme.inkSoft.opacity(0.28)), lineWidth: 0.45)
        }

        drawPlaceLabels(context: &context, size: size)
    }

    private func path(for ring: MapVectorRing, size: CGSize, closed: Bool) -> Path? {
        guard let first = ring.points.first else { return nil }
        var path = Path()
        path.move(to: project(coordinate(first), size: size))
        for point in ring.points.dropFirst() {
            path.addLine(to: project(coordinate(point), size: size))
        }
        if closed { path.closeSubpath() }
        return path
    }

    /// Meridians and parallels are both straight lines in Mercator, so each needs two
    /// points rather than the stepped polyline this used to build. Spacing follows the
    /// zoom: the old fixed 30°/15° grid drew nothing once the viewport was narrower
    /// than one cell.
    private func drawGraticule(context: inout GraphicsContext, size: CGSize) {
        let step = OfflineMapProjection.graticuleStep(for: mapScale)
        let color = SepiaTheme.line.opacity(0.18)
        let limit = OfflineMapProjection.latitudeLimit

        for index in 0 ... Int(360 / step) {
            let longitude = -180 + Double(index) * step
            let x = project(MapCoordinate(latitude: 0, longitude: longitude), size: size).x
            guard x >= 0, x <= size.width else { continue }
            var path = Path()
            path.move(to: project(MapCoordinate(latitude: limit, longitude: longitude), size: size))
            path.addLine(to: project(MapCoordinate(latitude: -limit, longitude: longitude), size: size))
            context.stroke(path, with: .color(color), lineWidth: 0.5)
        }
        for index in 0 ... Int(160 / step) {
            let latitude = -80 + Double(index) * step
            let y = project(MapCoordinate(latitude: latitude, longitude: 0), size: size).y
            guard y >= 0, y <= size.height else { continue }
            var path = Path()
            path.move(to: project(MapCoordinate(latitude: latitude, longitude: -180), size: size))
            path.addLine(to: project(MapCoordinate(latitude: latitude, longitude: 180), size: size))
            context.stroke(path, with: .color(color), lineWidth: 0.5)
        }
    }

    private func drawPlaceLabels(context: inout GraphicsContext, size: CGSize) {
        var occupied: [CGRect] = []

        // The tree's own places are laid out first and win every collision. They used
        // to carry no name at all — gazetteer cities were labelled while the family's
        // own villages were bare dots, which is backwards for this map.
        if mapScale >= 3 {
            for cluster in clusters(in: size) where cluster.annotations.count == 1 {
                guard let annotation = cluster.annotations.first,
                      focus.emphasis(for: annotation.personID) != .dimmed,
                      !annotation.placeName.isEmpty else { continue }
                let resolved = context.resolve(
                    Text(annotation.placeName)
                        .font(SepiaTheme.ui(size: 10, scaled: false))
                        .foregroundColor(SepiaTheme.ink)
                )
                let measured = resolved.measure(in: size)
                let rect = CGRect(
                    x: cluster.point.x + 13,
                    y: cluster.point.y - measured.height / 2,
                    width: measured.width,
                    height: measured.height
                )
                guard !occupied.contains(where: { $0.insetBy(dx: -3, dy: -2).intersects(rect) }) else { continue }
                // The pin is a button drawn above the canvas; reserve its circle so a
                // gazetteer name cannot land under it.
                occupied.append(CGRect(x: cluster.point.x - 12, y: cluster.point.y - 12, width: 24, height: 24))
                occupied.append(rect)
                context.draw(resolved, in: rect)
            }
        }

        guard PlacesDatabase.shared.isReady else { return }
        let tier = labelTier
        let language = AppLanguage(rawValue: languageRaw) ?? .default
        var drawn = 0
        for place in labels {
            guard let latitude = place.latitude, let longitude = place.longitude else { continue }
            let point = project(MapCoordinate(latitude: latitude, longitude: longitude), size: size)
            guard point.x >= 0, point.x <= size.width, point.y >= 0, point.y <= size.height else { continue }
            let resolved = context.resolve(
                Text(place.name(language: language))
                    .font(SepiaTheme.ui(size: tier == .close ? 10 : 9, scaled: false))
                    .foregroundColor(SepiaTheme.inkSoft.opacity(0.86))
            )
            // Measured, not guessed: the collision box used to be `name.count * 6.2`.
            let measured = resolved.measure(in: size)
            // Offset from the dot. Labels used to be centred on the place they named,
            // hiding the very point they marked.
            let rect = CGRect(
                x: point.x + 5,
                y: point.y - measured.height / 2,
                width: measured.width,
                height: measured.height
            )
            guard !occupied.contains(where: { $0.insetBy(dx: -3, dy: -2).intersects(rect) }) else { continue }
            context.fill(
                Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)),
                with: .color(SepiaTheme.inkSoft.opacity(0.7))
            )
            context.draw(resolved, in: rect)
            occupied.append(rect)
            drawn += 1
            if drawn >= tier.maximumLabels { break }
        }
    }

    private func drawRoutes(context: inout GraphicsContext, size: CGSize) {
        for route in routes {
            var path = Path()
            path.move(to: project(route.start, size: size))
            path.addLine(to: project(route.end, size: size))
            let emphasis = focus.emphasis(for: route.personID)
            let base = route.isBurial ? SepiaTheme.pinBurial.opacity(0.7) : SepiaTheme.mapLine
            let bump: CGFloat = emphasis == .focused ? 1 : 0
            context.stroke(
                path,
                with: .color(base.opacity(emphasis.lineOpacity)),
                style: StrokeStyle(
                    lineWidth: (route.isBurial ? 2.5 : 2) + bump,
                    dash: route.isBurial ? [1, 5] : [6, 4]
                )
            )
        }
    }

    // MARK: - Model

    private func coordinate(_ point: MapVectorPoint) -> MapCoordinate {
        MapCoordinate(latitude: point.latitude, longitude: point.longitude)
    }

    private func clusters(in size: CGSize) -> [OfflineMapCluster] {
        var grouped: [String: [OfflineMapAnnotation]] = [:]
        for annotation in annotations {
            let point = project(annotation.coordinate, size: size)
            guard point.x >= -30, point.x <= size.width + 30, point.y >= -30, point.y <= size.height + 30 else { continue }
            let key = "\(Int(point.x / 36)),\(Int(point.y / 36))"
            grouped[key, default: []].append(annotation)
        }
        return grouped.map { key, values in
            let points = values.map { project($0.coordinate, size: size) }
            let point = CGPoint(
                x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
                y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
            )
            return OfflineMapCluster(id: key, point: point, annotations: values)
        }
    }

    private func resolveAnnotations() {
        var result: [OfflineMapAnnotation] = []
        var newRoutes: [OfflineMapRoute] = []
        for person in tree.people {
            let birth = coordinate(
                latitude: person.birthLat,
                longitude: person.birthLon,
                place: person.birthPlace
            )
            let death = coordinate(
                latitude: person.deathLat,
                longitude: person.deathLon,
                place: person.deathPlace
            )
            let burial = coordinate(
                latitude: person.burialLat,
                longitude: person.burialLon,
                place: person.burialPlace
            )
            if let birth {
                result.append(OfflineMapAnnotation(
                    personID: person.id,
                    personName: person.displayName(language: .current),
                    placeName: person.presentationPlace(kind: .birth, fallback: person.birthPlace),
                    kind: .birth,
                    coordinate: birth
                ))
            }
            if let death {
                result.append(OfflineMapAnnotation(
                    personID: person.id,
                    personName: person.displayName(language: .current),
                    placeName: person.presentationPlace(kind: .death, fallback: person.deathPlace),
                    kind: .death,
                    coordinate: death
                ))
            }
            if let burial {
                result.append(OfflineMapAnnotation(
                    personID: person.id,
                    personName: person.displayName(language: .current),
                    placeName: person.presentationPlace(kind: .burial, fallback: person.burialPlace),
                    kind: .burial,
                    coordinate: burial
                ))
            }
            if let birth, let death {
                newRoutes.append(OfflineMapRoute(personID: person.id, start: birth, end: death, isBurial: false))
            }
            if let death, let burial {
                newRoutes.append(OfflineMapRoute(personID: person.id, start: death, end: burial, isBurial: true))
            }
        }
        annotations = result
        routes = newRoutes
    }

    private func coordinate(latitude: Double?, longitude: Double?, place: String?) -> MapCoordinate? {
        if let latitude, let longitude, (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude) {
            return MapCoordinate(latitude: latitude, longitude: longitude)
        }
        if let coordinate = GeocodingService.shared.coordinateSync(for: place) {
            return MapCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        return nil
    }

    // MARK: - Camera

    private func fit(size: CGSize) {
        // With a branch selected, frame that branch rather than every place in the tree.
        let onBranch = focus.isActive ? annotations.filter { focus.emphasis(for: $0.personID) != .dimmed } : []
        let annotations = onBranch.isEmpty ? annotations : onBranch

        guard !annotations.isEmpty, size.width > 0, size.height > 0 else { return }
        let normalized = annotations.map { OfflineMapProjection.normalized($0.coordinate) }
        let minX = normalized.map(\.x).min()!, maxX = normalized.map(\.x).max()!
        let minY = normalized.map(\.y).min()!, maxY = normalized.map(\.y).max()!
        let width = max(maxX - minX, 0.025)
        let height = max(maxY - minY, 0.025)
        mapScale = min(32, max(0.9, min(0.78 / width, 0.78 * size.height / size.width / height)))
        scaleAtGestureStart = mapScale
        center = OfflineMapProjection.clampCenter(
            CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2),
            scale: mapScale,
            size: size
        )
        // Set before `zoom` so the `onChange` above sees no delta: it used to re-scale
        // by 0.85/previous and undo the fit that just ran.
        lastZoom = 0.85
        zoom = 0.85
    }

    private func project(_ coordinate: MapCoordinate, size: CGSize) -> CGPoint {
        OfflineMapProjection.project(coordinate, center: center, scale: mapScale, size: size)
    }

    private func zoomBy(factor: CGFloat, anchor: CGPoint, size: CGSize) {
        guard size.width > 0, factor > 0, factor.isFinite else { return }
        let newScale = min(
            OfflineMapProjection.maximumScale,
            max(OfflineMapProjection.minimumScale, mapScale * factor)
        )
        guard newScale != mapScale else { return }
        center = OfflineMapProjection.anchoredCenter(
            center: center,
            anchor: anchor,
            oldScale: mapScale,
            newScale: newScale,
            size: size
        )
        mapScale = newScale
        scaleAtGestureStart = newScale
    }

    // MARK: - Gestures

    /// Tracks the pointer while the button is down. This used to be `.onEnded` only,
    /// so the map stayed frozen through the whole drag and jumped on release.
    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard size.width > 0 else { return }
                let anchor: CGPoint
                if let centerAtDragStart {
                    anchor = centerAtDragStart
                } else {
                    anchor = center
                    centerAtDragStart = center
                }
                center = OfflineMapProjection.clampCenter(
                    CGPoint(
                        x: anchor.x - value.translation.width / (size.width * mapScale),
                        y: anchor.y - value.translation.height / (size.width * mapScale)
                    ),
                    scale: mapScale,
                    size: size
                )
            }
            .onEnded { _ in centerAtDragStart = nil }
    }

    private func magnificationGesture(size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                // Same damping as the tree canvas. Undamped magnification is worst here:
                // the scale range is 0.8–40, so a short pinch flew across it.
                let damped = 1 + (value - 1) * zoomSensitivity
                let target = min(
                    OfflineMapProjection.maximumScale,
                    max(OfflineMapProjection.minimumScale, scaleAtGestureStart * damped)
                )
                guard target != mapScale else { return }
                let anchor = pointer ?? CGPoint(x: size.width / 2, y: size.height / 2)
                center = OfflineMapProjection.anchoredCenter(
                    center: center,
                    anchor: anchor,
                    oldScale: mapScale,
                    newScale: target,
                    size: size
                )
                mapScale = target
            }
            .onEnded { _ in scaleAtGestureStart = mapScale }
    }

    private func doubleTapGesture(size: CGSize) -> some Gesture {
        SpatialTapGesture(count: 2)
            .modifiers(.option)
            .onEnded { value in zoomBy(factor: 1 / 2, anchor: value.location, size: size) }
            .exclusively(
                before: SpatialTapGesture(count: 2)
                    .onEnded { value in zoomBy(factor: 2, anchor: value.location, size: size) }
            )
    }

    /// Scroll-wheel zoom, anchored at the pointer.
    ///
    /// A local monitor rather than an `NSViewRepresentable`: AppKit delivers scroll
    /// events by hit-testing, and any view placed over the canvas to catch them would
    /// also swallow the clicks meant for the pins underneath.
    private func installScrollMonitor() {
        guard scrollMonitor == nil else { return }
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            guard let contentView = event.window?.contentView else { return event }
            // AppKit measures from the window's bottom-left; SwiftUI's global space is
            // top-left.
            let inWindow = event.locationInWindow
            let point = CGPoint(x: inWindow.x, y: contentView.bounds.height - inWindow.y)
            let frame = mapFrame
            guard frame.width > 0, frame.contains(point) else { return event }
            let delta = event.scrollingDeltaY
            guard delta != 0 else { return event }
            // A trackpad reports many small precise deltas; a wheel reports one notch.
            let factor: CGFloat = event.hasPreciseScrollingDeltas
                ? exp(delta * 0.01)
                : (delta > 0 ? 1.2 : 1 / 1.2)
            zoomBy(
                factor: factor,
                anchor: CGPoint(x: point.x - frame.minX, y: point.y - frame.minY),
                size: frame.size
            )
            return nil
        }
    }

    // MARK: - Chrome

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(L10n.tr("Рождение"), color: SepiaTheme.pinBirth)
            legendItem(L10n.tr("Смерть"), color: SepiaTheme.pinDeath)
            legendItem(L10n.tr("Захоронение"), color: SepiaTheme.pinBurial)
        }
        .padding(8)
        .background(SepiaTheme.paper.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(12)
    }

    private func legendItem(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(SepiaType.label).foregroundColor(SepiaTheme.inkSoft)
        }
    }

    /// Distance reference. Offline mode had none at all, so there was no way to tell a
    /// 10 km view from a 1000 km one. Apple mode gets `MapScaleView` for free.
    private var currentScaleBar: (kilometres: Double, width: CGFloat)? {
        guard viewSize.width > 0 else { return nil }
        return OfflineMapProjection.scaleBar(
            scale: mapScale,
            latitude: OfflineMapProjection.coordinate(atNormalized: center).latitude,
            size: viewSize,
            maximumWidth: 120
        )
    }

    @ViewBuilder private var scaleBar: some View {
        if let bar = currentScaleBar {
            VStack(alignment: .leading, spacing: 3) {
                Text(scaleLabel(bar.kilometres))
                    .font(SepiaType.micro)
                    .foregroundColor(SepiaTheme.inkSoft)
                Rectangle()
                    .fill(SepiaTheme.inkSoft.opacity(0.75))
                    .frame(width: max(1, bar.width), height: 3)
            }
            .padding(7)
            .background(SepiaTheme.paper.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.tr("Масштаб: \(scaleLabel(bar.kilometres))"))
        }
    }

    private func scaleLabel(_ kilometres: Double) -> String {
        kilometres >= 1
            ? L10n.tr("\(Int(kilometres.rounded())) км")
            : L10n.tr("\(Int((kilometres * 1000).rounded())) м")
    }
}

struct OfflinePersonMiniMap: View {
    let person: Person

    var body: some View {
        GeometryReader { proxy in
            let points = miniPoints
            ZStack {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(SepiaTheme.mapSea))
                    if points.count == 2 {
                        var path = Path()
                        path.move(to: miniProject(points[0].coordinate, points: points, size: size))
                        path.addLine(to: miniProject(points[1].coordinate, points: points, size: size))
                        context.stroke(path, with: .color(SepiaTheme.mapLine), style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                }
                ForEach(points) { point in
                    Circle()
                        .fill(point.kind.color)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .position(miniProject(point.coordinate, points: points, size: proxy.size))
                        .accessibilityLabel("\(point.kind.label): \(point.placeName)")
                }
                if points.isEmpty {
                    Text(L10n.tr("Место не отмечено"))
                        .font(SepiaTheme.body(size: 12))
                        .foregroundColor(SepiaTheme.inkSoft)
                }
            }
        }
        .frame(height: miniPoints.isEmpty ? 64 : 150)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
        .overlay(alignment: .topLeading) { legend }
    }

    /// Matches `ApplePersonMiniMap`'s legend so the card looks the same whichever map
    /// provider is selected. Two items, not the full map's three: the mini map plots
    /// birth and death only.
    @ViewBuilder private var legend: some View {
        let points = miniPoints
        if !points.isEmpty {
            HStack(spacing: 8) {
                if points.contains(where: { $0.kind == .birth }) {
                    HStack(spacing: 3) { Circle().fill(SepiaTheme.pinBirth).frame(width: 6, height: 6); Text(L10n.tr("Рожд.")) }
                }
                if points.contains(where: { $0.kind == .death }) {
                    HStack(spacing: 3) { Circle().fill(SepiaTheme.pinDeath).frame(width: 6, height: 6); Text(L10n.tr("Смерть")) }
                }
            }
            .font(SepiaTheme.ui(size: 9))
            .foregroundColor(SepiaTheme.inkSoft)
            .padding(5)
            .background(SepiaTheme.paper.opacity(0.9))
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .padding(6)
        }
    }

    private var miniPoints: [OfflineMapAnnotation] {
        var result: [OfflineMapAnnotation] = []
        if let coordinate = miniCoordinate(person.birthLat, person.birthLon, person.birthPlace) {
            result.append(OfflineMapAnnotation(
                personID: person.id,
                personName: person.displayName(language: .current),
                placeName: person.presentationPlace(kind: .birth, fallback: person.birthPlace),
                kind: .birth, coordinate: coordinate
            ))
        }
        if let coordinate = miniCoordinate(person.deathLat, person.deathLon, person.deathPlace) {
            result.append(OfflineMapAnnotation(
                personID: person.id,
                personName: person.displayName(language: .current),
                placeName: person.presentationPlace(kind: .death, fallback: person.deathPlace),
                kind: .death, coordinate: coordinate
            ))
        }
        return result
    }

    private func miniCoordinate(_ latitude: Double?, _ longitude: Double?, _ place: String?) -> MapCoordinate? {
        if let latitude, let longitude { return MapCoordinate(latitude: latitude, longitude: longitude) }
        if let coordinate = GeocodingService.shared.coordinateSync(for: place) {
            return MapCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        return nil
    }

    private func miniProject(_ coordinate: MapCoordinate, points: [OfflineMapAnnotation], size: CGSize) -> CGPoint {
        let longitudes = points.map(\.coordinate.longitude)
        let latitudes = points.map(\.coordinate.latitude)
        let minLon = longitudes.min() ?? coordinate.longitude
        let maxLon = longitudes.max() ?? coordinate.longitude
        let minLat = latitudes.min() ?? coordinate.latitude
        let maxLat = latitudes.max() ?? coordinate.latitude
        let lonRange = max(maxLon - minLon, 4)
        let latRange = max(maxLat - minLat, 4)
        return CGPoint(
            x: size.width * (0.15 + 0.7 * (coordinate.longitude - (minLon - (lonRange - (maxLon - minLon)) / 2)) / lonRange),
            y: size.height * (0.85 - 0.7 * (coordinate.latitude - (minLat - (latRange - (maxLat - minLat)) / 2)) / latRange)
        )
    }
}

private struct OfflineMapAnnotation: Identifiable {
    var id: String { "\(personID)-\(kind.rawValue)-\(coordinate.latitude)-\(coordinate.longitude)" }
    let personID: UUID
    let personName: String
    let placeName: String
    let kind: OfflineMapPinKind
    let coordinate: MapCoordinate
}

private struct OfflineMapRoute: Identifiable {
    let id = UUID()
    let personID: UUID
    let start: MapCoordinate
    let end: MapCoordinate
    let isBurial: Bool
}

private struct OfflineMapCluster: Identifiable {
    let id: String
    let point: CGPoint
    let annotations: [OfflineMapAnnotation]
    var color: Color { annotations.first?.kind.color ?? SepiaTheme.accent }
    var accessibilityLabel: String {
        if annotations.count == 1 { return "\(annotations[0].personName), \(annotations[0].kind.label)" }
        return L10n.tr("\(L10n.count(annotations.count, .event)) в одном месте")
    }
}

private enum OfflineMapPinKind: String {
    case birth
    case death
    case burial

    var color: Color {
        switch self {
        case .birth: SepiaTheme.pinBirth
        case .death: SepiaTheme.pinDeath
        case .burial: SepiaTheme.pinBurial
        }
    }

    var label: String {
        switch self {
        case .birth: L10n.tr("Рождение")
        case .death: L10n.tr("Смерть")
        case .burial: L10n.tr("Захоронение")
        }
    }
}
