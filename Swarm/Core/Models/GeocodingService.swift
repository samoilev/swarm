import CoreLocation
import Foundation

/// Fully offline coordinate lookup backed by the same bilingual GeoNames snapshot
/// used by place search and map labels. Free text is never resolved by “first match”:
/// only an exact full address or a globally unique bare name/alias receives a pin.
public final class GeocodingService: @unchecked Sendable {
    public static let shared = GeocodingService()

    private let places = PlacesDatabase.shared
    private let lock = NSLock()
    private var cache: [String: CLLocationCoordinate2D?] = [:]

    public var isReady: Bool { places.isReady }

    public init() {}

    public func whenReady(_ run: @escaping @MainActor () -> Void) {
        places.whenReady(run)
    }

    public func clearCache(for placeName: String) {
        let key = cacheKey(placeName, language: .current)
        _ = lock.withLock { cache.removeValue(forKey: key) }
    }

    public func coordinateSync(
        for placeName: String?,
        language: AppLanguage = .current
    ) -> CLLocationCoordinate2D? {
        guard let placeName,
              !placeName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              places.isReady else { return nil }
        let key = cacheKey(placeName, language: language)
        if let cached = lock.withLock({ cache[key] }) { return cached }

        let entry = places.uniqueEntry(matching: placeName, language: language)
        let coordinate: CLLocationCoordinate2D? = if let latitude = entry?.latitude, let longitude = entry?.longitude {
            CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        } else {
            nil
        }
        lock.withLock { cache[key] = coordinate }
        return coordinate
    }

    /// An explicit picker selection always carries its exact source coordinates.
    public func coordinate(for place: PlaceEntry) -> CLLocationCoordinate2D? {
        guard let latitude = place.latitude, let longitude = place.longitude,
              (-90 ... 90).contains(latitude),
              (-180 ... 180).contains(longitude) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func cacheKey(_ value: String, language: AppLanguage) -> String {
        language.rawValue + "|" + value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: language.locale
            )
            .lowercased(with: language.locale)
            .replacingOccurrences(of: "ё", with: "е")
    }
}
