import CoreGraphics
import Foundation
@testable import SwarmCore
import Testing

struct OfflineMapProjectionTests {
    private let size = CGSize(width: 1200, height: 800)
    private let moscow = MapCoordinate(latitude: 55.7558, longitude: 37.6173)

    // MARK: - Projection

    @Test func normalizedPlacesTheOriginAtTheTopLeftOfTheWorld() {
        let northWest = OfflineMapProjection.normalized(
            MapCoordinate(latitude: OfflineMapProjection.latitudeLimit, longitude: -180)
        )
        #expect(abs(northWest.x) < 0.000_1)
        #expect(abs(northWest.y) < 0.000_1)

        let equator = OfflineMapProjection.normalized(MapCoordinate(latitude: 0, longitude: 0))
        #expect(abs(equator.x - 0.5) < 0.000_1)
        #expect(abs(equator.y - 0.5) < 0.000_1)
    }

    @Test func projectionRoundTripsThroughScreenSpace() {
        let center = OfflineMapProjection.normalized(moscow)
        for scale in [CGFloat(0.8), 2.4, 12, 40] {
            let point = OfflineMapProjection.project(moscow, center: center, scale: scale, size: size)
            let back = OfflineMapProjection.normalizedPoint(
                forView: point,
                center: center,
                scale: scale,
                size: size
            )
            let coordinate = OfflineMapProjection.coordinate(atNormalized: back)
            #expect(abs(coordinate.latitude - moscow.latitude) < 0.000_1)
            #expect(abs(coordinate.longitude - moscow.longitude) < 0.000_1)
        }
    }

    @Test func centringOnACoordinatePutsItInTheMiddleOfTheView() {
        let center = OfflineMapProjection.normalized(moscow)
        let point = OfflineMapProjection.project(moscow, center: center, scale: 8, size: size)
        #expect(abs(point.x - size.width / 2) < 0.000_1)
        #expect(abs(point.y - size.height / 2) < 0.000_1)
    }

    @Test func bothAxesScaleByWidthSoWorldPixelsStaySquare() {
        let center = CGPoint(x: 0.5, y: 0.5)
        let east = OfflineMapProjection.project(
            normalized: CGPoint(x: 0.6, y: 0.5), center: center, scale: 1, size: size
        )
        let south = OfflineMapProjection.project(
            normalized: CGPoint(x: 0.5, y: 0.6), center: center, scale: 1, size: size
        )
        #expect(abs((east.x - size.width / 2) - (south.y - size.height / 2)) < 0.000_1)
    }

    // MARK: - Visible bounds

    @Test func boundsCoverTheWholeWorldWhenZoomedOut() {
        let bounds = OfflineMapProjection.visibleBounds(
            center: CGPoint(x: 0.5, y: 0.5), scale: 0.8, size: size
        )
        #expect(bounds.minimumLongitude == -180)
        #expect(bounds.maximumLongitude == 180)
    }

    @Test func boundsNarrowAsScaleRises() {
        let center = OfflineMapProjection.normalized(moscow)
        var previousSpan = Double.infinity
        for scale in [CGFloat(1.5), 4, 12, 40] {
            let bounds = OfflineMapProjection.visibleBounds(center: center, scale: scale, size: size)
            let span = bounds.maximumLongitude - bounds.minimumLongitude
            #expect(span < previousSpan)
            #expect(bounds.maximumLatitude > bounds.minimumLatitude)
            previousSpan = span
        }
        // At maximum zoom the viewport is a few degrees wide, not a few dozen.
        let closest = OfflineMapProjection.visibleBounds(center: center, scale: 40, size: size)
        #expect(closest.maximumLongitude - closest.minimumLongitude < 10)
    }

    @Test func boundsContainTheCentreTheyWereBuiltFrom() {
        let center = OfflineMapProjection.normalized(moscow)
        let bounds = OfflineMapProjection.visibleBounds(center: center, scale: 20, size: size)
        #expect(bounds.minimumLatitude < moscow.latitude)
        #expect(bounds.maximumLatitude > moscow.latitude)
        #expect(bounds.minimumLongitude < moscow.longitude)
        #expect(bounds.maximumLongitude > moscow.longitude)
    }

