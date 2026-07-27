import SwarmCore
import SwiftUI

/// Network-free map surface. It deliberately has no MapKit dependency and renders a
/// compact bundled world outline plus the tree's stored coordinates with SwiftUI Canvas.
struct OfflineVectorMapView: View {
    let tree: FamilyTree
    @Binding var zoom: CGFloat
    @Binding var selectedPerson: Person?
    @Binding var fitRequest: Int

    @State private var annotations: [OfflineMapAnnotation] = []
    @State private var routes: [OfflineMapRoute] = []
    @State private var center = CGPoint(x: 0.61, y: 0.31)
    @State private var mapScale: CGFloat = 2.4
    @State private var scaleAtGestureStart: CGFloat = 2.4
    @State private var expandedClusterID: String?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Canvas { context, size in
                    drawBackground(context: &context, size: size)
                    drawRoutes(context: &context, size: size)
                }
                .contentShape(Rectangle())
                .gesture(dragGesture(size: proxy.size))
                .simultaneousGesture(magnificationGesture)

                ForEach(clusters(in: proxy.size)) { cluster in
                    clusterButton(cluster)
                        .position(cluster.point)
                }

                if annotations.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 28))
                        Text(L10n.tr("Нет мест с координатами"))
                            .font(SepiaTheme.body(size: 14))
                        Text(L10n.tr("Выберите место из справочника или укажите координаты вручную"))
                            .font(SepiaTheme.ui(size: 11))
                    }
                    .foregroundColor(SepiaTheme.inkSoft)
                    .multilineTextAlignment(.center)
                }
            }
            .clipped()
            .background(Color(hex: "e8e0c8"))
            .overlay(alignment: .topLeading) {
                Label(L10n.tr("Офлайн"), systemImage: "network.slash")
                    .font(SepiaTheme.ui(size: 10))
                    .foregroundColor(SepiaTheme.inkSoft)
                    .padding(7)
                    .background(SepiaTheme.paper.opacity(0.92))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(12)
            }
            .overlay(alignment: .bottomLeading) { legend }
            .onAppear {
                resolveAnnotations()
                fit(size: proxy.size)
            }
            .onChange(of: tree.layoutVersion) { _, _ in
                resolveAnnotations()
                fit(size: proxy.size)
            }
            .onChange(of: fitRequest) { _, _ in fit(size: proxy.size) }
            .onChange(of: zoom) { oldValue, newValue in
                guard oldValue > 0 else { return }
                mapScale = min(40, max(0.8, mapScale * newValue / oldValue))
                scaleAtGestureStart = mapScale
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(L10n.tr("Офлайн-карта мест семьи"))
        .accessibilityRepresentation {
            VStack {
                Text(L10n.tr("Места семьи"))
                ForEach(annotations) { annotation in
                    Button("\(annotation.personName): \(annotation.placeName), \(annotation.kind.label)") {
                        selectedPerson = tree.person(byId: annotation.personID)
                    }
                }
            }
        }
    }

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
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(10)
        }
    }

    private func drawBackground(context: inout GraphicsContext, size: CGSize) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "e8e0c8")))

        // Latitude/longitude grid.
        for longitude in stride(from: -180.0, through: 180.0, by: 30.0) {
            var path = Path()
            for latitude in stride(from: -80.0, through: 80.0, by: 4.0) {
                let point = project(OfflineCoordinate(latitude: latitude, longitude: longitude), size: size)
                if latitude == -80 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(SepiaTheme.line.opacity(0.18)), lineWidth: 0.5)
        }
        for latitude in stride(from: -60.0, through: 75.0, by: 15.0) {
            var path = Path()
            for longitude in stride(from: -180.0, through: 180.0, by: 5.0) {
                let point = project(OfflineCoordinate(latitude: latitude, longitude: longitude), size: size)
                if longitude == -180 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(SepiaTheme.line.opacity(0.18)), lineWidth: 0.5)
        }

        for polygon in OfflineMapVectorData.shared.landPolygons {
            guard let first = polygon.first else { continue }
            var path = Path()
            path.move(to: project(vectorCoordinate(first), size: size))
            for coordinate in polygon.dropFirst() { path.addLine(to: project(vectorCoordinate(coordinate), size: size)) }
            path.closeSubpath()
            context.fill(path, with: .color(Color(hex: "c9c0a4")))
            context.stroke(path, with: .color(SepiaTheme.inkSoft.opacity(0.45)), lineWidth: 0.8)
        }

        for border in OfflineMapVectorData.shared.borderLines {
            guard let first = border.first else { continue }
            var path = Path()
            path.move(to: project(vectorCoordinate(first), size: size))
            for coordinate in border.dropFirst() { path.addLine(to: project(vectorCoordinate(coordinate), size: size)) }
            context.stroke(path, with: .color(SepiaTheme.inkSoft.opacity(0.28)), lineWidth: 0.45)
        }

        for label in OfflineWorldOutline.labels {
            let point = project(label.coordinate, size: size)
            context.draw(
                Text(label.name).font(SepiaTheme.ui(size: 9)).foregroundColor(SepiaTheme.inkSoft.opacity(0.8)),
                at: point
            )
        }
    }

    private func drawRoutes(context: inout GraphicsContext, size: CGSize) {
        for route in routes {
            var path = Path()
            path.move(to: project(route.start, size: size))
            path.addLine(to: project(route.end, size: size))
            context.stroke(
                path,
                with: .color(route.isBurial ? SepiaTheme.pinBurial.opacity(0.7) : SepiaTheme.mapLine),
                style: StrokeStyle(lineWidth: route.isBurial ? 2.5 : 2, dash: route.isBurial ? [1, 5] : [6, 4])
            )
        }
    }

    private func vectorCoordinate(_ point: MapVectorPoint) -> OfflineCoordinate {
        OfflineCoordinate(latitude: point.latitude, longitude: point.longitude)
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
                    personName: person.listName,
                    placeName: person.birthPlace ?? "",
                    kind: .birth,
                    coordinate: birth
                ))
            }
            if let death {
                result.append(OfflineMapAnnotation(
                    personID: person.id,
                    personName: person.listName,
                    placeName: person.deathPlace ?? "",
                    kind: .death,
                    coordinate: death
                ))
            }
            if let burial {
                result.append(OfflineMapAnnotation(
                    personID: person.id,
                    personName: person.listName,
                    placeName: person.burialPlace ?? "",
                    kind: .burial,
                    coordinate: burial
                ))
            }
            if let birth, let death { newRoutes.append(OfflineMapRoute(start: birth, end: death, isBurial: false)) }
            if let death, let burial { newRoutes.append(OfflineMapRoute(start: death, end: burial, isBurial: true)) }
        }
        annotations = result
        routes = newRoutes
    }

    private func coordinate(latitude: Double?, longitude: Double?, place: String?) -> OfflineCoordinate? {
        if let latitude, let longitude, (-90 ... 90).contains(latitude), (-180 ... 180).contains(longitude) {
            return OfflineCoordinate(latitude: latitude, longitude: longitude)
        }
        if let coordinate = GeocodingService.shared.coordinateSync(for: place) {
            return OfflineCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        return nil
    }

    private func fit(size: CGSize) {
        guard !annotations.isEmpty, size.width > 0, size.height > 0 else { return }
        let normalized = annotations.map { Self.normalized($0.coordinate) }
        let minX = normalized.map(\.x).min()!, maxX = normalized.map(\.x).max()!
        let minY = normalized.map(\.y).min()!, maxY = normalized.map(\.y).max()!
        center = CGPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
        let width = max(maxX - minX, 0.025)
        let height = max(maxY - minY, 0.025)
        mapScale = min(32, max(0.9, min(0.78 / width, 0.78 * size.height / size.width / height)))
        scaleAtGestureStart = mapScale
        zoom = 0.85
    }

    private func project(_ coordinate: OfflineCoordinate, size: CGSize) -> CGPoint {
        let normalized = Self.normalized(coordinate)
        return CGPoint(
            x: size.width / 2 + (normalized.x - center.x) * size.width * mapScale,
            y: size.height / 2 + (normalized.y - center.y) * size.width * mapScale
        )
    }

    private static func normalized(_ coordinate: OfflineCoordinate) -> CGPoint {
        let latitude = min(85.0511, max(-85.0511, coordinate.latitude))
        let x = (coordinate.longitude + 180) / 360
        let radians = latitude * .pi / 180
        let y = (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2
        return CGPoint(x: x, y: y)
    }

    private func dragGesture(size: CGSize) -> some Gesture {
        DragGesture()
            .onEnded { value in
                guard size.width > 0 else { return }
                center.x -= value.translation.width / (size.width * mapScale)
                center.y -= value.translation.height / (size.width * mapScale)
                center.x = min(1, max(0, center.x))
                center.y = min(1, max(0, center.y))
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in mapScale = min(40, max(0.8, scaleAtGestureStart * value)) }
            .onEnded { _ in scaleAtGestureStart = mapScale }
    }

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
            Text(text).font(SepiaTheme.ui(size: 11)).foregroundColor(SepiaTheme.inkSoft)
        }
    }
}

