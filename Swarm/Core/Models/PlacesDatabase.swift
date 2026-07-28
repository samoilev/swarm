import Foundation
import os

private let log = Logger(subsystem: "com.samoilev.swarm", category: "PlacesDatabase")

public struct PlaceEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let featureCode: String
    public let population: Int
    public let nameRu: String
    public let nameEn: String
    public let nameLocal: String
    public let aliases: [String]
    public let regionRu: String
    public let regionEn: String
    public let countryRu: String
    public let countryEn: String
    public let countryCode: String
    public let continentCode: String
    public let latitude: Double?
    public let longitude: Double?
    public let datasetVersion: String

    public init(
        id: String,
        featureCode: String = "PPL",
        population: Int = 0,
        nameRu: String,
        nameEn: String,
        nameLocal: String = "",
        aliases: [String] = [],
        regionRu: String = "",
        regionEn: String = "",
        countryRu: String,
        countryEn: String,
        countryCode: String = "",
        continentCode: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        datasetVersion: String = ""
    ) {
        self.id = id
        self.featureCode = featureCode
        self.population = population
        self.nameRu = nameRu
        self.nameEn = nameEn
        self.nameLocal = nameLocal
        self.aliases = aliases
        self.regionRu = regionRu
        self.regionEn = regionEn
        self.countryRu = countryRu
        self.countryEn = countryEn
        self.countryCode = countryCode
        self.continentCode = continentCode
        self.latitude = latitude
        self.longitude = longitude
        self.datasetVersion = datasetVersion
    }

    /// Compatibility initializer for callers that construct a local fixture.
    public init(
        id: String,
        name: String,
        region: String,
        country: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        aliases: [String] = []
    ) {
        self.init(
            id: id,
            nameRu: name,
            nameEn: name,
            nameLocal: name,
            aliases: aliases,
            regionRu: region,
            regionEn: region,
            countryRu: country,
            countryEn: country,
            latitude: latitude,
            longitude: longitude
        )
    }

    public func name(language: AppLanguage) -> String {
        preferred(language == .english ? nameEn : nameRu, fallback: nameLocal)
    }

    public func region(language: AppLanguage) -> String {
        preferred(language == .english ? regionEn : regionRu, fallback: "")
    }

    public func country(language: AppLanguage) -> String {
        preferred(language == .english ? countryEn : countryRu, fallback: countryCode)
    }

    public func displayName(language: AppLanguage) -> String {
        [name(language: language), region(language: language), country(language: language)]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    public var name: String { name(language: .current) }
    public var region: String { region(language: .current) }
    public var country: String { country(language: .current) }
    public var displayName: String { displayName(language: .current) }

    public func placeReference(language: AppLanguage = .current) -> PlaceReference {
        PlaceReference(
            datasetID: id,
            displayName: displayName(language: language),
            latitude: latitude,
            longitude: longitude,
            isCustom: false
        )
    }

    public var placeReference: PlaceReference { placeReference() }

    private func preferred(_ value: String, fallback: String) -> String {
        value.isEmpty ? fallback : value
    }
}

public enum PlaceLabelTier: CaseIterable, Hashable, Sendable {
    case world
    case regional
    case city
    case close

    public var maximumLabels: Int {
        switch self {
        case .world: 30
        case .regional: 60
        case .city: 120
        case .close: 200
        }
    }
}

public struct PlaceBounds: Hashable, Sendable {
    public let minimumLatitude: Double
    public let maximumLatitude: Double
    public let minimumLongitude: Double
    public let maximumLongitude: Double

    public init(
        minimumLatitude: Double,
        maximumLatitude: Double,
        minimumLongitude: Double,
        maximumLongitude: Double
    ) {
        self.minimumLatitude = minimumLatitude
        self.maximumLatitude = maximumLatitude
        self.minimumLongitude = minimumLongitude
        self.maximumLongitude = maximumLongitude
    }

    fileprivate func contains(latitude: Double, longitude: Double) -> Bool {
        guard (minimumLatitude ... maximumLatitude).contains(latitude) else { return false }
        if minimumLongitude <= maximumLongitude {
            return (minimumLongitude ... maximumLongitude).contains(longitude)
        }
        return longitude >= minimumLongitude || longitude <= maximumLongitude
    }
}

public final class PlacesDatabase: @unchecked Sendable {
    public static let shared = PlacesDatabase()

    private struct IndexedEntry: Sendable {
        let place: PlaceEntry
        let ruName: String
        let enName: String
        let localName: String
        let aliasNames: [String]
        let haystack: String
        let fullAddressRu: String
        let fullAddressEn: String
    }