    // MARK: - Clamping

    @Test func clampKeepsTheViewportOverTheWorld() {
        for scale in [CGFloat(2), 8, 40] {
            let half = 0.5 / Double(scale)
            let halfHeight = Double(size.height / size.width) * 0.5 / Double(scale)
            for attempt in [CGPoint(x: -5, y: -5), CGPoint(x: 9, y: 9), CGPoint(x: 0, y: 1)] {
                let clamped = OfflineMapProjection.clampCenter(attempt, scale: scale, size: size)
                #expect(Double(clamped.x) >= half - 0.000_1)
                #expect(Double(clamped.x) <= 1 - half + 0.000_1)
                #expect(Double(clamped.y) >= halfHeight - 0.000_1)
                #expect(Double(clamped.y) <= 1 - halfHeight + 0.000_1)
            }
        }
    }

    @Test func clampCentresAnAxisSmallerThanTheViewport() {
        // At minimum scale this 3:2 view is wider than the world but still shorter than
        // it, so the two axes settle differently: x has nothing to pan along and belongs
        // in the middle, y has room left and pins to the edge it was pushed past.
        let clamped = OfflineMapProjection.clampCenter(
            CGPoint(x: 0.1, y: 0.9), scale: 0.8, size: size
        )
        #expect(abs(clamped.x - 0.5) < 0.000_1)
        let halfHeight = Double(size.height / size.width) * 0.5 / 0.8
        #expect(abs(Double(clamped.y) - (1 - halfHeight)) < 0.000_1)
    }

    @Test func clampLeavesAnAlreadyValidCentreAlone() {
        let center = CGPoint(x: 0.61, y: 0.31)
        let clamped = OfflineMapProjection.clampCenter(center, scale: 8, size: size)
        #expect(abs(clamped.x - center.x) < 0.000_1)
        #expect(abs(clamped.y - center.y) < 0.000_1)
    }

    // MARK: - Anchored zoom

    @Test func zoomKeepsTheWorldPointUnderTheAnchorInPlace() {
        let center = CGPoint(x: 0.6, y: 0.3)
        let anchor = CGPoint(x: 900, y: 200)
        let before = OfflineMapProjection.normalizedPoint(
            forView: anchor, center: center, scale: 4, size: size
        )
        let moved = OfflineMapProjection.anchoredCenter(
            center: center, anchor: anchor, oldScale: 4, newScale: 16, size: size
        )
        let after = OfflineMapProjection.normalizedPoint(
            forView: anchor, center: moved, scale: 16, size: size
        )
        #expect(abs(before.x - after.x) < 0.000_1)
        #expect(abs(before.y - after.y) < 0.000_1)
    }

    @Test func zoomingAtTheViewCentreDoesNotShiftTheCentre() {
        let center = CGPoint(x: 0.6, y: 0.3)
        let moved = OfflineMapProjection.anchoredCenter(
            center: center,
            anchor: CGPoint(x: size.width / 2, y: size.height / 2),
            oldScale: 4,
            newScale: 12,
            size: size
        )
        #expect(abs(moved.x - center.x) < 0.000_1)
        #expect(abs(moved.y - center.y) < 0.000_1)
    }

    @Test func anchoredZoomStillClampsToTheWorld() {
        // Zooming all the way out from a corner drives the raw centre well off the map;
        // the result still has to land inside the band the viewport allows.
        let moved = OfflineMapProjection.anchoredCenter(
            center: CGPoint(x: 0.02, y: 0.02),
            anchor: .zero,
            oldScale: 40,
            newScale: 0.8,
            size: size
        )
        #expect(abs(moved.x - 0.5) < 0.000_1)
        let halfHeight = Double(size.height / size.width) * 0.5 / 0.8
        #expect(Double(moved.y) >= halfHeight - 0.000_1)
        #expect(Double(moved.y) <= 1 - halfHeight + 0.000_1)
    }

    // MARK: - Chrome

    @Test func graticuleStepTightensAsScaleRises() {
        let steps = [CGFloat(0.8), 2, 8, 20, 40].map(OfflineMapProjection.graticuleStep(for:))
        #expect(steps == [30, 10, 5, 2, 1])
        for (coarse, fine) in zip(steps, steps.dropFirst()) {
            #expect(fine < coarse)
        }
    }

