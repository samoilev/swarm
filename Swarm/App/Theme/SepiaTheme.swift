import SwiftUI

struct SepiaTheme {
    /// Portrait photo aspect ratio (width ÷ height), used consistently for the photo
    /// in tree nodes, the inspector, the editor, and the upload crop selector.
    static let portraitAspect: CGFloat = 3.0 / 4.0

    // Core colors
    static let paper = Color(hex: "ece1c9")
    static let ink = Color(hex: "3a2c1a")
    // Muted secondary text. Kept dark enough to clear WCAG AA (≥4.5:1) on the
    // lightest-through-darkest surfaces it sits on (paper, cards, toolbar, fan);
    // don't lighten "for elegance" — that regresses contrast.
    static let inkSoft = Color(hex: "6e5b36")
    static let line = Color(hex: "b39c70")
    static let cardBg = Color(hex: "f8f1df")
    static let cardBgMale = Color(hex: "eaf2f0")
    static let cardBgFemale = Color(hex: "f5ece4")
    /// Boundary of an interactive control (card, button, field). WCAG 1.4.11 wants ≥3:1
    /// against every surface the control sits on; this clears paper (3.22), cardBg (3.71)
    /// and btnBg (3.58). Don't lighten it back toward the old c7b389 — that read as 1.58
    /// against paper, which left the cards and buttons effectively edgeless.
    static let cardLine = Color(hex: "927850")
    /// Hover/emphasis weight of `cardLine` (4.46:1 on paper).
    static let cardLineStrong = Color(hex: "7a6238")
    static let cardLineMale = Color(hex: "8fb0a8")
    static let cardLineFemale = Color(hex: "c49a82")
    static let cardRule = Color(hex: "d9c9a4")
    static let accent = Color(hex: "9c4a2f")
    /// Pressed/hover weight of `accent`; white on it is 8.39:1.
    static let accentDeep = Color(hex: "7d3a24")
    // Secondary gold accent, also used for small tracked labels — kept ≥4.5:1 (AA).
    static let accent2 = Color(hex: "775d26")
    static let photoA = Color(hex: "e7dcc2")
    static let photoB = Color(hex: "dccdab")
    static let toolbarBg = Color(hex: "e8ddc4")
    static let toolbarLine = Color(hex: "cdb98f")
    static let panelBg = Color(hex: "f1e8d4")
    static let btnBg = Color(hex: "f4edda")
    /// Hover fill for paper-coloured surfaces. Deliberately *lighter* than the resting
    /// fill: btnBg and cardBg already sit above `paper`, so darkening on hover would
    /// sink them into the page instead of lifting them off it.
    static let btnBgHover = Color(hex: "fdf8ea")
    static let cardBgHover = Color(hex: "fdf9ee")
    static let fieldLine = Color(hex: "d2c09a")
    static let fanA = Color(hex: "f4edd9")
    static let fanB = Color(hex: "ebdfc2")
    static let fanEmpty = Color(hex: "e4d8bf")
    static let fanSel = Color(hex: "edcfa8")
    static let fanLine = Color(hex: "c7b389")
    static let posterBg = Color(hex: "f4ecd6")

    // Map view colors
    static let mapSea = Color(hex: "dde8e4")
    static let mapLand = Color(hex: "f2ead7")
    static let mapBorder = Color(hex: "b8a880")
    static let mapGrid = Color(hex: "c8bea0").opacity(0.4)
    static let mapLine = Color(hex: "8a6d2f").opacity(0.7)
    static let pinBirth = Color(hex: "4a8c6e")
    static let pinDeath = Color(hex: "9c4a2f")
    static let pinBurial = Color(hex: "6b5b95")

    static func display(size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .serif)
    }

    static func body(size: CGFloat) -> Font {
        .system(size: size, design: .serif)
    }

    static func ui(size: CGFloat) -> Font {
        .system(size: size, weight: .medium, design: .serif)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

/// Shared hover/press/disabled behaviour for the sepia controls. `ButtonStyle` cannot
/// hold `@State`, so the styles below wrap their label in this view.
private struct SepiaControlSurface<Label: View>: View {
    let label: Label
    let isPressed: Bool
    let isActive: Bool

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private var fill: Color {
        if isActive { return isPressed || isHovering ? SepiaTheme.accentDeep : SepiaTheme.accent }
        return isHovering ? SepiaTheme.btnBgHover : SepiaTheme.btnBg
    }

    private var stroke: Color {
        if isActive { return isPressed || isHovering ? SepiaTheme.accentDeep : SepiaTheme.accent }
        return isHovering ? SepiaTheme.cardLineStrong : SepiaTheme.cardLine
    }

    var body: some View {
        label
            .foregroundColor(isActive ? .white : SepiaTheme.ink)
            .background(fill)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(stroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
            // Disabled is a real state, not just a dimmer: the fill flattens toward the
            // page so a disabled control reads as part of the paper rather than as a
            // button the user simply failed to hit.
            .opacity(isEnabled ? (isPressed ? 0.82 : 1.0) : 0.4)
            .saturation(isEnabled ? 1 : 0.35)
            .onHover { hovering in
                guard isEnabled else { return }
                if reduceMotion {
                    isHovering = hovering
                } else {
                    withAnimation(.easeOut(duration: 0.15)) { isHovering = hovering }
                }
            }
            .onChange(of: isEnabled) { _, enabled in if !enabled { isHovering = false } }
    }
}

extension View {
    /// The resting chrome of a sepia control. `SepiaButtonStyle` covers Buttons; menus
    /// and text fields can't use a ButtonStyle, and without this they fall back to the
    /// stock macOS look and read as a different design system on the same row.
    func sepiaControlChrome(height: CGFloat = 30) -> some View {
        frame(height: height)
            .background(SepiaTheme.btnBg)
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(SepiaTheme.cardLine, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct SepiaButtonStyle: ButtonStyle {
    var isActive: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        SepiaControlSurface(
            label: configuration.label
                .font(SepiaTheme.ui(size: 12))
                .fontWeight(.semibold)
                .padding(.horizontal, 10)
                .frame(height: 30),
            isPressed: configuration.isPressed,
            isActive: isActive
        )
    }
}

struct SepiaIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SepiaControlSurface(
            label: configuration.label.frame(width: 30, height: 30),
            isPressed: configuration.isPressed,
            isActive: false
        )
    }
}
