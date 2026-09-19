import SwiftUI

// The only file in the app that is allowed to name a macOS 26 symbol or spell
// `#available(macOS 26, *)`. Everything else calls the shims below, so lowering the
// deployment target stays a rename at the leaves instead of 116 inline availability
// branches. The Ubuntu lint job in CI enforces that containment.
//
// Liquid Glass itself is *not* gated on the deployment target — the system reads the
// linked SDK version out of `LC_BUILD_VERSION`, which is a separate field from `minos`.
// Built against the macOS 26 SDK, the 26 branches below run on 26 exactly as they did
// when the whole app required it. `build_dmg.sh` asserts that SDK floor.
//
// Cost worth knowing: `ViewBuilder.buildLimitedAvailability` returns `AnyView`, so each
// guarded leaf boxes its branch once per body evaluation. Fine for chrome; the two
// sites in a redraw-hot path are TreeCanvasView's zoom cluster and MapChartView.

// MARK: - Glass surfaces

/// The subset of `Glass` this app actually uses, in a type that exists on macOS 15.
///
/// `Glass` is macOS 26-only and so cannot appear in a signature the older runtime has to
/// parse. Member-level availability is allowed independently of the enclosing type,
/// which is what lets `resolved` hand back the real thing on 26.
struct SepiaGlassStyle {
    var tint: Color?
    /// Named `isInteractive` rather than `interactive`, which is taken by the builder
    /// method below — a stored property and a method cannot share a name.
    var isInteractive = false

    static let regular = SepiaGlassStyle()

    static func tinted(_ color: Color) -> SepiaGlassStyle {
        SepiaGlassStyle(tint: color)
    }

    func interactive(_ enabled: Bool = true) -> SepiaGlassStyle {
        var copy = self
        copy.isInteractive = enabled
        return copy
    }

    @available(macOS 26.0, *)
    var resolved: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint) }
        if isInteractive { glass = glass.interactive() }
        return glass
    }
}

extension View {
    /// `glassEffect` on macOS 26, a warm sepia surface below it.
    ///
    /// The shape is constrained to `InsettableShape` so the fallback can use
    /// `strokeBorder`: a plain `stroke` straddles the edge and the fill clips half of it
    /// away. All three shapes in use here — `Capsule`, `Circle`, `RoundedRectangle` —
    /// are insettable.
    @ViewBuilder
    func sepiaGlass(_ style: SepiaGlassStyle = .regular, in shape: some InsettableShape) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(style.resolved, in: shape)
        } else {
            // Mirrors `LiquidGlassPanelBackground`: vibrancy alone reads cold and grey
            // against `paper`, so it is always warmed by the paper token over the top.
            background {
                ZStack {
                    shape.fill(.regularMaterial)
                    shape.fill(SepiaTheme.paper.opacity(0.82))
                    if let tint = style.tint {
                        shape.fill(tint)
                    }
                    shape.strokeBorder(SepiaTheme.cardLine.opacity(0.7), lineWidth: 1)
                }
            }
        }
    }
}

/// `GlassEffectContainer` on macOS 26, a plain pass-through below it.
///
/// The container only merges neighbouring glass shapes; with no glass to merge there is
/// nothing for it to do, so the fallback is the content itself rather than a stand-in.
struct SepiaGlassGroup<Content: View>: View {
    var spacing: CGFloat?
    @ViewBuilder var content: Content

    init(spacing: CGFloat? = nil, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            // `GlassEffectContainer.ContentBuilder` is a typealias for `ViewBuilder`, so
            // the already-built content passes straight through.
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

// MARK: - Buttons

extension View {
    /// `.buttonStyle(.glass)` on macOS 26, `SepiaButtonStyle` below it.
    ///
    /// Deliberately a `View` extension and not a `PrimitiveButtonStyle` that delegates:
    /// the style form compiles, but `makeBody` is itself a view builder, so it pays the
    /// same `AnyView` erasure *plus* an extra `Button` layer on every one of these sites.
    ///
    /// `shape` is only read by the fallback. On 26 the call site's own
    /// `.buttonBorderShape(...)` still drives the glass shape, so those lines stay put.
    /// A plain `ButtonStyle` cannot see `buttonBorderShape`, hence the explicit argument.
    @ViewBuilder
    func sepiaGlassButton(_ shape: SepiaShape.Kind = .rounded(7)) -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(SepiaButtonStyle.forShape(shape))
        }
    }

    /// `.buttonStyle(.glassProminent)` on macOS 26, the accent-filled sepia button below.
    @ViewBuilder
    func sepiaGlassProminentButton(_ shape: SepiaShape.Kind = .rounded(7)) -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(SepiaButtonStyle.forShape(shape, isActive: true))
        }
    }
}

// MARK: - Toolbar

extension ToolbarContent {
    /// `sharedBackgroundVisibility` on macOS 26, a no-op below it.
    ///
    /// The extension is on `ToolbarContent` because that is where SwiftUI declares the
    /// modifier — it is *not* a member of `ToolbarItem` or `ToolbarItemGroup`, despite
    /// reading like one at the call site. Inside this extension `Self` is only known to
    /// conform to `ToolbarContent`, so the `CustomizableToolbarContent` overload never
    /// becomes ambiguous.
    ///
    /// The return type drops any `CustomizableToolbarContent` conformance. Harmless
    /// here: the app has no `.toolbar(id:)` call sites.
    @ToolbarContentBuilder
    func sepiaSharedBackground(_ visibility: Visibility) -> some ToolbarContent {
        if #available(macOS 26.0, *) {
            sharedBackgroundVisibility(visibility)
        } else {
            self
        }
    }
}

/// Sizing for `sepiaToolbarSpacer`. `SwiftUI.SpacerSizing` is itself macOS 26-only, so
/// it cannot appear in the shim's signature.
enum SepiaToolbarSpacing {
    case fixed
    case flexible
}

/// `ToolbarSpacer` on macOS 26, a measured gap or nothing below it.
///
/// Flexible resolves to *nothing* on macOS 15 on purpose: a `Spacer` inside an AppKit
/// toolbar item has no intrinsic width and collapses anyway, and 15 already pushes
/// `.primaryAction` to the trailing edge by itself.
///
/// Fixed has to stay a real gap. Below 26 the shared-background capsules disappear too,
/// so without it the principal groups butt straight into one another.
@ToolbarContentBuilder
func sepiaToolbarSpacer(
    _ sizing: SepiaToolbarSpacing = .flexible,
    placement: ToolbarItemPlacement = .automatic
) -> some ToolbarContent {
    if #available(macOS 26.0, *) {
        ToolbarSpacer(sizing == .fixed ? .fixed : .flexible, placement: placement)
    } else if sizing == .fixed {
        ToolbarItem(placement: placement) {
            Color.clear
                .frame(width: 10, height: 1)
                .accessibilityHidden(true)
        }
    }
}