    @Test func scaleBarStaysOnTheOneTwoFiveLadder() throws {
        for scale in [CGFloat(0.8), 1.5, 4, 12, 25, 40] {
            let bar = try #require(
                OfflineMapProjection.scaleBar(
                    scale: scale, latitude: 55.75, size: size, maximumWidth: 120
                )
            )
            let magnitude = pow(10, floor(log10(bar.kilometres)))
            let mantissa = (bar.kilometres / magnitude).rounded()
            #expect([1, 2, 5].contains(mantissa))
            #expect(bar.width <= 120.000_1)
            #expect(bar.width > 0)
        }
    }

    @Test func scaleBarWidthMatchesTheDistanceItClaims() throws {
        let bar = try #require(
            OfflineMapProjection.scaleBar(scale: 8, latitude: 55.75, size: size, maximumWidth: 120)
        )
        let perPoint = OfflineMapProjection.kilometresPerPoint(scale: 8, latitude: 55.75, size: size)
        #expect(abs(Double(bar.width) * perPoint - bar.kilometres) < 0.001)
    }

    @Test func mercatorStretchIsTakenOutOfTheDistanceReading() {
        // A degree of longitude is about half as long at 60N as at the equator, and the
        // bar has to say so or it reads roughly 2x long over Russia.
        let equator = OfflineMapProjection.kilometresPerPoint(scale: 8, latitude: 0, size: size)
        let sixty = OfflineMapProjection.kilometresPerPoint(scale: 8, latitude: 60, size: size)
        #expect(abs(sixty / equator - 0.5) < 0.01)
    }

    @Test func scaleBarRejectsDegenerateGeometry() {
        #expect(OfflineMapProjection.scaleBar(
            scale: 8, latitude: 55, size: .zero, maximumWidth: 120
        ) == nil)
        #expect(OfflineMapProjection.scaleBar(
            scale: 8, latitude: 55, size: size, maximumWidth: 0
        ) == nil)
    }

    /// The renderer's own zoom limits, so a change to either end has to be deliberate.
    @Test func scaleLimitsSpanTheRangeTheRendererAdvertises() {
        #expect(OfflineMapProjection.minimumScale == 0.8)
        #expect(OfflineMapProjection.maximumScale == 40)
    }

    // MARK: - Zoom stepping

    /// Zoom In zoomed the map *out* above 200%: the keyboard clamped to 2.0 while the
    /// toolbar ran to 8, so `min(2.0, …)` above that was a downward assignment, and both
    /// renderers read the binding as a ratio.
    @Test func steppingInNeverZoomsOutAnywhereInTheRange() {
        var zoom = OfflineMapProjection.minimumZoom
        while zoom < OfflineMapProjection.maximumZoom {
            let next = OfflineMapProjection.steppedZoom(zoom, zoomingIn: true)
            #expect(next > zoom)
            zoom = next
        }
        #expect(zoom == OfflineMapProjection.maximumZoom)
    }

    @Test func steppingOutNeverZoomsIn() {
        var zoom = OfflineMapProjection.maximumZoom
        while zoom > OfflineMapProjection.minimumZoom {
            let next = OfflineMapProjection.steppedZoom(zoom, zoomingIn: false)
            #expect(next < zoom)
            zoom = next
        }
        #expect(zoom == OfflineMapProjection.minimumZoom)
    }

    @Test func steppingSaturatesAtBothEndsRatherThanPassingThem() {
        let top = OfflineMapProjection.maximumZoom
        #expect(OfflineMapProjection.steppedZoom(top, zoomingIn: true) == top)
        // The reported case exactly: 800% asked to zoom in stays at 800%.
        #expect(OfflineMapProjection.steppedZoom(top, zoomingIn: false) < top)

        let bottom = OfflineMapProjection.minimumZoom
        #expect(OfflineMapProjection.steppedZoom(bottom, zoomingIn: false) == bottom)
        #expect(OfflineMapProjection.steppedZoom(bottom, zoomingIn: true) > bottom)
    }
}
