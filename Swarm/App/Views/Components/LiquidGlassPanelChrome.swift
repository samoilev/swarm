import SwarmCore
import SwiftUI

/// Shared material layer for utility sheets and compact windows. Content stays opaque
/// enough to read; Liquid Glass is reserved for navigation and actions above it.
struct LiquidGlassPanelBackground: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.regularMaterial)
            SepiaTheme.paper.opacity(0.9)
        }
        .ignoresSafeArea()
    }
}

/// The warm paper field the library, the new-tree flow and the language chooser all float
/// their glass over. One gradient with a couple of soft blooms, so the three screens read
/// as three views of one room rather than three flat backgrounds that happen to be beige.
struct SepiaPaperField: View {
    struct Bloom {
        let center: UnitPoint
        let color: Color
        let opacity: Double
        let radius: CGFloat
    }

    var blooms: [Bloom]

    /// Two corners lit: the grid has content across the whole pane, so the light comes
    /// from opposite ends of it.
    static let library: [Bloom] = [
        Bloom(center: UnitPoint(x: 0.12, y: -0.08), color: SepiaTheme.accent, opacity: 0.16, radius: 620),
        Bloom(center: UnitPoint(x: 0.96, y: 1.08), color: SepiaTheme.accent2, opacity: 0.20, radius: 560),
    ]

    /// One bloom above the card that holds the only question on the screen.
    static let single: [Bloom] = [
        Bloom(center: UnitPoint(x: 0.5, y: -0.10), color: SepiaTheme.accent, opacity: 0.14, radius: 520),
    ]

    var body: some View {
        ZStack {
            // `fanEmpty` rather than the prototype's raw hex — the token wins over the
            // HTML, and it is the darkest paper weight the palette already carries.
            LinearGradient(
                colors: [SepiaTheme.panelBg, SepiaTheme.fanEmpty],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            ForEach(Array(blooms.enumerated()), id: \.offset) { _, bloom in
                RadialGradient(
                    colors: [bloom.color.opacity(bloom.opacity), .clear],
                    center: bloom.center,
                    startRadius: 0,
                    endRadius: bloom.radius
                )
            }
        }
        .ignoresSafeArea()
    }
}

/// Small tracked capitals — `LIBRARY`, `STEP 1 OF 2`, `3 GENERATIONS`. The archive's way
/// of labelling something without giving it the weight of a heading.
struct SepiaTrackedLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = SepiaTheme.accent2

    init(_ text: String, size: CGFloat = 10, color: Color = SepiaTheme.accent2) {
        self.text = text
        self.size = size
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(SepiaTheme.ui(size: size))
            .fontWeight(.semibold)
            .tracking(size * 0.2)
            .foregroundStyle(color)
    }
}

/// The app's name in the window toolbar, immediately after the traffic lights, with an
/// optional label saying which room of the app you are standing in. Leading-aligned and
/// never centred: this is the same row the tree workspace draws, not a title bar.
struct SepiaWordmark: View {
    var label: String?

    var body: some View {
        // Centred, not baseline-aligned: the dot is a separator between two names, so it
        // belongs at the optical middle of the wordmark, with the room label beside it —
        // sitting them on the baseline dropped both to the foot of the word.
        HStack(alignment: .center, spacing: 9) {
            Rectangle()
                .fill(SepiaTheme.ink.opacity(0.13))
                .frame(width: 1, height: 26)
                .padding(.trailing, 9)
                .accessibilityHidden(true)

            Text("Swarm")
                .font(SepiaTheme.display(size: 21))
                .foregroundStyle(SepiaTheme.ink)
                .offset(y: 1)

            if let label, !label.isEmpty {
                // Both sit below the mathematical centre, and the label a point further
                // than the dot. The label is all capitals, so it carries no descender and
                // its ink rides high inside its own frame; a circle has no such bias, so
                // the two need different nudges to look level with the wordmark.
                Circle()
                    .fill(SepiaTheme.accent)
                    .frame(width: 4, height: 4)
                    .offset(y: 1.5)
                    .accessibilityHidden(true)

                SepiaTrackedLabel(label)
                    .offset(y: 2.5)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct LiquidGlassPanelHeader: View {
    let title: String
    var subtitle: String?
    var minimumHeight: CGFloat = 58
    var closeLabel: String = L10n.tr("Закрыть")
    var closeDisabled = false
    var onClose: (() -> Void)?

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SepiaTheme.display(size: 20))
                        .fontWeight(.semibold)
                        .foregroundStyle(SepiaTheme.ink)
                        .accessibilityAddTraits(.isHeader)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(SepiaTheme.ui(size: 11))
                            .foregroundStyle(SepiaTheme.inkSoft)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .frame(minHeight: minimumHeight)
                .glassEffect(
                    .regular.tint(SepiaTheme.toolbarBg.opacity(0.22)),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous)
                )

                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(SepiaTheme.ink)
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .disabled(closeDisabled)
                    .help(closeLabel)
                    .accessibilityLabel(closeLabel)
                }
            }
        }
    }
}

struct LiquidGlassActionRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 10) {
                content
            }
        }
    }
}
