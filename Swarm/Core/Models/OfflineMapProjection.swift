import CoreGraphics
import Foundation

/// A latitude/longitude pair the offline map can project.
///
/// The renderer used to carry its own private copy of this. Lifting it here is what
/// lets the projection math be tested at all: every function below used to be a
/// `private` method on a SwiftUI `View`, reachable only by driving the UI.
public struct MapCoordinate: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

/// Web Mercator projection and camera math for the offline vector map.
///
/// Normalised space is the unit square: x 0…1 west→east, y 0…1 north→south. Both
/// screen axes are scaled by `size.width`, not by their own dimension — that is what
/// keeps world pixels square, and every function here assumes it.
public enum OfflineMapProjection {
    /// Web Mercator's usable latitude limit. `tan` diverges at the poles, so the
    /// standard cutoff is the latitude whose projected y is exactly one world unit
    /// from the equator.
    public static let latitudeLimit = 85.0511

    public static let minimumScale: CGFloat = 0.8
    public static let maximumScale: CGFloat = 40

    /// Equatorial circumference, WGS 84. The full world is this many kilometres wide
    /// in normalised space; every other latitude shrinks by `cos(latitude)`.
    public static let equatorialCircumferenceKilometres = 40075.016686

    // MARK: - Projection

    public static func normalized(_ coordinate: MapCoordinate) -> CGPoint {
        let latitude = min(latitudeLimit, max(-latitudeLimit, coordinate.latitude))
        let radians = latitude * .pi / 180
        return CGPoint(
            x: (coordinate.longitude + 180) / 360,
            y: (1 - log(tan(radians) + 1 / cos(radians)) / .pi) / 2
        )
    }

    public static func coordinate(atNormalized point: CGPoint) -> MapCoordinate {
        let wrapped = Double(point.x) - floor(Double(point.x))
        let clamped = min(1, max(0, Double(point.y)))
        return MapCoordinate(
            latitude: atan(sinh(.pi * (1 - 2 * clamped))) * 180 / .pi,
            longitude: wrapped * 360 - 180
        )
    }

    public static func project(
        _ coordinate: MapCoordinate,
        center: CGPoint,
        scale: CGFloat,
        size: CGSize
    ) -> CGPoint {
        project(normalized: normalized(coordinate), center: center, scale: scale, size: size)
    }

    public static func project(
        normalized point: CGPoint,
        center: CGPoint,
        scale: CGFloat,
        size: CGSize
    ) -> CGPoint {
        CGPoint(
            x: size.width / 2 + (point.x - center.x) * size.width * scale,
            y: size.height / 2 + (point.y - center.y) * size.width * scale
        )
    }

    /// Inverse of `project(normalized:…)`: where in the world a point on screen sits.
    public static func normalizedPoint(
        forView point: CGPoint,
        center: CGPoint,
        scale: CGFloat,
        size: CGSize
    ) -> CGPoint {
        let span = size.width * scale
        guard span > 0 else { return center }
        return CGPoint(
            x: center.x + (point.x - size.width / 2) / span,
            y: center.y + (point.y - size.height / 2) / span
        )
    }

    // MARK: - Camera

    /// Half of the visible width and height, in normalised units.
    private static func halfSpan(scale: CGFloat, size: CGSize) -> (x: Double, y: Double) {
        guard scale > 0, size.width > 0 else { return (0.5, 0.5) }
        return (
            0.5 / Double(scale),
            Double(size.height / size.width) * 0.5 / Double(scale)
        )
    }

