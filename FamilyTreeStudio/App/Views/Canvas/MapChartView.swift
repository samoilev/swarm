import FamilyTreeCore
import MapKit
import SwiftUI

struct MapChartView: View {
    let tree: FamilyTree
    @Binding var zoom: CGFloat
    @Binding var selectedPerson: Person?
    @Binding var fitRequest: Int

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
                    .stroke(
                        line.dotted ? SepiaTheme.pinBurial.opacity(0.8) : SepiaTheme.mapLine,
                        style: line.dotted
                            ? StrokeStyle(lineWidth: 3, lineCap: .round, dash: [0.1, 6])
                            : StrokeStyle(lineWidth: 2, dash: [6, 4])
                    )
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
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

            withAnimation(.easeInOut(duration: 0.3)) {
                mapPosition = .region(MKCoordinateRegion(center: currentCenter, span: currentSpan))
            }
        }
        .overlay(alignment: .bottomLeading) {
            legendView
        }
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
        .frame(width: 30, height: 30)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(group.label)
        .accessibilityHint(count == 1 ? "Выбрать персону" : "Показать \(count) персон")
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
                                .font(SepiaTheme.ui(size: 11))
                                .foregroundColor(SepiaTheme.ink)
                                .lineLimit(1)
                            Text(ann.eventType.shortLabel)
                                .font(SepiaTheme.ui(size: 9))
                                .foregroundColor(SepiaTheme.inkSoft)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
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
                Text("Рождение")
                    .font(SepiaTheme.ui(size: 11))
                    .foregroundColor(SepiaTheme.inkSoft)
            }
            HStack(spacing: 4) {
                Circle().fill(SepiaTheme.pinDeath).frame(width: 8, height: 8)
                Text("Смерть")
                    .font(SepiaTheme.ui(size: 11))
                    .foregroundColor(SepiaTheme.inkSoft)
            }
            HStack(spacing: 4) {
                Circle().fill(SepiaTheme.pinBurial).frame(width: 8, height: 8)
                Text("Захоронение")
                    .font(SepiaTheme.ui(size: 11))
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
                    personName: person.listName,
                    placeName: person.birthPlace ?? "",
                    eventType: .birth,
                    coordinate: coord
                ))
            }
            if let coord = deathCoord {
                newAnnotations.append(PersonMapAnnotation(
                    personId: person.id,
                    personName: person.listName,
                    placeName: person.deathPlace ?? "",
                    eventType: .death,
                    coordinate: coord
                ))
            }
            if let coord = burialCoord {
                newAnnotations.append(PersonMapAnnotation(
                    personId: person.id,
                    personName: person.listName,
                    placeName: person.burialPlace ?? "",
                    eventType: .burial,
                    coordinate: coord
                ))
            }

            // Life line (dashed): birth → death.
            if let b = birthCoord, let d = deathCoord {
                newPolylines.append(MapPolylineData(coordinates: [b, d]))
            }
            // Burial line (dotted): death → grave.
            if let d = deathCoord, let g = burialCoord {
                newPolylines.append(MapPolylineData(coordinates: [d, g], dotted: true))
            }
        }

        annotations = newAnnotations
        polylines = newPolylines

        // Fit map to show all annotations
        fitToAnnotations()
    }

    private func fitToAnnotations() {
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

        withAnimation(.easeInOut(duration: 0.5)) {
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
        case .birth: "род."
        case .death: "ум."
        case .burial: "погр."
        }
    }
}
