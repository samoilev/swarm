import FamilyTreeCore
import MapKit
import SwiftUI

/// A small, non-interactive map showing a person's birth and death places as pins,
/// connected by a line. Shows just one pin when only one place is known. Coordinates
/// come from the person's cached lat/lon or the local GeoNames DB (offline only).
struct PersonMiniMap: View {
    let person: Person
    @AppStorage("mapProvider") private var providerRaw = MapProviderSetting.default.rawValue

    var body: some View {
        if providerRaw == MapProviderSetting.appleMaps.rawValue {
            ApplePersonMiniMap(person: person)
        } else {
            OfflinePersonMiniMap(person: person)
        }
    }
}

struct ApplePersonMiniMap: View {
    let person: Person

    @State private var birth: CLLocationCoordinate2D?
    @State private var death: CLLocationCoordinate2D?
    @State private var position: MapCameraPosition = .automatic
    @State private var resolved = false

    var body: some View {
        Group {
            if birth != nil || death != nil {
                Map(position: $position, interactionModes: []) {
                    if let b = birth {
                        Annotation(settlement(person.birthPlace), coordinate: b) { dot(SepiaTheme.pinBirth) }
                    }
                    if let d = death {
                        Annotation(settlement(person.deathPlace), coordinate: d) { dot(SepiaTheme.pinDeath) }
                    }
                    if let b = birth, let d = death {
                        MapPolyline(coordinates: [b, d])
                            .stroke(SepiaTheme.mapLine, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
                .overlay(alignment: .bottomLeading) { legend }
            } else if resolved {
                placeholder(text: "Не удалось определить место на карте")
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(SepiaTheme.cardBg)
                    ProgressView().controlSize(.small)
                }
                .frame(height: 80)
            }
        }
        .task(id: locationKey) { await resolve() }
    }

    /// The settlement name for a pin caption — the first comma-component of the stored
    /// place (e.g. "Москва" from "Москва, Москва, Россия"). Empty when no place is set.
    private func settlement(_ place: String?) -> String {
        guard let p = place?.trimmingCharacters(in: .whitespaces), !p.isEmpty else { return "" }
        return p.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? p
    }

    private func dot(_ color: Color) -> some View {
        ZStack {
            Circle().fill(color)
                .frame(width: 14, height: 14)
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
        }
        // An explicit outer frame is required: without it MapKit on macOS
        // measures the annotation content as zero-sized and clips it invisible.
        .frame(width: 28, height: 28)
    }

    private func placeholder(text: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(SepiaTheme.cardBg)
            Text(text).font(SepiaTheme.body(size: 12)).foregroundColor(SepiaTheme.inkSoft)
                .multilineTextAlignment(.center).padding(8)
        }
        .frame(height: 64)
    }

    private var legend: some View {
        HStack(spacing: 8) {
            if birth != nil {
                HStack(spacing: 3) { Circle().fill(SepiaTheme.pinBirth).frame(width: 6, height: 6); Text("Рожд.") }
            }
            if death != nil {
                HStack(spacing: 3) { Circle().fill(SepiaTheme.pinDeath).frame(width: 6, height: 6); Text("Смерть") }
            }
        }
        .font(SepiaTheme.ui(size: 9))
        .foregroundColor(SepiaTheme.inkSoft)
        .padding(5)
        .background(SepiaTheme.paper.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .padding(6)
    }

    /// Changes whenever any location-relevant field changes, so `.task` re-runs.
    private var locationKey: String {
        "\(person.birthPlace ?? "")|" +
            "\(person.birthLat.map { String($0) } ?? "")|\(person.birthLon.map { String($0) } ?? "")|" +
            "\(person.deathPlace ?? "")|" +
            "\(person.deathLat.map { String($0) } ?? "")|\(person.deathLon.map { String($0) } ?? "")"
    }

    // MARK: - Coordinate resolution

    private func resolve() async {
        // Clear stale pins immediately so the old location doesn't linger
        // while the new one is geocoding.
        birth = nil
        death = nil
        resolved = false
        // Also clear the in-memory geocoding cache for this person's places so
        // that if wrong coordinates were previously cached (e.g. a disambiguation
        // error) they don't survive across the task restart.
        if let p = person.birthPlace { GeocodingService.shared.clearCache(for: p) }
        if let p = person.deathPlace { GeocodingService.shared.clearCache(for: p) }

        let geo = GeocodingService.shared
        var b: CLLocationCoordinate2D?
        var d: CLLocationCoordinate2D?

        if let lat = person.birthLat, let lon = person.birthLon { b = .init(latitude: lat, longitude: lon) }
        if let lat = person.deathLat, let lon = person.deathLon { d = .init(latitude: lat, longitude: lon) }

        // Wait for the local GeoNames DB so known places resolve instead of
        // returning nil before it has finished loading.
        await withCheckedContinuation { cont in geo.whenReady { cont.resume() } }

        if b == nil, let place = person.birthPlace, !place.isEmpty {
            if let c = geo.coordinateSync(for: place) { b = c; person.birthLat = c.latitude; person.birthLon = c.longitude }
        }
        if d == nil, let place = person.deathPlace, !place.isEmpty {
            if let c = geo.coordinateSync(for: place) { d = c; person.deathLat = c.latitude; person.deathLon = c.longitude }
        }

        birth = b
        death = d
        resolved = true
        updateCamera()
    }

    private func updateCamera() {
        let coords = [birth, death].compactMap { $0 }
        guard !coords.isEmpty else { return }
        if coords.count == 1 {
            position = .region(MKCoordinateRegion(
                center: coords[0],
                span: MKCoordinateSpan(latitudeDelta: 6, longitudeDelta: 6)
            ))
        } else {
            let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
            let center = CLLocationCoordinate2D(
                latitude: (lats.min()! + lats.max()!) / 2,
                longitude: (lons.min()! + lons.max()!) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max((lats.max()! - lats.min()!) * 1.6, 4),
                longitudeDelta: max((lons.max()! - lons.min()!) * 1.6, 4)
            )
            position = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}
