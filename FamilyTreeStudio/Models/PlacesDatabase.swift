import Foundation

struct PlaceEntry: Identifiable, Hashable {
    let id: Int
    let name: String
    let region: String
    let country: String
    
    var displayName: String {
        if region.isEmpty { return "\(name), \(country)" }
        return "\(name), \(region), \(country)"
    }
}

struct PlacesDatabase {
    static let shared = PlacesDatabase()
    
    private let entries: [(name: String, nameLower: String, region: String, country: String)]
    
    init() {
        entries = Self.loadPlaces()
    }
    
    func search(_ query: String) -> [PlaceEntry] {
        guard query.count >= 2 else { return [] }
        let q = query.lowercased()
        
        var results: [PlaceEntry] = []
        var count = 0
        
        for (i, entry) in entries.enumerated() {
            if entry.nameLower.hasPrefix(q) || entry.nameLower.contains(q) {
                results.append(PlaceEntry(
                    id: i,
                    name: entry.name,
                    region: entry.region,
                    country: entry.country
                ))
                count += 1
                if count >= 15 { break }
            }
        }
        
        // Sort: prefix matches first, then by position in DB (population order)
        results.sort { a, b in
            let aPrefix = a.name.lowercased().hasPrefix(q)
            let bPrefix = b.name.lowercased().hasPrefix(q)
            if aPrefix != bPrefix { return aPrefix }
            return a.id < b.id
        }
        
        return results
    }
    
    private static func loadPlaces() -> [(name: String, nameLower: String, region: String, country: String)] {
        guard let url = Bundle.module.url(forResource: "places", withExtension: "tsv") else {
            print("PlacesDatabase: places.tsv not found in bundle")
            return []
        }
        
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            print("PlacesDatabase: failed to read places.tsv")
            return []
        }
        
        var result: [(name: String, nameLower: String, region: String, country: String)] = []
        result.reserveCapacity(460000)
        
        for line in data.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let name = String(parts[0])
            let region = String(parts[1])
            let country = String(parts[2])
            result.append((name: name, nameLower: name.lowercased(), region: region, country: country))
        }
        
        return result
    }
}
