import Foundation

public struct MapVectorPoint: Hashable, Sendable {
    public let longitude: Double
    public let latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }
}

/// One coastline ring or border line, with the bounding box it occupies.
///
/// The box is computed once at parse time so the renderer can reject a ring without
/// touching its vertices. The renderer used to project every vertex of every ring on
/// every frame, whatever was actually on screen.
public struct MapVectorRing: Sendable {
    public let points: [MapVectorPoint]
    public let minimumLatitude: Double
    public let maximumLatitude: Double
    public let minimumLongitude: Double
    public let maximumLongitude: Double

    public init(points: [MapVectorPoint]) {
        self.points = points
        minimumLatitude = points.map(\.latitude).min() ?? 0
        maximumLatitude = points.map(\.latitude).max() ?? 0
        minimumLongitude = points.map(\.longitude).min() ?? 0
        maximumLongitude = points.map(\.longitude).max() ?? 0
    }

    /// Box-on-box overlap. `bounds` may wrap the antimeridian, in which case its
    /// longitude range is two pieces and a ring only has to meet either one.
    public func intersects(_ bounds: PlaceBounds) -> Bool {
        guard maximumLatitude >= bounds.minimumLatitude,
              minimumLatitude <= bounds.maximumLatitude else { return false }
        if bounds.minimumLongitude <= bounds.maximumLongitude {
            return maximumLongitude >= bounds.minimumLongitude
                && minimumLongitude <= bounds.maximumLongitude
        }
        return maximumLongitude >= bounds.minimumLongitude
            || minimumLongitude <= bounds.maximumLongitude
    }
}

/// Simplified Natural Earth 1:110m land and country-border vectors bundled in the
/// core resource bundle. Loading is local and deterministic; no map framework or tile
/// service is involved.
public struct OfflineMapVectorData: Sendable {
    public let landPolygons: [MapVectorRing]
    public let borderLines: [MapVectorRing]

    /// One of the two bundled resources was missing or unparsable, which leaves the
    /// renderer with an empty sea and no coastlines.
    public var didFail: Bool { landPolygons.isEmpty || borderLines.isEmpty }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var cached: OfflineMapVectorData?

    /// Parsed once and kept — failures included. `reload()` is the only way back.
    public static var shared: OfflineMapVectorData {
        lock.withLock {
            if let cached { return cached }
            let value = OfflineMapVectorData(
                landPolygons: load(resource: "ne_110m_land"),
                borderLines: load(resource: "ne_110m_admin_0_boundary_lines_land")
            )
            cached = value
            return value
        }
    }

    /// Drops the parsed copy so the next `shared` re-reads the bundle.
    public static func reload() {
        lock.withLock { cached = nil }
    }

    public func land(intersecting bounds: PlaceBounds) -> [MapVectorRing] {
        landPolygons.filter { $0.intersects(bounds) }
    }

    public func borders(intersecting bounds: PlaceBounds) -> [MapVectorRing] {
        borderLines.filter { $0.intersects(bounds) }
    }

    private static func load(resource: String) -> [MapVectorRing] {
        guard let url = ResourceBundle.url(forResource: resource, withExtension: "geojson"),
              let root = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return [] }
        var result: [MapVectorRing] = []
        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String,
                  let coordinates = geometry["coordinates"] else { continue }
            switch type {
            case "Polygon":
                if let rings = coordinates as? [[[Double]]] { result += rings.compactMap(ring) }
            case "MultiPolygon":
                if let polygons = coordinates as? [[[[Double]]]] {
                    for rings in polygons { result += rings.compactMap(ring) }
                }
            case "LineString":
                if let line = coordinates as? [[Double]], let parsed = ring(line) { result.append(parsed) }
            case "MultiLineString":
                if let lines = coordinates as? [[[Double]]] { result += lines.compactMap(ring) }
            default: break
            }
        }
        return result
    }

    private static func ring(_ values: [[Double]]) -> MapVectorRing? {
        let points = values.compactMap { value -> MapVectorPoint? in
            guard value.count >= 2 else { return nil }
            return MapVectorPoint(longitude: value[0], latitude: value[1])
        }
        return points.count > 1 ? MapVectorRing(points: points) : nil
    }
}
