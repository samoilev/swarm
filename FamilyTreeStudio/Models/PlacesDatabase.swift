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

final class PlacesDatabase {
    static let shared = PlacesDatabase()

    private struct Entry {
        let name: String
        let region: String
        let country: String
        let nameLower: String   // normalized name (lowercased, ё→е) — used for ranking
        let haystack: String    // normalized "name region country" — used for matching
    }

    // Read/written on the main thread only (search runs on main; the background
    // load hands the parsed array back via the main queue).
    private var entries: [Entry] = []
    private(set) var isReady = false

    private init() {
        // ~455k rows — parse off the main thread so opening a form never hangs.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = Self.loadPlaces()
            DispatchQueue.main.async {
                self?.entries = loaded
                self?.isReady = true
            }
        }
    }

    /// Lowercase and fold ё→е so search is case- and ё-insensitive.
    private static func normalize(_ s: String) -> String {
        s.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    /// True if the string contains any Latin-script letter — i.e. an anglicism /
    /// transliteration we don't want surfacing in an address.
    private static func hasLatin(_ s: String) -> Bool {
        s.contains { $0.isASCII && $0.isLetter }
    }

    /// Search by settlement name, region, or country. The query is split into tokens
    /// (on spaces/commas); the first token must appear somewhere in the entry and the
    /// rest add a ranking bonus. Matches are ordered name-prefix → name-substring →
    /// region/country-only, then by population. Returns up to 60 ranked results.
    func search(_ query: String) -> [PlaceEntry] {
        let q = Self.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard q.count >= 2 else { return [] }
        let tokens = q.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard let first = tokens.first else { return [] }
        let extra = tokens.dropFirst()

        var scored: [(entry: PlaceEntry, score: Int, pos: Int)] = []
        scored.reserveCapacity(400)

        for (i, e) in entries.enumerated() {
            // The primary token must match the name, region, or country somewhere.
            guard e.haystack.contains(first) else { continue }

            var score: Int
            if e.nameLower.hasPrefix(first) { score = 1000 }       // best: name starts with it
            else if e.nameLower.contains(first) { score = 500 }    // name contains it
            else { score = 100 }                                   // matched only via region/country
            for tk in extra where e.haystack.contains(tk) { score += 200 }

            scored.append((PlaceEntry(id: i, name: e.name, region: e.region, country: e.country), score, i))
            if scored.count >= 400 { break } // perf cap; the sort below keeps the best
        }

        // Higher score first; tie-break by DB position (which is population order).
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.pos < $1.pos }
        return scored.prefix(60).map(\.entry)
    }

    private static func loadPlaces() -> [Entry] {
        guard let url = Bundle.module.url(forResource: "places", withExtension: "tsv") else {
            print("PlacesDatabase: places.tsv not found in bundle")
            return []
        }

        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            print("PlacesDatabase: failed to read places.tsv")
            return []
        }

        var result: [Entry] = []
        result.reserveCapacity(460000)

        for line in data.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let name = String(parts[0])
            // A Latin-script (transliterated/English) name can't form a Cyrillic
            // address, so drop the entry entirely — it should never be suggested.
            if hasLatin(name) { continue }
            // Drop a transliterated/English region (e.g. "Zabaykalskiy (Transbaikal)
            // Kray") so it never leaks into an address; keep the clean name + country.
            var region = String(parts[1])
            if hasLatin(region) { region = "" }
            let country = String(parts[2])
            result.append(Entry(
                name: name,
                region: region,
                country: country,
                nameLower: normalize(name),
                haystack: normalize("\(name) \(region) \(country)")
            ))
        }

        return result
    }
}
