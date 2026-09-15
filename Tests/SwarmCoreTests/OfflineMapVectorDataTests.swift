import Foundation
@testable import SwarmCore
import Testing

struct OfflineMapVectorDataTests {
    /// `Bundle`'s own lookup memoises a miss for the life of the process, so Try Again
    /// could never find a resource restored while the app ran. The helper falls back to
    /// the resource folder on disk; both bundled files have to resolve through it.
    @Test func resourceLookupResolvesTheBundledMapDataAndRejectsWhatIsNotThere() throws {
        for (name, ext) in [("ne_110m_land", "geojson"), ("place_index_v2", "tsv")] {
            let url = try #require(ResourceBundle.url(forResource: name, withExtension: ext))
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
        #expect(ResourceBundle.url(forResource: "no_such_resource", withExtension: "geojson") == nil)
    }

    /// Longitude is passed as a pair rather than a range: a viewport straddling the
    /// antimeridian has a minimum above its maximum, which `ClosedRange` refuses.
    private func bounds(
        latitude: ClosedRange<Double>,
        west: Double,
        east: Double
    ) -> PlaceBounds {
        PlaceBounds(
            minimumLatitude: latitude.lowerBound,
            maximumLatitude: latitude.upperBound,
            minimumLongitude: west,
            maximumLongitude: east
        )
    }

    private func ring(
        latitude: ClosedRange<Double>,
        longitude: ClosedRange<Double>
    ) -> MapVectorRing {
        MapVectorRing(points: [
            MapVectorPoint(longitude: longitude.lowerBound, latitude: latitude.lowerBound),
            MapVectorPoint(longitude: longitude.upperBound, latitude: latitude.upperBound),
        ])
    }

    // MARK: - Bundled resources

    @Test func bundledVectorsParseIntoRings() {
        let data = OfflineMapVectorData.shared
        #expect(!data.didFail)
        #expect(data.landPolygons.count == 128)
        #expect(data.borderLines.count == 333)
    }

    @Test func everyBundledRingHasAtLeastTwoPointsAndPlausibleBounds() {
        let data = OfflineMapVectorData.shared
        for ring in data.landPolygons + data.borderLines {
            #expect(ring.points.count > 1)
            #expect(ring.minimumLatitude >= -90)
            #expect(ring.maximumLatitude <= 90)
            #expect(ring.minimumLongitude >= -180)
            #expect(ring.maximumLongitude <= 180)
            #expect(ring.minimumLatitude <= ring.maximumLatitude)
            #expect(ring.minimumLongitude <= ring.maximumLongitude)
        }
    }

    @Test func reloadRebuildsTheSameGeometry() {
        let before = OfflineMapVectorData.shared.landPolygons.count
        OfflineMapVectorData.reload()
        #expect(OfflineMapVectorData.shared.landPolygons.count == before)
    }

    // MARK: - Bounding boxes

    @Test func ringBoundsSpanEveryPoint() {
        let ring = MapVectorRing(points: [
            MapVectorPoint(longitude: 10, latitude: 50),
            MapVectorPoint(longitude: -4, latitude: 61),
            MapVectorPoint(longitude: 37, latitude: 44),
        ])
        #expect(ring.minimumLongitude == -4)
        #expect(ring.maximumLongitude == 37)
        #expect(ring.minimumLatitude == 44)
        #expect(ring.maximumLatitude == 61)
    }

    @Test func ringWithNoPointsCollapsesToTheOrigin() {
        let ring = MapVectorRing(points: [])
        #expect(ring.minimumLatitude == 0)
        #expect(ring.maximumLongitude == 0)
    }

    // MARK: - Culling

    @Test func overlappingRingsSurviveAndDistantOnesDoNot() {
        let viewport = bounds(latitude: 50 ... 60, west: 30, east: 40)
        #expect(ring(latitude: 55 ... 56, longitude: 37 ... 38).intersects(viewport))
        // Touching on an edge still counts: a coastline that grazes the viewport draws.
        #expect(ring(latitude: 40 ... 50, longitude: 30 ... 40).intersects(viewport))
        // Right latitude, wrong longitude.
        #expect(!ring(latitude: 55 ... 56, longitude: -10 ... -5).intersects(viewport))
        // Right longitude, wrong latitude.
        #expect(!ring(latitude: -40 ... -30, longitude: 30 ... 40).intersects(viewport))
    }

    @Test func aRingLargerThanTheViewportStillCounts() {
        // Eurasia's ring dwarfs any close-zoom viewport; rejecting it would erase the
        // land under every pin.
        let viewport = bounds(latitude: 55.7 ... 55.8, west: 37.6, east: 37.7)
        #expect(ring(latitude: -60 ... 80, longitude: -170 ... 170).intersects(viewport))
    }

    @Test func boundsWrappingTheAntimeridianMatchBothSides() {
        let viewport = bounds(latitude: 60 ... 70, west: 170, east: -170)
        #expect(ring(latitude: 62 ... 64, longitude: 175 ... 179).intersects(viewport))
        #expect(ring(latitude: 62 ... 64, longitude: -179 ... -175).intersects(viewport))
        #expect(!ring(latitude: 62 ... 64, longitude: 0 ... 10).intersects(viewport))
    }

    @Test func cullingTheBundledLandKeepsFarFewerRingsThanItDrops() {
        let data = OfflineMapVectorData.shared
        // A close view over Moscow: the renderer used to project all 128 rings, and all
        // 333 border lines, on every frame regardless of what was on screen.
        let viewport = bounds(latitude: 55.5 ... 56, west: 37.3, east: 38)
        let land = data.land(intersecting: viewport)
        let borders = data.borders(intersecting: viewport)
        #expect(!land.isEmpty)
        #expect(land.count < data.landPolygons.count / 4)
        #expect(borders.count < data.borderLines.count / 4)
    }

    @Test func aWholeWorldViewportKeepsEveryRing() {
        let data = OfflineMapVectorData.shared
        let viewport = bounds(latitude: -90 ... 90, west: -180, east: 180)
        #expect(data.land(intersecting: viewport).count == data.landPolygons.count)
        #expect(data.borders(intersecting: viewport).count == data.borderLines.count)
    }
}
