import MapKit
import SwarmCore
import SwiftUI

struct MapChartView: View {
    let tree: FamilyTree
    @Binding var zoom: CGFloat
    @Binding var selectedPerson: Person?
    @Binding var fitRequest: Int
    let focus: MapFocus

    @AppStorage("mapProvider") private var providerRaw = MapProviderSetting.default.rawValue

    @State private var placesSettled = false
    @State private var placesFailed = false
    @State private var vectorsFailed = false
    @State private var tilesLoaded = false
    @State private var tilesFailed = false
    @State private var showsSlowIndicator = false
    @State private var retryToken = 0

    /// A slow load is only worth announcing once it stops looking instant.
    private static let slowLoadThreshold = Duration.seconds(5)

    private var provider: MapProviderSetting {
        MapProviderSetting(rawValue: providerRaw) ?? .default
    }

    private var phase: MapLoadPhase {
        MapLoadPhase.resolve(
            provider: provider,
            placesSettled: placesSettled,
            placesFailed: placesFailed,
            vectorsFailed: vectorsFailed,
            tilesLoaded: tilesLoaded,
            tilesFailed: tilesFailed
        )
    }

    /// Both a retry and a provider switch start the load over from scratch.
    private var loadAttempt: String { "\(retryToken)|\(providerRaw)" }

    var body: some View {
        Group {
            if provider == .appleMaps {
                AppleMapChartView(tree: tree, zoom: $zoom, selectedPerson: $selectedPerson, fitRequest: $fitRequest, focus: focus)
                    .overlay(alignment: .bottomTrailing) { tileProbe }
            } else {
                OfflineVectorMapView(
                    tree: tree,
                    zoom: $zoom,
                    selectedPerson: $selectedPerson,
                    fitRequest: $fitRequest,
                    focus: focus,
                    reloadToken: retryToken
                )
            }
        }
        .task(id: loadAttempt) { await refreshDataState() }
        .task(id: loadAttempt) {
            try? await Task.sleep(for: Self.slowLoadThreshold)
            guard !Task.isCancelled else { return }
            showsSlowIndicator = phase == .loading
        }
        .overlay { loadStateOverlay }
        .onReceive(NotificationCenter.default.publisher(for: .zoomInRequested)) { _ in
            zoom = OfflineMapProjection.steppedZoom(zoom, zoomingIn: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .zoomOutRequested)) { _ in
            zoom = OfflineMapProjection.steppedZoom(zoom, zoomingIn: false)
        }
    }

    // MARK: - Load state

    private var tileProbe: some View {
        MapTileLoadProbe { loaded in
            if loaded { tilesLoaded = true } else { tilesFailed = true }
        }
        // Kept tiny but not invisible: at `opacity(0)` or `.hidden` AppKit skips the tile
        // fetch entirely and the probe never reports anything.
        .frame(width: 1, height: 1)
        .opacity(0.01)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .id(retryToken)
    }

    private func refreshDataState() async {
        showsSlowIndicator = false
        placesSettled = false
        placesFailed = false
        vectorsFailed = false
        tilesLoaded = false
        tilesFailed = false

        await withCheckedContinuation { continuation in
            PlacesDatabase.shared.whenReady { continuation.resume() }
        }
        guard !Task.isCancelled else { return }

        placesFailed = PlacesDatabase.shared.loadFailed
        // Only the offline renderer draws the bundled vectors, so only it waits on them.
        vectorsFailed = provider == .offlineVector && OfflineMapVectorData.shared.didFail
        placesSettled = true
    }

    private func retry() {
        GeocodingService.shared.invalidateCache()
        PlacesDatabase.shared.reload()
        OfflineMapVectorData.reload()
        retryToken += 1
    }

    @ViewBuilder
    private var loadStateOverlay: some View {
        switch phase {
        case .failed:
            failureCard
        case .loading where showsSlowIndicator:
            loadingIndicator
        default:
            EmptyView()
        }
    }

