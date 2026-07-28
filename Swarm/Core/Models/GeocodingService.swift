import CoreLocation
import Foundation
import os

private let log = Logger(subsystem: "com.samoilev.swarm", category: "Geocoding")

/// Fully offline geocoding, backed solely by the bundled GeoNames database
/// (252K+ settlements of the former USSR). Place names never leave the device —
/// a place absent from the database resolves to nil (no map pin).
public final class GeocodingService {
    public static let shared = GeocodingService()

    private var cache: [String: CLLocationCoordinate2D] = [:]

    /// GeoNames-sourced coordinates loaded from bundled TSV (name\tlat\tlon)
    private var knownPlaces: [String: CLLocationCoordinate2D] = [:]
    public private(set) var isReady = false
    private var readyCallbacks: [() -> Void] = []

    init() {
        // ~252k rows — load off the main thread so opening the map never hangs.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = Self.loadGeoNames()
            DispatchQueue.main.async {
                guard let self else { return }
                self.knownPlaces = loaded
                self.isReady = true
                let callbacks = self.readyCallbacks
                self.readyCallbacks = []
                callbacks.forEach { $0() }
            }
        }
    }

    /// Runs `run` once the GeoNames DB is loaded (immediately if already loaded).
    /// Callers that geocode in bulk should gate on this so places that are in the
    /// (not-yet-loaded) database don't prematurely resolve to nil.
    public func whenReady(_ run: @escaping () -> Void) {
        if isReady { run() } else { readyCallbacks.append(run) }
    }

    private static func loadGeoNames() -> [String: CLLocationCoordinate2D] {
        guard let url = ResourceBundle.core.url(forResource: "geonames_ussr", withExtension: "tsv") else {
            log.error("geonames_ussr.tsv not found in bundle")
            return [:]
        }
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            log.error("failed to read geonames_ussr.tsv")
            return [:]
        }

        var result: [String: CLLocationCoordinate2D] = [:]
        result.reserveCapacity(260_000)

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

        log.notice("loaded \(result.count) places from GeoNames")
        return result
    }

    /// Remove a place from the in-memory cache so the next lookup re-geocodes it.
    public func clearCache(for placeName: String) {
        let key = placeName.lowercased().trimmingCharacters(in: .whitespaces)
        cache.removeValue(forKey: key)
    }

    /// Synchronous lookup for known places only
    public func coordinateSync(for placeName: String?) -> CLLocationCoordinate2D? {
        guard let place = placeName, !place.isEmpty else { return nil }
        let key = place.lowercased().trimmingCharacters(in: .whitespaces)

        if let cached = cache[key] { return cached }

        if let coord = lookupInDatabase(key) {
            cache[key] = coord
            return coord
        }
        return nil
    }

    /// Coordinate lookup for an explicit place selection. No display-string parsing or
    /// ambiguity guessing is involved.
    public func coordinate(for place: PlaceEntry) -> CLLocationCoordinate2D? {
        guard let latitude = place.latitude, let longitude = place.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Try various strategies to find the place name in the database.
    private func lookupInDatabase(_ key: String) -> CLLocationCoordinate2D? {
        // Direct match on the full string (works for single city names in GeoNames).
        if let coord = knownPlaces[key] { return coord }

        // ё/е normalization of the full key.
        let normalized = key.replacingOccurrences(of: "ё", with: "е")
        if normalized != key, let coord = knownPlaces[normalized] { return coord }

        // A multi-part address like "Зарубино, Новгородская обл., Россия" is left
        // unpinned rather than guessed: stripping the region would return the first
        // city of that name in the DB (e.g. the Far-East Зарубино, not the Novgorod
        // one). Single-name inputs were already matched by the exact lookups above.
        return nil
    }
}
