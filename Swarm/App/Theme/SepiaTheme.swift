import AppKit
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
    /// Hover weights of the sex card lines. A hovered card must not lose its own hue —
    /// borrowing the neutral `cardLineStrong` made the tint flicker between cool and warm
    /// as the pointer crossed the tree. Darker than the resting line, so contrast only rises.
    static let cardLineMaleStrong = Color(hex: "6e948b")
    static let cardLineFemaleStrong = Color(hex: "a8765a")
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
    /// Hover fills for the sex-tinted cards — each is its own resting tint lifted toward
    /// white, not a swap to the neutral hover cream. Same reasoning as the *Strong lines:
    /// hover should raise a card off the paper, never restate what sex it is.
    static let cardBgMaleHover = Color(hex: "f4faf9")
    static let cardBgFemaleHover = Color(hex: "fdf7f1")
    static let fieldLine = Color(hex: "d2c09a")
    /// Fill of a text input. Was applied as `.colorMultiply` over a system field, which
    /// also dimmed the system placeholder to 3.85:1; it is a real fill now so the
    /// placeholder can be drawn at `inkSoft` (5.64:1 here) instead.
    static let fieldBg = Color(hex: "f5eed8")
    /// Validation and failure text. Reads 6.23:1 on `paper` and 7.18:1 on `cardBg`,
    /// where a raw `.red` sits near 3.4:1 and fights the sepia palette.
    static let danger = Color(hex: "8f2f22")
    static let fanA = Color(hex: "f4edd9")
    static let fanB = Color(hex: "ebdfc2")
    static let fanEmpty = Color(hex: "e4d8bf")
    static let fanSel = Color(hex: "edcfa8")
    static let fanLine = Color(hex: "c7b389")

    // Map view colors
    static let mapLine = Color(hex: "8a6d2f").opacity(0.7)
    static let pinBirth = Color(hex: "4a8c6e")
    static let pinDeath = Color(hex: "9c4a2f")
    static let pinBurial = Color(hex: "6b5b95")

    static func display(size: CGFloat) -> Font {
        .custom("New York", size: size, relativeTo: .title2).weight(.semibold)
    }

    static func body(size: CGFloat) -> Font {
        .custom("New York", size: size, relativeTo: .body)
    }

    static func ui(size: CGFloat) -> Font {
        .custom("New York", size: size, relativeTo: .caption).weight(.medium)
    }
}

private struct SepiaSystemAccessibilityModifier: ViewModifier {
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if contrast == .increased { content.contrast(1.16) }
        else { content }
    }
}

/// The app's motion vocabulary. Kept here beside the colour and control tokens so
/// durations and curves are chosen once rather than re-invented per view.
///
/// Springs are all damped ≥0.86: they settle, they never wobble. An archival record
/// should feel steady under the hand, so nothing here bounces.
enum SepiaMotion {
    /// Press acknowledgement. Under the ~80ms perception threshold, so it reads as instant.
    static let press = Animation.easeOut(duration: 0.10)
    /// Hover lift on a card or control.
    static let hover = Animation.easeOut(duration: 0.14)
    /// Everyday state change: dimming, a badge appearing, a toast, a numeric readout.
    static let state = Animation.easeOut(duration: 0.22)
    /// Selection: the ring settling onto a card.
    static let select = Animation.spring(response: 0.28, dampingFraction: 0.86)
    /// A panel entering or leaving the edge of the window.
    static let panel = Animation.spring(response: 0.34, dampingFraction: 0.90)
    /// The one long beat: every card gliding to a new seat when the tree is re-laid out.
    static let layout = Animation.spring(response: 0.55, dampingFraction: 0.88)
    /// Swapping one full-canvas view for another.
    static let crossfade = Animation.easeInOut(duration: 0.18)
    /// Longest stagger the entrance cascade may span, however tall the tree is.
    static let entranceStagger: Double = 0.30

    /// Delay for something arriving `fraction` of the way through a group's entrance.
    /// Clamped to `entranceStagger`, so nothing ever waits longer than the whole cascade.
    static func stagger(fraction: Double) -> Double {
        entranceStagger * min(max(fraction, 0), 1)
    }