    public static func visibleBounds(center: CGPoint, scale: CGFloat, size: CGSize) -> PlaceBounds {
        let half = halfSpan(scale: scale, size: size)
        let showsWholeWorld = half.x * 2 >= 1
        let top = coordinate(atNormalized: CGPoint(x: 0, y: CGFloat(Double(center.y) - half.y)))
        let bottom = coordinate(atNormalized: CGPoint(x: 0, y: CGFloat(Double(center.y) + half.y)))
        let west = coordinate(atNormalized: CGPoint(x: CGFloat(Double(center.x) - half.x), y: 0))
        let east = coordinate(atNormalized: CGPoint(x: CGFloat(Double(center.x) + half.x), y: 0))
        return PlaceBounds(
            minimumLatitude: bottom.latitude,
            maximumLatitude: top.latitude,
            minimumLongitude: showsWholeWorld ? -180 : west.longitude,
            maximumLongitude: showsWholeWorld ? 180 : east.longitude
        )
    }

    /// Keeps the viewport over the world.
    ///
    /// The old clamp pinned the *centre* to 0…1, which let the visible rectangle slide
    /// almost entirely off the map at high zoom — half a screen of empty sea with the
    /// pins gone. An axis smaller than the viewport is centred instead of clamped.
    public static func clampCenter(_ center: CGPoint, scale: CGFloat, size: CGSize) -> CGPoint {
        let half = halfSpan(scale: scale, size: size)
        let x: Double = half.x * 2 >= 1 ? 0.5 : min(1 - half.x, max(half.x, Double(center.x)))
        let y: Double = half.y * 2 >= 1 ? 0.5 : min(1 - half.y, max(half.y, Double(center.y)))
        return CGPoint(x: x, y: y)
    }

    /// Moves the centre so the world point under `anchor` stays under `anchor` across a
    /// scale change. Without this a zoom always pulls toward the middle of the view,
    /// which is why aiming at a village and zooming used to lose it off-screen.
    public static func anchoredCenter(
        center: CGPoint,
        anchor: CGPoint,
        oldScale: CGFloat,
        newScale: CGFloat,
        size: CGSize
    ) -> CGPoint {
        guard size.width > 0, oldScale > 0, newScale > 0 else { return center }
        let world = normalizedPoint(forView: anchor, center: center, scale: oldScale, size: size)
        let span = Double(size.width * newScale)
        let moved = CGPoint(
            x: Double(world.x) - Double(anchor.x - size.width / 2) / span,
            y: Double(world.y) - Double(anchor.y - size.height / 2) / span
        )
        return clampCenter(moved, scale: newScale, size: size)
    }

    // MARK: - Chrome

    /// Graticule spacing in degrees. The renderer used a fixed 30°/15°, which drew
    /// nothing at all once the viewport was narrower than a single cell.
    public static func graticuleStep(for scale: CGFloat) -> Double {
        switch scale {
        case ..<1.5: 30
        case ..<4: 10
        case ..<12: 5
        case ..<30: 2
        default: 1
        }
    }

    /// Ground kilometres per screen point at `latitude`. Mercator stretches with
    /// latitude, so a bar measured at the equator would read ~2x long over Russia.
    public static func kilometresPerPoint(scale: CGFloat, latitude: Double, size: CGSize) -> Double {
        let span = Double(size.width * scale)
        guard span > 0 else { return 0 }
        let clamped = min(latitudeLimit, max(-latitudeLimit, latitude))
        return equatorialCircumferenceKilometres * cos(clamped * .pi / 180) / span
    }

    /// A round scale-bar distance on the 1-2-5 ladder, with the width to draw it at.
    /// `nil` when the geometry is degenerate.
    public static func scaleBar(
        scale: CGFloat,
        latitude: Double,
        size: CGSize,
        maximumWidth: CGFloat
    ) -> (kilometres: Double, width: CGFloat)? {
        let perPoint = kilometresPerPoint(scale: scale, latitude: latitude, size: size)
        guard perPoint > 0, perPoint.isFinite, maximumWidth > 0 else { return nil }
        let widest = perPoint * Double(maximumWidth)
        guard widest > 0, widest.isFinite else { return nil }
        let magnitude = pow(10, floor(log10(widest)))
        let chosen = [1.0, 2, 5, 10]
            .map { $0 * magnitude }
            .last { $0 <= widest } ?? magnitude
        return (chosen, CGFloat(chosen / perPoint))
    }
}
