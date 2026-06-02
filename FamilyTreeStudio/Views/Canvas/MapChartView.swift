import SwiftUI
import MapKit

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
    @State private var isGeocodingInProgress = false
    @State private var lastZoom: CGFloat = 0.85
    @State private var currentSpan: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 40, longitudeDelta: 60)
    @State private var currentCenter: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 55, longitude: 40)
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
            // Connection lines between birth and death of same person
            ForEach(polylines) { line in
                MapPolyline(coordinates: line.coordinates)
                    .stroke(SepiaTheme.mapLine, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
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
            // Wait for the GeoNames DB so known places resolve locally instead of
            // all falling through to CLGeocoder (rate-limited).
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
        let hasBirth = group.annotations.contains { $0.eventType == .birth }
        let hasDeath = group.annotations.contains { $0.eventType == .death }
        let count = group.annotations.count
        let isExpanded = Binding<Bool>(
            get: { expandedGroupId == group.id },
            set: { if !$0 { expandedGroupId = nil } }
        )
        
        ZStack {
            if hasBirth && hasDeath {
                HStack(spacing: 2) {
                    Circle()
                        .fill(SepiaTheme.pinBirth)
                        .frame(width: 12, height: 12)
                    Circle()
                        .fill(SepiaTheme.pinDeath)
                        .frame(width: 12, height: 12)
                }
                .padding(2)
                .background(Capsule().fill(Color.white))
            } else {
                Circle()
                    .fill(hasBirth ? SepiaTheme.pinBirth : SepiaTheme.pinDeath)
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
                                .fill(ann.eventType == .birth ? SepiaTheme.pinBirth : SepiaTheme.pinDeath)
                                .frame(width: 8, height: 8)
                            Text(ann.personName)
                                .font(SepiaTheme.ui(size: 11))
                                .foregroundColor(SepiaTheme.ink)
                                .lineLimit(1)
                            Text(ann.eventType == .birth ? "род." : "ум.")
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
        return groups.map { (key, anns) in
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
        var pendingGeocode: [(Person, String, MapPinType)] = []
        
        for person in tree.people {
            var birthCoord: CLLocationCoordinate2D?
            var deathCoord: CLLocationCoordinate2D?
            
            // Birth
            if let place = person.birthPlace, !place.isEmpty {
                if let lat = person.birthLat, let lon = person.birthLon {
                    birthCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                } else if let coord = geo.coordinateSync(for: place) {
                    birthCoord = coord
                    person.birthLat = coord.latitude
                    person.birthLon = coord.longitude
                } else {
                    pendingGeocode.append((person, place, .birth))
                }
            }
            
            // Death
            if let place = person.deathPlace, !place.isEmpty {
                if let lat = person.deathLat, let lon = person.deathLon {
                    deathCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                } else if let coord = geo.coordinateSync(for: place) {
                    deathCoord = coord
                    person.deathLat = coord.latitude
                    person.deathLon = coord.longitude
                } else {
                    pendingGeocode.append((person, place, .death))
                }
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
            
            // Polyline
            if let b = birthCoord, let d = deathCoord {
                newPolylines.append(MapPolylineData(
                    id: person.id,
                    coordinates: [b, d]
                ))
            }
        }
        
        annotations = newAnnotations
        polylines = newPolylines
        
        // Fit map to show all annotations
        fitToAnnotations()
        
        // Async geocode pending places — serialize to avoid CLGeocoder throttling
        if !pendingGeocode.isEmpty {
            isGeocodingInProgress = true
            geocodeSequentially(items: pendingGeocode, index: 0)
        }
    }
    
    private func geocodeSequentially(items: [(Person, String, MapPinType)], index: Int) {
        guard index < items.count else {
            isGeocodingInProgress = false
            fitToAnnotations()
            return
        }
        
        let (person, place, eventType) = items[index]
        let geo = GeocodingService.shared
        
        geo.coordinate(for: place) { coord in
            DispatchQueue.main.async {
                if let coord {
                    switch eventType {
                    case .birth:
                        person.birthLat = coord.latitude
                        person.birthLon = coord.longitude
                    case .death:
                        person.deathLat = coord.latitude
                        person.deathLon = coord.longitude
                    }
                    
                    let ann = PersonMapAnnotation(
                        personId: person.id,
                        personName: person.listName,
                        placeName: eventType == .birth ? (person.birthPlace ?? "") : (person.deathPlace ?? ""),
                        eventType: eventType,
                        coordinate: coord
                    )
                    annotations.append(ann)
                    
                    if let bLat = person.birthLat, let bLon = person.birthLon,
                       let dLat = person.deathLat, let dLon = person.deathLon {
                        let b = CLLocationCoordinate2D(latitude: bLat, longitude: bLon)
                        let d = CLLocationCoordinate2D(latitude: dLat, longitude: dLon)
                        polylines.removeAll { $0.id == person.id }
                        polylines.append(MapPolylineData(id: person.id, coordinates: [b, d]))
                    }
                }
                
                // Process next after short delay to respect CLGeocoder rate limits
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    geocodeSequentially(items: items, index: index + 1)
                }
            }
        }
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
    let id: String  // stable key from coordinates
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
    let id: UUID
    let coordinates: [CLLocationCoordinate2D]
}

enum MapPinType {
    case birth, death
}
