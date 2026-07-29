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
