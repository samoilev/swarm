import CryptoKit
import Foundation
import os

private let log = Logger(subsystem: "com.familytreestudio.app", category: "PlacesDatabase")

public struct PlaceEntry: Identifiable, Hashable {
    public let id: String
    public let name: String
    public let region: String
    public let country: String
    public let latitude: Double?
    public let longitude: Double?
    public let aliases: [String]

    public init(
        id: String,
        name: String,
        region: String,
        country: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        aliases: [String] = []
    ) {
        self.id = id
        self.name = name
        self.region = region
        self.country = country
        self.latitude = latitude
        self.longitude = longitude
        self.aliases = aliases
    }

    public var displayName: String {
        if region.isEmpty { return "\(name), \(country)" }
        return "\(name), \(region), \(country)"
    }

    public var placeReference: PlaceReference {
        PlaceReference(
            datasetID: id,
            displayName: displayName,
            latitude: latitude,
            longitude: longitude,
            isCustom: false
        )
    }
}

public final class PlacesDatabase {
    public static let shared = PlacesDatabase()

    private struct Entry {
        let name: String
        let region: String
        let country: String
        let nameLower: String // normalized name (lowercased, ё→е) — used for ranking
        let haystack: String // normalized "name region country" — used for matching
        let id: String
        let latitude: Double?
        let longitude: Double?
        let aliases: [String]
        let aliasLowers: [String]
    }

    // Read/written on the main thread only (search runs on main; the background
    // load hands the parsed array back via the main queue).
    private var entries: [Entry] = []
    private var ready = false
    private var readyCallbacks: [() -> Void] = []
    private let lock = NSLock()

    public var isReady: Bool { lock.withLock { ready } }

    private init() {
        // ~455k rows — parse off the main thread so opening a form never hangs.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = Self.loadPlaces()
            guard let self else { return }
            let callbacks = self.lock.withLock {
                self.entries = loaded
                self.ready = true
                defer { self.readyCallbacks = [] }
                return self.readyCallbacks
            }
            DispatchQueue.main.async {
                callbacks.forEach { $0() }
            }
        }
    }

    public func whenReady(_ run: @escaping () -> Void) {
        let runNow = lock.withLock {
            if ready { return true }
            readyCallbacks.append(run)
            return false
        }
        if runNow { DispatchQueue.main.async(execute: run) }
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
    public func search(_ query: String) -> [PlaceEntry] {
        let q = Self.normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard q.count >= 2 else { return [] }
        let tokens = q.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        guard let first = tokens.first else { return [] }
        let extra = tokens.dropFirst()

        let searchableEntries = lock.withLock { entries }
        var scored: [(entry: PlaceEntry, score: Int, pos: Int)] = []
        scored.reserveCapacity(400)

        for (i, e) in searchableEntries.enumerated() {
            // The primary token must match the name, region, or country somewhere.
            guard e.haystack.contains(first) else { continue }

            var score = if e.nameLower == first { 1200 }
            else if e.aliasLowers.contains(first) { 1100 }
            else if e.nameLower.hasPrefix(first) { 1000 }
            else if e.aliasLowers.contains(where: { $0.hasPrefix(first) }) { 900 }
            else if e.nameLower.contains(first) { 500 }
            else if e.aliasLowers.contains(where: { $0.contains(first) }) { 450 }
            else { 100 } // matched only via region/country
            for tk in extra where e.haystack.contains(tk) {
                score += 200
            }

            scored.append((PlaceEntry(
                id: e.id,
                name: e.name,
                region: e.region,
                country: e.country,
                latitude: e.latitude,
                longitude: e.longitude,
                aliases: e.aliases
            ), score, i))
            if scored.count >= 400 { break } // perf cap; the sort below keeps the best
        }

        // Higher score first; tie-break by DB position (which is population order).
        scored.sort { $0.score != $1.score ? $0.score > $1.score : $0.pos < $1.pos }
        return scored.prefix(60).map(\.entry)
    }

    private static func loadPlaces() -> [Entry] {
        guard let url = Bundle.module.url(forResource: "places", withExtension: "tsv") else {
            log.error("places.tsv not found in bundle")
            return []
        }

        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            log.error("failed to read places.tsv")
            return []
        }

        let coordinates = loadCoordinates()
        var result = loadV2Places()
        result.reserveCapacity(460_000)
        let v2Keys = Set(result.map { "\($0.nameLower)|\(normalize($0.country))" })

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
            let normalized = normalize(name)
            guard !v2Keys.contains("\(normalized)|\(normalize(country))") else { continue }
            let matches = coordinates[normalized] ?? []
            // A name-only coordinate is safe only when all matching rows agree.
            let uniqueCoordinates = Set(matches.map { "\($0.0),\($0.1)" })
            let coordinate = uniqueCoordinates.count == 1 ? matches.first : nil
            let stableID = stableIDFor(name: name, region: region, country: country, coordinate: coordinate)
            result.append(Entry(
                name: name,
                region: region,
                country: country,
                nameLower: normalized,
                haystack: normalize("\(name) \(region) \(country)"),
                id: stableID,
                latitude: coordinate?.0,
                longitude: coordinate?.1,
                aliases: [],
                aliasLowers: []
            ))
        }

        return result
    }

    /// The v2 snapshot carries original GeoNames identifiers and aliases. The legacy
    /// files remain a compatibility fallback until a complete generated v2 snapshot
    /// replaces them; both are exposed through one in-memory index.
    private static func loadV2Places() -> [Entry] {
        guard let url = Bundle.module.url(forResource: "place_index_v2", withExtension: "tsv"),
              let data = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [Entry] = []
        for line in data.split(separator: "\n").dropFirst() {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 8,
                  let latitude = Double(parts[5]),
                  let longitude = Double(parts[6]) else { continue }
            let id = String(parts[0])
            let name = String(parts[1])
            let aliases = parts[2].split(separator: "|").map(String.init)
            let region = String(parts[3])
            let country = String(parts[4])
            result.append(Entry(
                name: name,
                region: region,
                country: country,
                nameLower: normalize(name),
                haystack: normalize(([name, region, country] + aliases).joined(separator: " ")),
                id: id,
                latitude: latitude,
                longitude: longitude,
                aliases: aliases,
                aliasLowers: aliases.map(normalize)
            ))
        }
        return result
    }

    private static func loadCoordinates() -> [String: [(Double, Double)]] {
        guard let url = Bundle.module.url(forResource: "geonames_ussr", withExtension: "tsv"),
              let data = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var result: [String: [(Double, Double)]] = [:]
        for line in data.split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 2)
            guard parts.count == 3, let latitude = Double(parts[1]), let longitude = Double(parts[2]) else { continue }
            result[normalize(String(parts[0])), default: []].append((latitude, longitude))
        }
        return result
    }

    private static func stableIDFor(
        name: String,
        region: String,
        country: String,
        coordinate: (Double, Double)?
    ) -> String {
        let source = "\(normalize(name))|\(normalize(region))|\(normalize(country))|" +
            "\(coordinate?.0.description ?? "")|\(coordinate?.1.description ?? "")"
        let digest = SHA256.hash(data: Data(source.utf8))
        return "local-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}