    private var loadingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(L10n.tr("Карта загружается…"))
                .font(SepiaType.label)
                .foregroundColor(SepiaTheme.inkSoft)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(SepiaTheme.paper.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(SepiaTheme.cardLine, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.12), radius: 6, y: 2)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("map.loading")
    }

    private var failureCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(SepiaTheme.icon(size: 26))
                .foregroundColor(SepiaTheme.inkSoft)
            Text(L10n.tr("Не удалось загрузить карту"))
                .font(SepiaTheme.body(size: 14))
                .foregroundColor(SepiaTheme.ink)
            Text(failureDetail)
                .font(SepiaType.label)
                .foregroundColor(SepiaTheme.inkSoft)
                .multilineTextAlignment(.center)
            // Stacked, not side by side: the Russian labels are long enough to truncate in
            // a row narrow enough to sit over the map.
            VStack(spacing: 8) {
                Button(L10n.tr("Загрузить снова")) { retry() }
                    .buttonStyle(.glassProminent)
                    .tint(SepiaTheme.accent)
                    .accessibilityIdentifier("map.retry")
                if provider == .appleMaps {
                    // The offline renderer needs no network, so it is the actual way out of a
                    // tile failure rather than another round of retrying.
                    Button(L10n.tr("Перейти на офлайн-карту")) {
                        providerRaw = MapProviderSetting.offlineVector.rawValue
                    }
                    .buttonStyle(.glass)
                    .accessibilityIdentifier("map.useOfflineMap")
                }
            }
            .padding(.top, 2)
        }
        .padding(20)
        .frame(maxWidth: 320)
        .background(SepiaTheme.paper)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(SepiaTheme.cardLine, lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.18), radius: 10, y: 3)
        .padding(24)
        // A scrim, not an opaque cover: whatever did load stays visible behind it.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SepiaTheme.paper.opacity(0.45))
        .accessibilityIdentifier("map.loadError")
    }

    private var failureDetail: String {
        if placesFailed {
            return L10n.tr("Справочник мест не открылся: места без сохранённых координат не отмечены.")
        }
        if vectorsFailed {
            return L10n.tr("Контуры материков не открылись.")
        }
        return L10n.tr("Apple Maps не отдаёт карту. Проверьте подключение к сети.")
    }
}

