import SwarmCore
import SwiftUI

struct MapPrivacySettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.default.rawValue
    @AppStorage(AppLanguage.choiceCompletedKey) private var languageChoiceCompleted = false
    @AppStorage("mapProvider") private var providerRaw = MapProviderSetting.default.rawValue
    @AppStorage(UIScale.storageKey) private var scaleRaw = UIScale.default.rawValue

    var body: some View {
        ZStack {
            LiquidGlassPanelBackground()

            VStack(alignment: .leading, spacing: 26) {
                // The window frame carries no title, so the panel names itself once,
                // centred over both sections.
                Text(L10n.tr("Настройки"))
                    .font(SepiaTheme.display(size: 26))
                    .foregroundStyle(SepiaTheme.ink)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)

                settingsSection(L10n.tr("Язык"), systemImage: "globe") {
                    LiquidGlassActionRow {
                        ForEach(AppLanguage.allCases) { language in
                            languageButton(language)
                        }
                    }
                }

                settingsSection(L10n.tr("Размер интерфейса"), systemImage: "textformat.size") {
                    LiquidGlassActionRow {
                        ForEach(UIScale.allCases) { scale in
                            scaleButton(scale)
                        }
                    }
                    .id(languageRaw)
                }

                settingsSection(L10n.tr("Карта и конфиденциальность"), systemImage: "map") {
                    LiquidGlassActionRow {
                        ForEach(MapProviderSetting.allCases) { provider in
                            providerButton(provider)
                        }
                    }
                    .id(languageRaw)

                    privacyNotice
                }
            }
            .padding(SepiaTheme.scaled(24))
        }
        // Two sections of fixed-height controls: the window takes its height from them
        // rather than reserving room for content that is no longer here.
        .frame(width: SepiaTheme.scaledPanel(560, axis: .horizontal))
        // Blanks the tab/window title macOS would otherwise fill with "Swarm Settings".
        .navigationTitle(Text(verbatim: ""))
    }

    private func settingsSection(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(SepiaTheme.display(size: 16))
                .foregroundStyle(SepiaTheme.ink)
                .accessibilityAddTraits(.isHeader)

            content()
        }
    }

    @ViewBuilder
    private func languageButton(_ language: AppLanguage) -> some View {
        let isSelected = currentLanguage == language
        choiceButton(
            title: language.displayName,
            subtitle: nil,
            isSelected: isSelected
        ) {
            languageBinding.wrappedValue = language
        }
    }

    private func scaleButton(_ scale: UIScale) -> some View {
        // The percentage alone. Five names side by side truncate at any width this
        // panel can reasonably take, and a clipped "Очень кр…" says less than "130%".
        choiceButton(
            title: scale.summary,
            subtitle: nil,
            isSelected: currentScale == scale
        ) {
            scaleBinding.wrappedValue = scale
        }
    }

    @ViewBuilder
    private func providerButton(_ provider: MapProviderSetting) -> some View {
        let isSelected = currentProvider == provider
        choiceButton(
            title: provider.displayName,
            subtitle: provider.summary,
            isSelected: isSelected
        ) {
            providerBinding.wrappedValue = provider
        }
    }

    @ViewBuilder
    private func choiceButton(
        title: String,
        subtitle: String?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if isSelected {
            Button(action: action) {
                choiceLabel(title: title, subtitle: subtitle, isSelected: true)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.small)
            .tint(SepiaTheme.accent)
            .accessibilityAddTraits(.isSelected)
        } else {
            Button(action: action) {
                choiceLabel(title: title, subtitle: subtitle, isSelected: false)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.roundedRectangle(radius: 12))
            .controlSize(.small)
        }
    }

    private func choiceLabel(title: String, subtitle: String?, isSelected: Bool) -> some View {
        HStack(spacing: SepiaTheme.scaled(7)) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(SepiaTheme.icon(size: 12, weight: .semibold))
                .frame(width: SepiaTheme.scaled(15))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SepiaTheme.ui(size: 11.5))
                    .fontWeight(.semibold)
                if let subtitle {
                    Text(subtitle)
                        .font(SepiaTheme.ui(size: 9.5))
                        .opacity(0.82)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 4)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, SepiaTheme.scaled(7))
        .frame(maxWidth: .infinity, minHeight: SepiaTheme.scaled(42))
    }

    private var privacyNotice: some View {
        Label(
            currentProvider == .offlineVector
                ? L10n.tr("Ничего не уходит в сеть.")
                : L10n.tr("Apple видит область просмотра карты."),
            systemImage: currentProvider == .offlineVector ? "network.slash" : "network"
        )
        .font(SepiaTheme.body(size: 12.5))
        .foregroundStyle(SepiaTheme.ink)
    }

    private var currentProvider: MapProviderSetting {
        MapProviderSetting(rawValue: providerRaw) ?? .default
    }

    private var currentScale: UIScale {
        UIScale(rawValue: scaleRaw) ?? .default
    }

    private var currentLanguage: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? .default
    }

    private var providerBinding: Binding<MapProviderSetting> {
        Binding(
            get: { currentProvider },
            set: { providerRaw = $0.rawValue }
        )
    }

    /// The multiplier is written here, at the point of mutation, rather than from an
    /// `.onChange` on the stored value: the `.id(scaleRaw)` bumps that re-run every body
    /// ride on the same update, and this way the global is already correct when they do.
    private var scaleBinding: Binding<UIScale> {
        Binding(
            get: { currentScale },
            set: {
                SepiaTheme.scale = CGFloat($0.factor)
                scaleRaw = $0.rawValue
            }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { currentLanguage },
            set: {
                languageRaw = $0.rawValue
                languageChoiceCompleted = true
            }
        )
    }
}
