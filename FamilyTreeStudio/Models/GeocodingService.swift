import Foundation
import CoreLocation

/// Geocoding service backed by GeoNames database (252K+ settlements of the former USSR)
/// Falls back to Apple CLGeocoder for places not in the database
class GeocodingService {
    static let shared = GeocodingService()
    
    private var cache: [String: CLLocationCoordinate2D] = [:]
    private let geocoder = CLGeocoder()
    
    /// GeoNames-sourced coordinates loaded from bundled TSV (name\tlat\tlon)
    private let knownPlaces: [String: CLLocationCoordinate2D]
    
    init() {
        knownPlaces = Self.loadGeoNames()
    }
    
    private static func loadGeoNames() -> [String: CLLocationCoordinate2D] {
        guard let url = Bundle.module.url(forResource: "geonames_ussr", withExtension: "tsv") else {
            print("GeocodingService: geonames_ussr.tsv not found in bundle")
            return [:]
        }
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            print("GeocodingService: failed to read geonames_ussr.tsv")
            return [:]
        }
        
        var result: [String: CLLocationCoordinate2D] = [:]
        result.reserveCapacity(260000)
        
        for line in data.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3,
                  let lat = Double(parts[1]),
                  let lon = Double(parts[2]) else { continue }
            let name = String(parts[0])
            result[name] = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        
        // Add historical name aliases not in GeoNames
        let aliases: [(String, String)] = [
            ("ленинград", "санкт-петербург"),
            ("петроград", "санкт-петербург"),
            ("свердловск", "екатеринбург"),
            ("горький", "нижний новгород"),
            ("куйбышев", "самара"),
            ("сталинград", "волгоград"),
            ("калинин", "тверь"),
            ("нур-султан", "астана"),
        ]
        for (alias, canonical) in aliases {
            if let coord = result[canonical], result[alias] == nil {
                result[alias] = coord
            }
        }
        
        print("GeocodingService: loaded \(result.count) places from GeoNames")
        return result
    }
    
    func coordinate(for placeName: String?, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        guard let place = placeName, !place.isEmpty else {
            completion(nil)
            return
        }
        
        let key = place.lowercased().trimmingCharacters(in: .whitespaces)
        
        // Check cache
        if let cached = cache[key] {
            completion(cached)
            return
        }
        
        // Try lookup in GeoNames database
        if let coord = lookupInDatabase(key) {
            cache[key] = coord
            completion(coord)
            return
        }
        
        // Fallback to CLGeocoder
        geocoder.geocodeAddressString(place) { [weak self] placemarks, _ in
            if let location = placemarks?.first?.location?.coordinate {
                self?.cache[key] = location
                completion(location)
            } else {
                completion(nil)
            }
        }
    }
    
    /// Synchronous lookup for known places only
    func coordinateSync(for placeName: String?) -> CLLocationCoordinate2D? {
        guard let place = placeName, !place.isEmpty else { return nil }
        let key = place.lowercased().trimmingCharacters(in: .whitespaces)
        
        if let cached = cache[key] { return cached }
        
        if let coord = lookupInDatabase(key) {
            cache[key] = coord
            return coord
        }
        return nil
    }
    
    /// Try various strategies to find the place name in the database
    private func lookupInDatabase(_ key: String) -> CLLocationCoordinate2D? {
        // Direct match
        if let coord = knownPlaces[key] { return coord }
        
        // Try each comma-separated part (e.g. "Витебск, Беларусь" -> try "витебск")
        let parts = key.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            if let coord = knownPlaces[part] { return coord }
        }
        
        // Try with ё/е normalization
        let normalized = key.replacingOccurrences(of: "ё", with: "е")
        if normalized != key, let coord = knownPlaces[normalized] { return coord }
        
        return nil
    }
}
