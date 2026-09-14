import Foundation

/// Where the map workspace stands while its data sources come up. Kept free of timers and
/// views so the provider/source truth table can be tested directly.
public enum MapLoadPhase: Sendable, Equatable {
    case loading
    case ready
    case failed

    /// Each provider depends on a different set of sources: Apple Maps needs its tiles, the
    /// offline renderer needs the bundled Natural Earth vectors, and both need the place
    /// index — without it the map draws no pins at all, which is the point of the screen.
    public static func resolve(
        provider: MapProviderSetting,
        placesSettled: Bool,
        placesFailed: Bool,
        vectorsFailed: Bool,
        tilesLoaded: Bool,
        tilesFailed: Bool
    ) -> MapLoadPhase {
        if placesFailed { return .failed }
        switch provider {
        case .appleMaps:
            if tilesFailed { return .failed }
            return placesSettled && tilesLoaded ? .ready : .loading
        case .offlineVector:
            if vectorsFailed { return .failed }
            return placesSettled ? .ready : .loading
        }
    }
}