    /// Delay for the nth of `count` siblings arriving as one group — a grid of cards, a
    /// row of nodes. A library of forty trees opens in the same beat as a library of four.
    static func stagger(_ index: Int, of count: Int) -> Double {
        guard count > 1 else { return 0 }
        return stagger(fraction: Double(index) / Double(count - 1))
    }
}

/// Applies an animation unless the user has asked for less motion. Reads the environment
/// itself so callers don't each have to hold `accessibilityReduceMotion` and branch on it.
private struct SepiaMotionModifier<V: Equatable>: ViewModifier {
    let animation: Animation
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Strengthens the custom sepia palette for the system Increase Contrast setting.
    /// Typography uses relative custom fonts above, so Larger Text scales in parallel.
    func sepiaSystemAccessibility() -> some View {
        modifier(SepiaSystemAccessibilityModifier())
    }

    /// `.animation(_:value:)` that collapses to an instant change under Reduce Motion.
    func sepiaMotion(_ animation: Animation, value: some Equatable) -> some View {
        modifier(SepiaMotionModifier(animation: animation, value: value))
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
            .scaleEffect(isPressed && isEnabled ? 0.96 : 1.0)
            .sepiaMotion(SepiaMotion.press, value: isPressed)
            .onHover { hovering in
                guard isEnabled else { return }
                if reduceMotion {
                    isHovering = hovering
                } else {
                    withAnimation(SepiaMotion.hover) { isHovering = hovering }
                }
            }
            .onChange(of: isEnabled) { _, enabled in if !enabled { isHovering = false } }
    }
}

/// Speaks a message to VoiceOver. Used for state the user can't be expected to notice
/// visually — a step change inside a sheet, a record written to disk.
func sepiaAnnounce(_ message: String) {
    guard let window = NSApp.keyWindow else { return }
    NSAccessibility.post(
        element: window,
        notification: .announcementRequested,
        userInfo: [
            .announcement: message,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ]
    )
}

extension View {
    /// The resting chrome of a sepia text input. Replaces `.textFieldStyle(.roundedBorder)`
    /// plus a `.colorMultiply` tint, which multiplied the *whole* rendered field — including
    /// the system placeholder (3.85:1, below AA) and the system focus ring. Here the fill,
    /// the placeholder (`inkSoft`, 5.64:1) and the focus ring (`accent`, 5.27:1 against the
    /// fill) are all drawn deliberately.
    /// `height`, `radius` and `fontSize` are parameters rather than a second copy of this
    /// modifier: the new-tree flow wants a taller, rounder field for its 17pt values, and
    /// a fork would sooner or later drift on the fill or the placeholder colour.
    func sepiaFieldChrome(
        isFocused: Bool,
        placeholder: String = "",
        isEmpty: Bool = false,
        height: CGFloat = 30,
        radius: CGFloat = 6,
        fontSize: CGFloat = 15
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let inset: CGFloat = height >= 40 ? 14 : 9
        return padding(.horizontal, inset)
            .frame(height: height)
            .background {
                ZStack(alignment: .leading) {
                    shape.fill(SepiaTheme.fieldBg)
                    if isEmpty, !placeholder.isEmpty {
                        Text(placeholder)
                            .font(SepiaTheme.body(size: fontSize))
                            .foregroundColor(SepiaTheme.inkSoft)
                            .lineLimit(1)
                            .padding(.horizontal, inset)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
            }
            .overlay(
                shape.strokeBorder(
                    isFocused ? SepiaTheme.accent : SepiaTheme.cardLine,
                    lineWidth: isFocused ? (height >= 40 ? 1.5 : 2) : 1
                )
            )
            .clipShape(shape)
            .shadow(
                color: SepiaTheme.ink.opacity(isFocused && height >= 40 ? 0.08 : 0),
                radius: 8,
                y: 2
            )
            .sepiaMotion(SepiaMotion.state, value: isFocused)
    }

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
