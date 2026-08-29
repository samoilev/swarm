import SwiftUI

/// How far a surface floats above the paper.
///
/// Three levels, because the app only has three kinds of floating thing. It
/// previously had about fifteen shadow recipes in two conventions — half tinted
/// with `ink`, half with pure `.black` — so two banners sitting side by side on
/// the same paper could cast different shadows.
///
/// All three are tinted with `ink`, never black: a neutral shadow on a warm ground
/// reads as grey dirt under the element rather than as depth.
enum SepiaElevation {
    /// Resting cards and buttons: barely off the page.
    case raised
    /// Banners, toasts and inspector panels laid over the canvas.
    case overlay
    /// Search fields and popovers: the topmost layer, clearly detached.
    case popover

    var opacity: Double {
        switch self {
        case .raised: 0.08
        case .overlay: 0.10
        case .popover: 0.15
        }
    }

    var radius: CGFloat {
        switch self {
        case .raised: 6
        case .overlay: 10
        case .popover: 14
        }
    }

    var offsetY: CGFloat {
        switch self {
        case .raised: 2
        case .overlay: 4
        case .popover: 6
        }
    }
}

extension View {
    /// Casts one of the three sepia shadows. Use instead of a hand-written
    /// `.shadow(color:radius:y:)` so elevation stays comparable across screens.
    func sepiaElevation(_ level: SepiaElevation) -> some View {
        shadow(
            color: SepiaTheme.ink.opacity(level.opacity),
            radius: level.radius,
            y: level.offsetY
        )
    }
}
