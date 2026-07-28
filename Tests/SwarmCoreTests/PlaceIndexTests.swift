import Foundation
@testable import SwarmCore
import Testing

struct PlaceIndexTests {
    private func readyDatabase() async -> PlacesDatabase {
        await withCheckedContinuation { continuation in
            PlacesDatabase.shared.whenReady {
                continuation.resume(returning: PlacesDatabase.shared)
            }
        }
    }

    @Test func productionSnapshotHasExactSchemaCoverageAndOnePinnedVersion() async throws {
        let url = try #require(
            ResourceBundle.core.url(forResource: "place_index_v2", withExtension: "tsv")
        )
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let prefix = try handle.read(upToCount: 1_024) ?? Data()
        let firstLine = try #require(String(data: prefix, encoding: .utf8)?.split(separator: "\n").first)
        #expect(firstLine == """
        geoname_id\tfeature_code\tpopulation\tname_ru\tname_en\tname_local\taliases\tregion_ru\tregion_en\tcountry_ru\tcountry_en\tcountry_code\tcontinent_code\tlatitude\tlongitude\tdataset_version
        """)

        let database = await readyDatabase()
        #expect(database.count == 476_958)
        #expect(database.datasetVersions == Set(["geonames-2026-07-28"]))
    }

    @Test func representativeCitiesAreSearchableInBothLanguages() async {
        let database = await readyDatabase()
        let cases: [(id: String, english: String, russian: String)] = [
            ("2643743", "London", "Лондон"),
            ("2988507", "Paris", "Париж"),
            ("5128581", "New York", "Нью-Йорк"),
            ("6167865", "Toronto", "Торонто"),
            ("3530597", "Mexico City", "Мехико"),
            ("625144", "Minsk", "Минск"),
        ]
        for city in cases {
            #expect(database.search(city.english, language: .english).contains { $0.id == city.id })
            #expect(database.search(city.russian, language: .russian).contains { $0.id == city.id })
        }
    }

    @Test func ambiguousBareNamesNeverReceiveArbitraryCoordinates() async {
        let database = await readyDatabase()
        #expect(database.uniqueEntry(matching: "Springfield", language: .english) == nil)

        let london = database.uniqueEntry(
            matching: "London, England, United Kingdom",
            language: .english
        )
        #expect(london?.id == "2643743")
        #expect(GeocodingService.shared.coordinateSync(
            for: "Springfield",
            language: .english
        ) == nil)
    }

    @Test func languageSwitchChangesPresentationButNotArchivalReference() async throws {
        let database = await readyDatabase()
        let london = try #require(database.entry(id: "2643743"))
        let reference = london.placeReference(language: .english)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let before = try encoder.encode(reference)

        #expect(database.presentationName(for: reference, language: .english)
            == "London, England, United Kingdom")
        #expect(database.presentationName(for: reference, language: .russian)
            == "Лондон, Англия, Британия")
        #expect(try encoder.encode(reference) == before)
        #expect(reference.displayName == "London, England, United Kingdom")
    }

    @Test func offlineLabelTiersAreRankedBoundedAndBilingual() async {
        let database = await readyDatabase()
        let europe = PlaceBounds(
            minimumLatitude: 35,
            maximumLatitude: 65,
            minimumLongitude: -15,
            maximumLongitude: 40
        )
        for tier in [PlaceLabelTier.world, .regional, .city, .close] {
            let labels = database.mapLabels(tier: tier, bounds: europe, language: .english)
            #expect(labels.count <= tier.maximumLabels * 5)
            #expect(zip(labels, labels.dropFirst()).allSatisfy { pair in
                pair.0.population >= pair.1.population
            })
        }
        let english = database.mapLabels(tier: .world, bounds: europe, language: .english)
        let russian = database.mapLabels(tier: .world, bounds: europe, language: .russian)
        #expect(english.first { $0.id == "2643743" }?.name(language: .english) == "London")
        #expect(russian.first { $0.id == "2643743" }?.name(language: .russian) == "Лондон")
    }
}