struct AppleMapChartView: View {
    let tree: FamilyTree
    @Binding var zoom: CGFloat
    @Binding var selectedPerson: Person?
    @Binding var fitRequest: Int
    let focus: MapFocus
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.default.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mapPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 55, longitude: 40),
        span: MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 60)
    ))
    @State private var annotations: [PersonMapAnnotation] = []
    @State private var polylines: [MapPolylineData] = []
    @State private var lastZoom: CGFloat = 0.85
    @State private var currentSpan: MKCoordinateSpan = .init(latitudeDelta: 40, longitudeDelta: 60)
    @State private var currentCenter: CLLocationCoordinate2D = .init(latitude: 55, longitude: 40)
    @State private var expandedGroupId: String? = nil

    var body: some View {
        let grouped = groupedAnnotations()
        Map(position: $mapPosition) {
            // Grouped pins
            ForEach(grouped) { group in
                Annotation(group.label, coordinate: group.coordinate) {
                    pinButton(for: group)
                }
            }
            // Connection lines: dashed birth→death life line, dotted death→grave burial line.
            ForEach(polylines) { line in
                MapPolyline(coordinates: line.coordinates)
                    .stroke(lineColor(for: line), style: lineStroke(for: line))
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .animation(reduceMotion ? nil : SepiaMotion.select, value: focus)
        .mapControls {
            MapCompass()
            MapScaleView()
            MapZoomStepper()
        }
        .onMapCameraChange { context in
            currentSpan = context.region.span
            currentCenter = context.region.center
        }
        .onAppear {
            lastZoom = zoom
            // Wait for the GeoNames DB so known places resolve instead of
            // prematurely returning nil (unpinned) before it has loaded.
            GeocodingService.shared.whenReady {
                computeAnnotations()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    fitToAnnotations()
                }
            }
        }
        .onChange(of: tree.layoutVersion) { _, _ in
            computeAnnotations()
        }
        .onChange(of: languageRaw) { _, _ in computeAnnotations() }
        .onChange(of: fitRequest) { _, _ in
            fitToAnnotations()
        }
        .onChange(of: zoom) { oldVal, newVal in
            guard abs(newVal - lastZoom) > 0.01 else { return }
            let factor = newVal / lastZoom
            lastZoom = newVal
            let newLatDelta = currentSpan.latitudeDelta / factor
            let newLonDelta = currentSpan.longitudeDelta / factor
            let clampedLat = max(0.5, min(newLatDelta, 160))
            let clampedLon = max(0.5, min(newLonDelta, 360))
            currentSpan = MKCoordinateSpan(latitudeDelta: clampedLat, longitudeDelta: clampedLon)

            withAnimation(reduceMotion ? nil : SepiaMotion.camera) {
                mapPosition = .region(MKCoordinateRegion(center: currentCenter, span: currentSpan))
            }
        }
        // Top-leading, not bottom: MapKit draws its own attribution and legal link in
        // the bottom-left corner, and Apple's terms require it to stay visible. The
        // legend used to sit on top of it.
        .overlay(alignment: .topLeading) {
            legendView
        }
    }

    // MARK: - Focus Styling

    private func lineColor(for line: MapPolylineData) -> Color {
        let base = line.dotted ? SepiaTheme.pinBurial.opacity(0.8) : SepiaTheme.mapLine
        return base.opacity(focus.emphasis(for: line.personId).lineOpacity)
    }

    /// The selected person's own path thickens by a point so it reads above their branch.
    private func lineStroke(for line: MapPolylineData) -> StrokeStyle {
        let bump: CGFloat = focus.emphasis(for: line.personId) == .focused ? 1 : 0
        return line.dotted
            ? StrokeStyle(lineWidth: 3 + bump, lineCap: .round, dash: [0.1, 6])
            : StrokeStyle(lineWidth: 2 + bump, dash: [6, 4])
    }

    // MARK: - Pin Button (interactive)

    @ViewBuilder
    private func pinButton(for group: AnnotationGroup) -> some View {
        // Distinct event types at this location, in a stable order (birth, death, burial).
        let types = [MapPinType.birth, .death, .burial].filter { t in
            group.annotations.contains { $0.eventType == t }
        }
        let count = group.annotations.count
        let isExpanded = Binding<Bool>(
            get: { expandedGroupId == group.id },
            set: { if !$0 { expandedGroupId = nil } }
        )

        ZStack {
            if types.count > 1 {
                HStack(spacing: 2) {
                    ForEach(types, id: \.self) { t in
                        Circle()
                            .fill(t.pinColor)
                            .frame(width: 12, height: 12)
                    }
                }
                .padding(2)
                .background(Capsule().fill(Color.white))
            } else {
                Circle()
                    .fill((types.first ?? .death).pinColor)
                    .frame(width: 14, height: 14)
                Circle()
                    .strokeBorder(Color.white, lineWidth: 2)
                    .frame(width: 14, height: 14)
            }

            if count > 1 {
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundColor(.white)
                    .padding(2)
                    .background(Circle().fill(Color.black.opacity(0.7)))
                    .offset(x: 10, y: -10)
            }
        }
        .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        .opacity(focus.emphasis(forAny: group.annotations.map(\.personId)).pinOpacity)
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(group.label)
        .accessibilityHint(
            count == 1
                ? L10n.tr("Выбрать персону")
                : L10n.tr("Показать \(L10n.count(count, .person))")
        )
        .accessibilityAction {
            if count == 1 {
                selectedPerson = tree.people.first { $0.id == group.annotations[0].personId }
            } else {
                expandedGroupId = group.id
            }
        }
        .onTapGesture {
            if count == 1 {
                selectedPerson = tree.people.first { $0.id == group.annotations[0].personId }
            } else {
                expandedGroupId = group.id
            }
        }
        .popover(isPresented: isExpanded, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(group.annotations) { ann in
                    Button {
                        selectedPerson = tree.people.first { $0.id == ann.personId }
                        expandedGroupId = nil
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(ann.eventType.pinColor)
                                .frame(width: 8, height: 8)
                            Text(ann.personName)
                                .font(SepiaType.label)
                                .foregroundColor(SepiaTheme.ink)
                                .lineLimit(1)
                            Text(ann.eventType.shortLabel)
                                .font(SepiaTheme.ui(size: 9))
                                .foregroundColor(SepiaTheme.inkSoft)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .opacity(focus.emphasis(for: ann.personId).pinOpacity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if ann.id != group.annotations.last?.id {
                        Divider()
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Grouping

    private func groupedAnnotations() -> [AnnotationGroup] {
        // Group annotations by approximate coordinate (within ~100m)
        var groups: [String: [PersonMapAnnotation]] = [:]
        for ann in annotations {
            let key = "\(String(format: "%.3f", ann.coordinate.latitude)),\(String(format: "%.3f", ann.coordinate.longitude))"
            groups[key, default: []].append(ann)
        }
        return groups.map { key, anns in
            AnnotationGroup(
                id: key,
                coordinate: anns[0].coordinate,
                annotations: anns
            )
        }
    }

    // MARK: - Legend

    private var legendView: some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Circle().fill(SepiaTheme.pinBirth).frame(width: 8, height: 8)
                Text(L10n.tr("Рождение"))
                    .font(SepiaType.label)
                    .foregroundColor(SepiaTheme.inkSoft)
            }
            HStack(spacing: 4) {
                Circle().fill(SepiaTheme.pinDeath).frame(width: 8, height: 8)
                Text(L10n.tr("Смерть"))
                    .font(SepiaType.label)
                    .foregroundColor(SepiaTheme.inkSoft)
            }
            HStack(spacing: 4) {
                Circle().fill(SepiaTheme.pinBurial).frame(width: 8, height: 8)
                Text(L10n.tr("Захоронение"))
                    .font(SepiaType.label)
                    .foregroundColor(SepiaTheme.inkSoft)
            }
        }
        .padding(8)
        .background(SepiaTheme.paper.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(SepiaTheme.cardLine, lineWidth: 0.5)
        )
        .padding(12)
    }

    // MARK: - Compute Annotations

    private func computeAnnotations() {
        let geo = GeocodingService.shared
        var newAnnotations: [PersonMapAnnotation] = []
        var newPolylines: [MapPolylineData] = []

        for person in tree.people {
            var birthCoord: CLLocationCoordinate2D?
            var deathCoord: CLLocationCoordinate2D?
            var burialCoord: CLLocationCoordinate2D?

            // Birth — explicit (manual or previously-resolved) coordinates win; only
            // geocode the place name when no coordinates are stored.
            if let lat = person.birthLat, let lon = person.birthLon {
                birthCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else if let place = person.birthPlace, !place.isEmpty {
                if let coord = geo.coordinateSync(for: place) {
                    birthCoord = coord
                    person.birthLat = coord.latitude
                    person.birthLon = coord.longitude
                }
            }

            // Death
            if let lat = person.deathLat, let lon = person.deathLon {
                deathCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else if let place = person.deathPlace, !place.isEmpty {
                if let coord = geo.coordinateSync(for: place) {
                    deathCoord = coord
                    person.deathLat = coord.latitude
                    person.deathLon = coord.longitude
                }
            }

            // Burial — manual grave coordinates win; otherwise geocode the place name.
            if let lat = person.burialLat, let lon = person.burialLon {
                burialCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else if let place = person.burialPlace, !place.isEmpty {
                burialCoord = geo.coordinateSync(for: place)
            }

            // Create annotations
            if let coord = birthCoord {
                newAnnotations.append(PersonMapAnnotation(
                    personId: person.id,
                    personName: person.displayName(language: .current),
                    placeName: person.presentationPlace(kind: .birth, fallback: person.birthPlace),
                    eventType: .birth,
                    coordinate: coord
                ))
            }
            if let coord = deathCoord {
                newAnnotations.append(PersonMapAnnotation(
                    personId: person.id,
                    personName: person.displayName(language: .current),
                    placeName: person.presentationPlace(kind: .death, fallback: person.deathPlace),
                    eventType: .death,
                    coordinate: coord
                ))
            }
            if let coord = burialCoord {
                newAnnotations.append(PersonMapAnnotation(
                    personId: person.id,
                    personName: person.displayName(language: .current),
                    placeName: person.presentationPlace(kind: .burial, fallback: person.burialPlace),
                    eventType: .burial,
                    coordinate: coord
                ))
            }

            // Life line (dashed): birth → death.
            if let b = birthCoord, let d = deathCoord {
                newPolylines.append(MapPolylineData(personId: person.id, coordinates: [b, d]))
            }
            // Burial line (dotted): death → grave.
            if let d = deathCoord, let g = burialCoord {
                newPolylines.append(MapPolylineData(personId: person.id, coordinates: [d, g], dotted: true))
            }
        }

        annotations = newAnnotations
        polylines = newPolylines

        // Fit map to show all annotations
        fitToAnnotations()
    }

    private func fitToAnnotations() {
        // With a branch selected, frame that branch rather than the whole tree. A branch
        // with no coordinates of its own falls back to everything.
        let onBranch = focus.isActive ? annotations.filter { focus.emphasis(for: $0.personId) != .dimmed } : []
        let annotations = onBranch.isEmpty ? annotations : onBranch

        guard !annotations.isEmpty else {
            // Default: show Eurasia
            let defaultSpan = MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 60)
            currentSpan = defaultSpan
            lastZoom = zoom
            mapPosition = .region(MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 55, longitude: 40),
                span: defaultSpan
            ))
            return
        }

        let lats = annotations.map(\.coordinate.latitude)
        let lons = annotations.map(\.coordinate.longitude)
        let minLat = lats.min()!
        let maxLat = lats.max()!
        let minLon = lons.min()!
        let maxLon = lons.max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, 5),
            longitudeDelta: max((maxLon - minLon) * 1.4, 5)
        )

        currentSpan = span
        lastZoom = zoom

        withAnimation(reduceMotion ? nil : SepiaMotion.cameraLong) {
            mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}

// MARK: - Data Types

struct AnnotationGroup: Identifiable {
    let id: String // stable key from coordinates
    let coordinate: CLLocationCoordinate2D
    let annotations: [PersonMapAnnotation]

    var label: String {
        if annotations.count == 1 {
            return annotations[0].personName
        }
        return "\(annotations[0].personName) +\(annotations.count - 1)"
    }
}

struct PersonMapAnnotation: Identifiable {
    let id = UUID()
    let personId: UUID
    let personName: String
    let placeName: String
    let eventType: MapPinType
    let coordinate: CLLocationCoordinate2D

    var label: String {
        personName
    }
}

struct MapPolylineData: Identifiable {
    let id = UUID()
    let personId: UUID
    let coordinates: [CLLocationCoordinate2D]
    /// Life line (birth→death) is dashed; the burial line (death→grave) is dotted.
    var dotted: Bool = false
}

enum MapPinType {
    case birth, death, burial

    var pinColor: Color {
        switch self {
        case .birth: SepiaTheme.pinBirth
        case .death: SepiaTheme.pinDeath
        case .burial: SepiaTheme.pinBurial
        }
    }

    /// Short label used in the grouped-pin popover.
    var shortLabel: String {
        switch self {
        case .birth: L10n.tr("род.")
        case .death: L10n.tr("ум.")
        case .burial: L10n.tr("погр.")
        }
    }
}
