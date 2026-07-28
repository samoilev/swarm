import Foundation

public struct MapVectorPoint: Hashable, Sendable {
    public let longitude: Double
    public let latitude: Double

    public init(longitude: Double, latitude: Double) {
        self.longitude = longitude
        self.latitude = latitude
    }
}

/// Simplified Natural Earth 1:110m land and country-border vectors bundled in the
/// core resource bundle. Loading is local and deterministic; no map framework or tile
/// service is involved.
public struct OfflineMapVectorData: Sendable {
    public let landPolygons: [[MapVectorPoint]]
    public let borderLines: [[MapVectorPoint]]

    public static let shared = OfflineMapVectorData(
        landPolygons: load(resource: "ne_110m_land"),
        borderLines: load(resource: "ne_110m_admin_0_boundary_lines_land")
    )

    private static func load(resource: String) -> [[MapVectorPoint]] {
        guard let url = ResourceBundle.core.url(forResource: resource, withExtension: "geojson"),
              let root = try? JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              let features = root["features"] as? [[String: Any]] else { return [] }
        var result: [[MapVectorPoint]] = []
        for feature in features {
            guard let geometry = feature["geometry"] as? [String: Any],
                  let type = geometry["type"] as? String,
                  let coordinates = geometry["coordinates"] else { continue }
            switch type {
            case "Polygon":
                if let rings = coordinates as? [[[Double]]] { result += rings.compactMap(points) }
            case "MultiPolygon":
                if let polygons = coordinates as? [[[[Double]]]] {
                    for rings in polygons { result += rings.compactMap(points) }
                }
            case "LineString":
                if let line = coordinates as? [[Double]], let parsed = points(line) { result.append(parsed) }
            case "MultiLineString":
                if let lines = coordinates as? [[[Double]]] { result += lines.compactMap(points) }
            default: break
            }
        }
        return result
    }

    private static func points(_ values: [[Double]]) -> [MapVectorPoint]? {
        let result = values.compactMap { value -> MapVectorPoint? in
            guard value.count >= 2 else { return nil }
            return MapVectorPoint(longitude: value[0], latitude: value[1])
        }
        return result.count > 1 ? result : nil
    }
}