struct OfflinePersonMiniMap: View {
    let person: Person

    var body: some View {
        GeometryReader { proxy in
            let points = miniPoints
            ZStack {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(hex: "e8e0c8")))
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
    }

    private var miniPoints: [OfflineMapAnnotation] {
        var result: [OfflineMapAnnotation] = []
        if let coordinate = miniCoordinate(person.birthLat, person.birthLon, person.birthPlace) {
            result.append(OfflineMapAnnotation(
                personID: person.id, personName: person.listName, placeName: person.birthPlace ?? "",
                kind: .birth, coordinate: coordinate
            ))
        }
        if let coordinate = miniCoordinate(person.deathLat, person.deathLon, person.deathPlace) {
            result.append(OfflineMapAnnotation(
                personID: person.id, personName: person.listName, placeName: person.deathPlace ?? "",
                kind: .death, coordinate: coordinate
            ))
        }
        return result
    }

    private func miniCoordinate(_ latitude: Double?, _ longitude: Double?, _ place: String?) -> OfflineCoordinate? {
        if let latitude, let longitude { return OfflineCoordinate(latitude: latitude, longitude: longitude) }
        if let coordinate = GeocodingService.shared.coordinateSync(for: place) {
            return OfflineCoordinate(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
        return nil
    }

    private func miniProject(_ coordinate: OfflineCoordinate, points: [OfflineMapAnnotation], size: CGSize) -> CGPoint {
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

private struct OfflineCoordinate: Hashable {
    let latitude: Double
    let longitude: Double
}

private struct OfflineMapAnnotation: Identifiable {
    var id: String { "\(personID)-\(kind.rawValue)-\(coordinate.latitude)-\(coordinate.longitude)" }
    let personID: UUID
    let personName: String
    let placeName: String
    let kind: OfflineMapPinKind
    let coordinate: OfflineCoordinate
}

private struct OfflineMapRoute: Identifiable {
    let id = UUID()
    let start: OfflineCoordinate
    let end: OfflineCoordinate
    let isBurial: Bool
}

private struct OfflineMapCluster: Identifiable {
    let id: String
    let point: CGPoint
    let annotations: [OfflineMapAnnotation]
    var color: Color { annotations.first?.kind.color ?? SepiaTheme.accent }
    var accessibilityLabel: String {
        if annotations.count == 1 { return "\(annotations[0].personName), \(annotations[0].kind.label)" }
        return L10n.tr("\(annotations.count) событий в одном месте")
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

private enum OfflineWorldOutline {
    struct Label {
        let name: String
        let coordinate: OfflineCoordinate
    }

    static let labels: [Label] = [
        Label(name: L10n.tr("Москва"), coordinate: OfflineCoordinate(latitude: 55.7558, longitude: 37.6173)),
        Label(name: L10n.tr("Санкт-Петербург"), coordinate: OfflineCoordinate(latitude: 59.9343, longitude: 30.3351)),
        Label(name: L10n.tr("Киев"), coordinate: OfflineCoordinate(latitude: 50.4501, longitude: 30.5234)),
        Label(name: L10n.tr("Минск"), coordinate: OfflineCoordinate(latitude: 53.9006, longitude: 27.5590)),
        Label(name: L10n.tr("Алматы"), coordinate: OfflineCoordinate(latitude: 43.2389, longitude: 76.8897)),
    ]
}
