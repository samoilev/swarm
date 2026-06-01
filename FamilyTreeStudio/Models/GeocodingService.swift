import Foundation
import CoreLocation

/// Lightweight geocoding service with built-in coordinate dictionary for common ex-USSR cities
/// Falls back to Apple CLGeocoder for unknown places
class GeocodingService {
    static let shared = GeocodingService()
    
    private var cache: [String: CLLocationCoordinate2D] = [:]
    private let geocoder = CLGeocoder()
    
    /// Known city coordinates (ex-USSR region focus)
    private let knownCities: [String: CLLocationCoordinate2D] = [
        // Russia
        "москва": CLLocationCoordinate2D(latitude: 55.7558, longitude: 37.6173),
        "санкт-петербург": CLLocationCoordinate2D(latitude: 59.9343, longitude: 30.3351),
        "ленинград": CLLocationCoordinate2D(latitude: 59.9343, longitude: 30.3351),
        "петроград": CLLocationCoordinate2D(latitude: 59.9343, longitude: 30.3351),
        "новосибирск": CLLocationCoordinate2D(latitude: 55.0084, longitude: 82.9357),
        "екатеринбург": CLLocationCoordinate2D(latitude: 56.8389, longitude: 60.6057),
        "свердловск": CLLocationCoordinate2D(latitude: 56.8389, longitude: 60.6057),
        "казань": CLLocationCoordinate2D(latitude: 55.7887, longitude: 49.1221),
        "нижний новгород": CLLocationCoordinate2D(latitude: 56.2965, longitude: 43.9361),
        "горький": CLLocationCoordinate2D(latitude: 56.2965, longitude: 43.9361),
        "самара": CLLocationCoordinate2D(latitude: 53.1959, longitude: 50.1002),
        "куйбышев": CLLocationCoordinate2D(latitude: 53.1959, longitude: 50.1002),
        "ростов-на-дону": CLLocationCoordinate2D(latitude: 47.2357, longitude: 39.7015),
        "волгоград": CLLocationCoordinate2D(latitude: 48.7080, longitude: 44.5133),
        "сталинград": CLLocationCoordinate2D(latitude: 48.7080, longitude: 44.5133),
        "пермь": CLLocationCoordinate2D(latitude: 58.0105, longitude: 56.2502),
        "воронеж": CLLocationCoordinate2D(latitude: 51.6720, longitude: 39.1843),
        "красноярск": CLLocationCoordinate2D(latitude: 56.0153, longitude: 92.8932),
        "саратов": CLLocationCoordinate2D(latitude: 51.5462, longitude: 46.0154),
        "краснодар": CLLocationCoordinate2D(latitude: 45.0355, longitude: 38.9753),
        "тула": CLLocationCoordinate2D(latitude: 54.1930, longitude: 37.6179),
        "омск": CLLocationCoordinate2D(latitude: 54.9885, longitude: 73.3242),
        "челябинск": CLLocationCoordinate2D(latitude: 55.1644, longitude: 61.4368),
        "уфа": CLLocationCoordinate2D(latitude: 54.7388, longitude: 55.9721),
        "владивосток": CLLocationCoordinate2D(latitude: 43.1198, longitude: 131.8869),
        "иркутск": CLLocationCoordinate2D(latitude: 52.2978, longitude: 104.2964),
        "хабаровск": CLLocationCoordinate2D(latitude: 48.4827, longitude: 135.0837),
        "ярославль": CLLocationCoordinate2D(latitude: 57.6261, longitude: 39.8845),
        "тверь": CLLocationCoordinate2D(latitude: 56.8587, longitude: 35.9176),
        "калинин": CLLocationCoordinate2D(latitude: 56.8587, longitude: 35.9176),
        "рязань": CLLocationCoordinate2D(latitude: 54.6296, longitude: 39.7316),
        "смоленск": CLLocationCoordinate2D(latitude: 54.7826, longitude: 32.0453),
        "курск": CLLocationCoordinate2D(latitude: 51.7304, longitude: 36.1926),
        "орёл": CLLocationCoordinate2D(latitude: 52.9651, longitude: 36.0785),
        "брянск": CLLocationCoordinate2D(latitude: 53.2521, longitude: 34.3717),
        "архангельск": CLLocationCoordinate2D(latitude: 64.5399, longitude: 40.5152),
        "мурманск": CLLocationCoordinate2D(latitude: 68.9585, longitude: 33.0827),
        "калининград": CLLocationCoordinate2D(latitude: 54.7104, longitude: 20.4522),
        "сочи": CLLocationCoordinate2D(latitude: 43.6028, longitude: 39.7342),
        "томск": CLLocationCoordinate2D(latitude: 56.4977, longitude: 84.9744),
        "барнаул": CLLocationCoordinate2D(latitude: 53.3548, longitude: 83.7698),
        "тюмень": CLLocationCoordinate2D(latitude: 57.1553, longitude: 65.5619),
        "пенза": CLLocationCoordinate2D(latitude: 53.1959, longitude: 45.0183),
        "липецк": CLLocationCoordinate2D(latitude: 52.6031, longitude: 39.5708),
        "тамбов": CLLocationCoordinate2D(latitude: 52.7317, longitude: 41.4433),
        "астрахань": CLLocationCoordinate2D(latitude: 46.3497, longitude: 48.0408),
        "калуга": CLLocationCoordinate2D(latitude: 54.5293, longitude: 36.2754),
        "владимир": CLLocationCoordinate2D(latitude: 56.1291, longitude: 40.4069),
        "кострома": CLLocationCoordinate2D(latitude: 57.7677, longitude: 40.9269),
        "иваново": CLLocationCoordinate2D(latitude: 57.0004, longitude: 40.9739),
        "вологда": CLLocationCoordinate2D(latitude: 59.2181, longitude: 39.8914),
        "новгород": CLLocationCoordinate2D(latitude: 58.5228, longitude: 31.2748),
        "псков": CLLocationCoordinate2D(latitude: 57.8136, longitude: 28.3496),
        "петрозаводск": CLLocationCoordinate2D(latitude: 61.7849, longitude: 34.3469),
        // Ukraine
        "киев": CLLocationCoordinate2D(latitude: 50.4501, longitude: 30.5234),
        "харьков": CLLocationCoordinate2D(latitude: 49.9935, longitude: 36.2304),
        "одесса": CLLocationCoordinate2D(latitude: 46.4825, longitude: 30.7233),
        "днепропетровск": CLLocationCoordinate2D(latitude: 48.4647, longitude: 35.0462),
        "днепр": CLLocationCoordinate2D(latitude: 48.4647, longitude: 35.0462),
        "донецк": CLLocationCoordinate2D(latitude: 48.0159, longitude: 37.8028),
        "запорожье": CLLocationCoordinate2D(latitude: 47.8388, longitude: 35.1396),
        "львов": CLLocationCoordinate2D(latitude: 49.8397, longitude: 24.0297),
        "кривой рог": CLLocationCoordinate2D(latitude: 47.9105, longitude: 33.3918),
        "николаев": CLLocationCoordinate2D(latitude: 46.9750, longitude: 31.9946),
        "херсон": CLLocationCoordinate2D(latitude: 46.6354, longitude: 32.6169),
        "полтава": CLLocationCoordinate2D(latitude: 49.5883, longitude: 34.5514),
        "чернигов": CLLocationCoordinate2D(latitude: 51.4982, longitude: 31.2893),
        "винница": CLLocationCoordinate2D(latitude: 49.2328, longitude: 28.4816),
        "житомир": CLLocationCoordinate2D(latitude: 50.2547, longitude: 28.6587),
        // Belarus
        "минск": CLLocationCoordinate2D(latitude: 53.9006, longitude: 27.5590),
        "гомель": CLLocationCoordinate2D(latitude: 52.4345, longitude: 30.9754),
        "могилёв": CLLocationCoordinate2D(latitude: 53.9045, longitude: 30.3449),
        "витебск": CLLocationCoordinate2D(latitude: 55.1904, longitude: 30.2049),
        "гродно": CLLocationCoordinate2D(latitude: 53.6884, longitude: 23.8258),
        "брест": CLLocationCoordinate2D(latitude: 52.0976, longitude: 23.7341),
        // Belarus — districts & small towns
        "орша": CLLocationCoordinate2D(latitude: 54.5081, longitude: 30.4172),
        "полоцк": CLLocationCoordinate2D(latitude: 55.4879, longitude: 28.7856),
        "новополоцк": CLLocationCoordinate2D(latitude: 55.5318, longitude: 28.6489),
        "бобруйск": CLLocationCoordinate2D(latitude: 53.1384, longitude: 29.2214),
        "барановичи": CLLocationCoordinate2D(latitude: 53.1327, longitude: 26.0139),
        "борисов": CLLocationCoordinate2D(latitude: 54.2279, longitude: 28.5050),
        "пинск": CLLocationCoordinate2D(latitude: 52.1115, longitude: 26.1032),
        "мозырь": CLLocationCoordinate2D(latitude: 52.0483, longitude: 29.2455),
        "солигорск": CLLocationCoordinate2D(latitude: 52.7909, longitude: 27.5407),
        "молодечно": CLLocationCoordinate2D(latitude: 54.3075, longitude: 26.8542),
        "лида": CLLocationCoordinate2D(latitude: 53.8833, longitude: 25.2997),
        "жлобин": CLLocationCoordinate2D(latitude: 52.8917, longitude: 30.0244),
        "жодино": CLLocationCoordinate2D(latitude: 54.0971, longitude: 28.3353),
        "слуцк": CLLocationCoordinate2D(latitude: 53.0254, longitude: 27.5597),
        "речица": CLLocationCoordinate2D(latitude: 52.3617, longitude: 30.3933),
        "светлогорск": CLLocationCoordinate2D(latitude: 52.6267, longitude: 29.7350),
        "рогачёв": CLLocationCoordinate2D(latitude: 53.0876, longitude: 30.0489),
        "рогачев": CLLocationCoordinate2D(latitude: 53.0876, longitude: 30.0489),
        "кобрин": CLLocationCoordinate2D(latitude: 52.2142, longitude: 24.3564),
        "слоним": CLLocationCoordinate2D(latitude: 53.0900, longitude: 25.3167),
        "волковыск": CLLocationCoordinate2D(latitude: 53.1567, longitude: 24.4553),
        "калинковичи": CLLocationCoordinate2D(latitude: 52.1283, longitude: 29.3267),
        "сморгонь": CLLocationCoordinate2D(latitude: 54.4783, longitude: 26.3986),
        "осиповичи": CLLocationCoordinate2D(latitude: 53.3008, longitude: 28.6358),
        "новогрудок": CLLocationCoordinate2D(latitude: 53.5942, longitude: 25.8264),
        "горки": CLLocationCoordinate2D(latitude: 54.2833, longitude: 30.9833),
        "лепель": CLLocationCoordinate2D(latitude: 54.8822, longitude: 28.7006),
        "глубокое": CLLocationCoordinate2D(latitude: 55.1383, longitude: 27.6917),
        "поставы": CLLocationCoordinate2D(latitude: 55.1117, longitude: 26.8350),
        "докшицы": CLLocationCoordinate2D(latitude: 54.8917, longitude: 27.7667),
        "толочин": CLLocationCoordinate2D(latitude: 54.4117, longitude: 29.6933),
        "дубровно": CLLocationCoordinate2D(latitude: 54.5667, longitude: 30.6833),
        "сенно": CLLocationCoordinate2D(latitude: 54.8100, longitude: 29.7050),
        "чашники": CLLocationCoordinate2D(latitude: 54.8567, longitude: 29.1667),
        "городок": CLLocationCoordinate2D(latitude: 55.4617, longitude: 29.9833),
        "верхнедвинск": CLLocationCoordinate2D(latitude: 55.7783, longitude: 27.9367),
        "браслав": CLLocationCoordinate2D(latitude: 55.6417, longitude: 27.0417),
        "миоры": CLLocationCoordinate2D(latitude: 55.6217, longitude: 27.6283),
        "шарковщина": CLLocationCoordinate2D(latitude: 55.3667, longitude: 27.4667),
        "ушачи": CLLocationCoordinate2D(latitude: 55.1750, longitude: 28.6167),
        "россоны": CLLocationCoordinate2D(latitude: 55.9083, longitude: 28.7917),
        "бешенковичи": CLLocationCoordinate2D(latitude: 55.0383, longitude: 29.4617),
        "шумилино": CLLocationCoordinate2D(latitude: 55.3000, longitude: 29.6167),
        "лиозно": CLLocationCoordinate2D(latitude: 55.0217, longitude: 30.7917),
        "черные": CLLocationCoordinate2D(latitude: 55.2000, longitude: 29.2833),
        // Georgia
        "тбилиси": CLLocationCoordinate2D(latitude: 41.7151, longitude: 44.8271),
        "батуми": CLLocationCoordinate2D(latitude: 41.6168, longitude: 41.6367),
        "кутаиси": CLLocationCoordinate2D(latitude: 42.2679, longitude: 42.6946),
        // Armenia
        "ереван": CLLocationCoordinate2D(latitude: 40.1792, longitude: 44.4991),
        // Azerbaijan
        "баку": CLLocationCoordinate2D(latitude: 40.4093, longitude: 49.8671),
        // Kazakhstan
        "алма-ата": CLLocationCoordinate2D(latitude: 43.2220, longitude: 76.8512),
        "алматы": CLLocationCoordinate2D(latitude: 43.2220, longitude: 76.8512),
        "астана": CLLocationCoordinate2D(latitude: 51.1694, longitude: 71.4491),
        "нур-султан": CLLocationCoordinate2D(latitude: 51.1694, longitude: 71.4491),
        "караганда": CLLocationCoordinate2D(latitude: 49.8047, longitude: 73.1094),
        // Uzbekistan
        "ташкент": CLLocationCoordinate2D(latitude: 41.2995, longitude: 69.2401),
        "самарканд": CLLocationCoordinate2D(latitude: 39.6542, longitude: 66.9597),
        "бухара": CLLocationCoordinate2D(latitude: 39.7745, longitude: 64.4286),
        // Moldova
        "кишинёв": CLLocationCoordinate2D(latitude: 47.0105, longitude: 28.8638),
        "кишинев": CLLocationCoordinate2D(latitude: 47.0105, longitude: 28.8638),
        // Baltic
        "рига": CLLocationCoordinate2D(latitude: 56.9496, longitude: 24.1052),
        "таллин": CLLocationCoordinate2D(latitude: 59.4370, longitude: 24.7536),
        "вильнюс": CLLocationCoordinate2D(latitude: 54.6872, longitude: 25.2797),
        // Other
        "берлин": CLLocationCoordinate2D(latitude: 52.5200, longitude: 13.4050),
        "варшава": CLLocationCoordinate2D(latitude: 52.2297, longitude: 21.0122),
        "прага": CLLocationCoordinate2D(latitude: 50.0755, longitude: 14.4378),
        "тель-авив": CLLocationCoordinate2D(latitude: 32.0853, longitude: 34.7818),
        "нью-йорк": CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
    ]
    
    func coordinate(for placeName: String?, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        guard let place = placeName, !place.isEmpty else {
            completion(nil)
            return
        }
        
        // Check cache
        let key = place.lowercased().trimmingCharacters(in: .whitespaces)
        if let cached = cache[key] {
            completion(cached)
            return
        }
        
        // Check known cities — try the first word (city name) from compound place strings
        let parts = key.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            if let coord = knownCities[part] {
                cache[key] = coord
                completion(coord)
                return
            }
        }
        // Try full key
        if let coord = knownCities[key] {
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
    
    /// Synchronous lookup for known cities only
    func coordinateSync(for placeName: String?) -> CLLocationCoordinate2D? {
        guard let place = placeName, !place.isEmpty else { return nil }
        let key = place.lowercased().trimmingCharacters(in: .whitespaces)
        
        if let cached = cache[key] { return cached }
        
        let parts = key.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        for part in parts {
            if let coord = knownCities[part] {
                cache[key] = coord
                return coord
            }
        }
        if let coord = knownCities[key] {
            cache[key] = coord
            return coord
        }
        return nil
    }
}