    private struct LoadedIndex: Sendable {
        let entries: [IndexedEntry]
        let byID: [String: Int]
        let uniqueBareNames: [String: Int]
        let fullAddresses: [String: Int]
        let spatialBuckets: [Int: [Int]]
        let searchPrefixes: [String: [Int]]
        let labelCandidates: [PlaceLabelTier: [Int]]
        let versions: Set<String>
    }

    private let lock = NSLock()
    private var entries: [IndexedEntry] = []
    private var byID: [String: Int] = [:]
    private var uniqueBareNames: [String: Int] = [:]
    private var fullAddresses: [String: Int] = [:]
    private var spatialBuckets: [Int: [Int]] = [:]
    private var searchPrefixes: [String: [Int]] = [:]
    private var labelCandidates: [PlaceLabelTier: [Int]] = [:]
    private var versions: Set<String> = []
    private var ready = false
    private var readyCallbacks: [@MainActor () -> Void] = []

    public var isReady: Bool { lock.withLock { ready } }
    public var count: Int { lock.withLock { entries.count } }
    public var datasetVersions: Set<String> { lock.withLock { versions } }

    private init() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let loaded = Self.loadPlaces()
            guard let self else { return }
            let callbacks = self.lock.withLock {
                self.entries = loaded.entries
                self.byID = loaded.byID
                self.uniqueBareNames = loaded.uniqueBareNames
                self.fullAddresses = loaded.fullAddresses
                self.spatialBuckets = loaded.spatialBuckets
                self.searchPrefixes = loaded.searchPrefixes
                self.labelCandidates = loaded.labelCandidates
                self.versions = loaded.versions
                self.ready = true
                defer { self.readyCallbacks = [] }
                return self.readyCallbacks
            }
            DispatchQueue.main.async { callbacks.forEach { $0() } }
        }
    }

    public func whenReady(_ run: @escaping @MainActor () -> Void) {
        let runNow = lock.withLock {
            if ready { return true }
            readyCallbacks.append(run)
            return false
        }
        if runNow { DispatchQueue.main.async(execute: run) }
    }

    public func entry(id: String) -> PlaceEntry? {
        lock.withLock {
            guard let index = byID[id], entries.indices.contains(index) else { return nil }
            return entries[index].place
        }
    }

    public func presentationName(
        for reference: PlaceReference,
        language: AppLanguage = .current
    ) -> String {
        guard !reference.isCustom,
              let id = reference.datasetID,
              let entry = entry(id: id) else {
            return reference.displayName
        }
        return entry.displayName(language: language)
    }

    /// Search every matching row, then rank by match quality, population, and stable
    /// GeoNames ID. There is deliberately no early match cutoff: common names such as
    /// Springfield must not hide a more populous or exact full-address match later.
    public func search(
        _ query: String,
        language: AppLanguage = .current,
        limit: Int = 60
    ) -> [PlaceEntry] {
        let normalizedQuery = Self.normalize(query, language: language)
        guard normalizedQuery.count >= 2 else { return [] }
        let tokens = normalizedQuery
            .split(whereSeparator: { $0 == " " || $0 == "," })
            .map(String.init)
        guard let first = tokens.first else { return [] }

        let snapshot: ([IndexedEntry], [Int]) = lock.withLock {
            let prefix = Self.prefixKey(first)
            return (entries, searchPrefixes[prefix] ?? Array(entries.indices))
        }
        var scored: [(index: Int, score: Int)] = []
        scored.reserveCapacity(min(2_000, snapshot.1.count))

        for index in snapshot.1 {
            guard snapshot.0.indices.contains(index) else { continue }
            let entry = snapshot.0[index]
            guard entry.haystack.contains(first) else { continue }
            let localizedName = language == .english ? entry.enName : entry.ruName
            var score: Int
            if normalizedQuery == (language == .english ? entry.fullAddressEn : entry.fullAddressRu) {
                score = 2_000
            } else if localizedName == first {
                score = 1_500
            } else if entry.aliasNames.contains(first) || entry.localName == first {
                score = 1_400
            } else if localizedName.hasPrefix(first) {
                score = 1_200
            } else if entry.aliasNames.contains(where: { $0.hasPrefix(first) }) {
                score = 1_100
            } else if localizedName.contains(first) {
                score = 700
            } else if entry.aliasNames.contains(where: { $0.contains(first) }) {
                score = 650
            } else {
                score = 200
            }
            for token in tokens.dropFirst() where entry.haystack.contains(token) {
                score += 250
            }
            scored.append((index, score))
        }

        scored.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            let lhs = snapshot.0[$0.index].place
            let rhs = snapshot.0[$1.index].place
            if lhs.population != rhs.population { return lhs.population > rhs.population }
            return Self.stableIDLessThan(lhs.id, rhs.id)
        }
        return scored.prefix(max(0, limit)).map { snapshot.0[$0.index].place }
    }

    /// Resolve free text only when it is exact and unambiguous. Full localized
    /// addresses are direct; a bare name/alias resolves only if exactly one indexed
    /// place owns it. Ambiguous names deliberately return nil.
    public func uniqueEntry(
        matching text: String,
        language: AppLanguage = .current
    ) -> PlaceEntry? {
        let key = Self.normalize(text, language: language)
        let result: IndexedEntry? = lock.withLock {
            if let index = fullAddresses[key], entries.indices.contains(index) {
                return entries[index]
            }
            if let index = uniqueBareNames[key], entries.indices.contains(index) {
                return entries[index]
            }
            return nil
        }
        return result?.place
    }

    public func mapLabels(
        tier: PlaceLabelTier,
        bounds: PlaceBounds,
        language: AppLanguage = .current
    ) -> [PlaceEntry] {
        let snapshot: ([IndexedEntry], [Int]) = lock.withLock {
            let indexes = tier == .close
                ? candidateIndexes(in: bounds)
                : labelCandidates[tier] ?? []
            return (entries, indexes)
        }
        let filtered = snapshot.1.compactMap { index -> PlaceEntry? in
            guard snapshot.0.indices.contains(index) else { return nil }
            let place = snapshot.0[index].place
            guard let latitude = place.latitude, let longitude = place.longitude,
                  bounds.contains(latitude: latitude, longitude: longitude),
                  Self.isEligibleForLabel(place, tier: tier) else { return nil }
            return place
        }
        let ranked = tier == .close
            ? filtered.sorted {
                if $0.population != $1.population { return $0.population > $1.population }
                return Self.stableIDLessThan($0.id, $1.id)
            }
            : filtered
        return ranked
        .prefix(tier.maximumLabels * 5)
        .map { $0 }
    }

    private func candidateIndexes(in bounds: PlaceBounds) -> [Int] {
        let minimumLatCell = Self.latitudeCell(bounds.minimumLatitude)
        let maximumLatCell = Self.latitudeCell(bounds.maximumLatitude)
        let longitudeRanges: [ClosedRange<Int>]
        if bounds.minimumLongitude <= bounds.maximumLongitude {
            longitudeRanges = [
                Self.longitudeCell(bounds.minimumLongitude) ... Self.longitudeCell(bounds.maximumLongitude),
            ]
        } else {
            longitudeRanges = [
                Self.longitudeCell(bounds.minimumLongitude) ... 71,
                0 ... Self.longitudeCell(bounds.maximumLongitude),
            ]
        }
        var result: [Int] = []
        for latitudeCell in minimumLatCell ... maximumLatCell {
            for longitudeRange in longitudeRanges {
                for longitudeCell in longitudeRange {
                    result.append(contentsOf: spatialBuckets[latitudeCell * 72 + longitudeCell] ?? [])
                }
            }
        }
        return result
    }

    private static func isEligibleForLabel(_ place: PlaceEntry, tier: PlaceLabelTier) -> Bool {
        let isNationalCapital = place.featureCode == "PPLC"
        let isAdminSeat = place.featureCode.hasPrefix("PPLA")
        switch tier {
        case .world:
            return isNationalCapital || place.population >= 5_000_000
        case .regional:
            return isNationalCapital || place.featureCode == "PPLA" || place.population >= 1_000_000
        case .city:
            return isAdminSeat || place.population >= 100_000
        case .close:
            return true
        }
    }

    private static func loadPlaces() -> LoadedIndex {
        guard let url = ResourceBundle.core.url(
            forResource: "place_index_v2",
            withExtension: "tsv"
        ) else {
            log.error("place_index_v2.tsv not found in bundle")
            return LoadedIndex(
                entries: [],
                byID: [:],
                uniqueBareNames: [:],
                fullAddresses: [:],
                spatialBuckets: [:],
                searchPrefixes: [:],
                labelCandidates: [:],
                versions: []
            )
        }
        guard let data = try? String(contentsOf: url, encoding: .utf8) else {
            log.error("failed to read place_index_v2.tsv")
            return LoadedIndex(
                entries: [],
                byID: [:],
                uniqueBareNames: [:],
                fullAddresses: [:],
                spatialBuckets: [:],
                searchPrefixes: [:],
                labelCandidates: [:],
                versions: []
            )
        }

        var result: [IndexedEntry] = []
        result.reserveCapacity(max(1_000, data.utf8.count / 180))
        var byID: [String: Int] = [:]
        var uniqueBare: [String: Int] = [:]
        var ambiguousBare = Set<String>()
        var fullAddresses: [String: Int] = [:]
        var ambiguousAddresses = Set<String>()
        var buckets: [Int: [Int]] = [:]
        var prefixes: [String: [Int]] = [:]
        var versions = Set<String>()

        for line in data.split(separator: "\n").dropFirst() {
            let columns = line.split(
                separator: "\t",
                maxSplits: 15,
                omittingEmptySubsequences: false
            ).map(String.init)
            guard columns.count == 16,
                  byID[columns[0]] == nil,
                  let population = Int(columns[2]),
                  let latitude = Double(columns[13]),
                  let longitude = Double(columns[14]),
                  (-90 ... 90).contains(latitude),
                  (-180 ... 180).contains(longitude) else { continue }

            let aliases = columns[6].split(separator: "|").map(String.init)
            let place = PlaceEntry(
                id: columns[0],
                featureCode: columns[1],
                population: population,
                nameRu: columns[3],
                nameEn: columns[4],
                nameLocal: columns[5],
                aliases: aliases,
                regionRu: columns[7],
                regionEn: columns[8],
                countryRu: columns[9],
                countryEn: columns[10],
                countryCode: columns[11],
                continentCode: columns[12],
                latitude: latitude,
                longitude: longitude,
                datasetVersion: columns[15]
            )
            let ruName = normalize(place.name(language: .russian), language: .russian)
            let enName = normalize(place.name(language: .english), language: .english)
            let localName = normalize(place.nameLocal, language: .english)
            let aliasNames = aliases
                .map { normalize($0, language: .english) }
                .filter { !$0.isEmpty }
            let ruAddress = normalize(place.displayName(language: .russian), language: .russian)
            let enAddress = normalize(place.displayName(language: .english), language: .english)
            let haystack = ([ruAddress, enAddress, localName] + aliasNames)
                .joined(separator: " ")
            let indexed = IndexedEntry(
                place: place,
                ruName: ruName,
                enName: enName,
                localName: localName,
                aliasNames: aliasNames,
                haystack: haystack,
                fullAddressRu: ruAddress,
                fullAddressEn: enAddress
            )
            let index = result.count
            result.append(indexed)
            byID[place.id] = index
            versions.insert(place.datasetVersion)

            for key in Set([ruName, enName, localName] + aliasNames) where !key.isEmpty {
                addUnique(key, index: index, values: &uniqueBare, ambiguous: &ambiguousBare)
            }
            for key in Set([ruAddress, enAddress]) where !key.isEmpty {
                addUnique(key, index: index, values: &fullAddresses, ambiguous: &ambiguousAddresses)
            }
            let bucket = latitudeCell(latitude) * 72 + longitudeCell(longitude)
            buckets[bucket, default: []].append(index)
            let words = haystack.split { !$0.isLetter && !$0.isNumber }
            for prefix in Set(words.map { prefixKey(String($0)) }) where !prefix.isEmpty {
                prefixes[prefix, default: []].append(index)
            }
        }

        var labelCandidates: [PlaceLabelTier: [Int]] = [:]
        for tier in PlaceLabelTier.allCases where tier != .close {
            labelCandidates[tier] = result.indices
                .filter { isEligibleForLabel(result[$0].place, tier: tier) }
                .sorted {
                    let lhs = result[$0].place
                    let rhs = result[$1].place
                    if lhs.population != rhs.population { return lhs.population > rhs.population }
                    return stableIDLessThan(lhs.id, rhs.id)
                }
        }

        log.notice("loaded \(result.count) bilingual places from GeoNames")
        return LoadedIndex(
            entries: result,
            byID: byID,
            uniqueBareNames: uniqueBare,
            fullAddresses: fullAddresses,
            spatialBuckets: buckets,
            searchPrefixes: prefixes,
            labelCandidates: labelCandidates,
            versions: versions
        )
    }

    private static func addUnique(
        _ key: String,
        index: Int,
        values: inout [String: Int],
        ambiguous: inout Set<String>
    ) {
        guard !ambiguous.contains(key) else { return }
        if let existing = values[key], existing != index {
            values.removeValue(forKey: key)
            ambiguous.insert(key)
        } else {
            values[key] = index
        }
    }

    private static func normalize(_ value: String, language: AppLanguage) -> String {
        value
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: language.locale
            )
            .lowercased(with: language.locale)
            .replacingOccurrences(of: "ё", with: "е")
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,.;"))
    }

    private static func stableIDLessThan(_ lhs: String, _ rhs: String) -> Bool {
        if let lhsNumber = Int(lhs), let rhsNumber = Int(rhs), lhsNumber != rhsNumber {
            return lhsNumber < rhsNumber
        }
        return lhs < rhs
    }

    private static func prefixKey(_ value: String) -> String {
        String(value.prefix(2))
    }

    private static func latitudeCell(_ latitude: Double) -> Int {
        min(35, max(0, Int(floor((latitude + 90) / 5))))
    }

    private static func longitudeCell(_ longitude: Double) -> Int {
        min(71, max(0, Int(floor((longitude + 180) / 5))))
    }
}
