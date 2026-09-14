@testable import SwarmCore
import Testing

struct MapLoadPhaseTests {
    private func phase(
        _ provider: MapProviderSetting,
        placesSettled: Bool = true,
        placesFailed: Bool = false,
        vectorsFailed: Bool = false,
        tilesLoaded: Bool = true,
        tilesFailed: Bool = false
    ) -> MapLoadPhase {
        MapLoadPhase.resolve(
            provider: provider,
            placesSettled: placesSettled,
            placesFailed: placesFailed,
            vectorsFailed: vectorsFailed,
            tilesLoaded: tilesLoaded,
            tilesFailed: tilesFailed
        )
    }

    @Test func everySourceSettledMeansReady() {
        #expect(phase(.appleMaps) == .ready)
        #expect(phase(.offlineVector) == .ready)
    }

    @Test func aMissingPlaceIndexFailsBothProviders() {
        #expect(phase(.appleMaps, placesFailed: true) == .failed)
        #expect(phase(.offlineVector, placesFailed: true) == .failed)
    }

    @Test func eachProviderOnlyFailsOnTheSourcesItDrawsFrom() {
        // Tiles are Apple's alone; the offline renderer never asks for one.
        #expect(phase(.appleMaps, tilesLoaded: false, tilesFailed: true) == .failed)
        #expect(phase(.offlineVector, tilesLoaded: false, tilesFailed: true) == .ready)

        // The bundled vectors are the offline renderer's alone.
        #expect(phase(.offlineVector, vectorsFailed: true) == .failed)
        #expect(phase(.appleMaps, vectorsFailed: true) == .ready)
    }

    @Test func anUnsettledSourceKeepsTheMapLoadingRatherThanFailing() {
        #expect(phase(.appleMaps, placesSettled: false) == .loading)
        #expect(phase(.offlineVector, placesSettled: false) == .loading)
        #expect(phase(.appleMaps, tilesLoaded: false) == .loading)
    }

    @Test func aFailureOutranksSourcesThatAreStillLoading() {
        #expect(phase(.appleMaps, placesSettled: false, placesFailed: true) == .failed)
        #expect(phase(.appleMaps, placesSettled: false, tilesFailed: true) == .failed)
    }
}
