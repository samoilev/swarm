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

            Form {
                Section {
                    LabeledContent {
                        languagePicker
                    } label: {
                        rowLabel(L10n.tr("Язык интерфейса"))
                    }

                    LabeledContent {
                        scaleSlider
                    } label: {
                        rowLabel(L10n.tr("Размер интерфейса"))
                    }
                } header: {
                    SepiaTrackedLabel(L10n.tr("Общие"))
                }

                Section {
                    LabeledContent {
                        providerPicker
                    } label: {
                        rowLabel(L10n.tr("Карта"))
                    }
                } header: {
                    SepiaTrackedLabel(L10n.tr("Карта и конфиденциальность"))
                } footer: {
                    privacyNotice
                }
            }
            .formStyle(.grouped)
            // The paper field behind the form is the window's background; the grouped
            // style would otherwise paint its own over it.
            .scrollContentBackground(.hidden)
            .tint(SepiaTheme.accent)
            // `L10n.tr` reads the stored language at call time, so the labels only pick
            // up a new one when the whole form is rebuilt.
            .id(languageRaw)
        }
        .frame(
            width: SepiaTheme.scaledPanel(520, axis: .horizontal),
            height: SepiaTheme.scaledPanel(250, axis: .vertical)
        )
        // The window frame carries the name now that the pane no longer repeats it;
        // left unset, macOS fills the title bar with "Swarm Settings".
        .navigationTitle(Text(L10n.tr("Настройки")))
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(SepiaType.body)
            .foregroundStyle(SepiaTheme.ink)
    }

    private var languagePicker: some View {
        Picker(selection: languageBinding) {
            ForEach(AppLanguage.allCases) { language in
                Text(language.displayName).tag(language)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: SepiaTheme.scaled(180))
    }

    /// The five steps ride one slider rather than five buttons: the setting is a scale,
    /// and a row of percentages that had to lose their names to fit said so less clearly.
    private var scaleSlider: some View {
        HStack(spacing: SepiaTheme.scaled(12)) {
            Slider(value: scaleIndexBinding, in: 0 ... Double(UIScale.allCases.count - 1), step: 1)
                .frame(width: SepiaTheme.scaled(170))
                .accessibilityLabel(Text(L10n.tr("Размер интерфейса")))
                .accessibilityValue(Text(currentScale.summary))

            Text(currentScale.summary)
                .font(SepiaType.control)
                .monospacedDigit()
                .foregroundStyle(SepiaTheme.inkSoft)
                .frame(width: SepiaTheme.scaled(38), alignment: .trailing)
                .accessibilityHidden(true)
        }
    }

    private var providerPicker: some View {
        Picker(selection: providerBinding) {
            ForEach(MapProviderSetting.allCases) { provider in
                Text(provider.displayName).tag(provider)
            }
        } label: {
            EmptyView()
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        // The form's accent tint reaches a menu picker's own label, and a provider name
        // in accent red reads as a link rather than as the current value.
        .tint(SepiaTheme.ink)
    }

    /// The chosen provider's own summary plus what it costs in privacy: the menu shows
    /// only the two names, so the sentence under the section carries the rest.
    private var privacyNotice: some View {
        Label(
            "\(currentProvider.summary) \(privacySummary)",
            systemImage: currentProvider == .offlineVector ? "network.slash" : "network"
        )
        .font(SepiaType.label)
        .foregroundStyle(SepiaTheme.inkSoft)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var privacySummary: String {
        currentProvider == .offlineVector
            ? L10n.tr("Ничего не уходит в сеть.")
            : L10n.tr("Apple видит область просмотра карты.")
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

    /// The slider moves over the step's position, not its factor: the five factors are
    /// unevenly spaced, so a continuous slider over them would drag unevenly too.
    private var scaleIndexBinding: Binding<Double> {
        Binding(
            get: { Double(UIScale.allCases.firstIndex(of: currentScale) ?? 0) },
            set: { index in
                let position = min(max(Int(index.rounded()), 0), UIScale.allCases.count - 1)
                scaleBinding.wrappedValue = UIScale.allCases[position]
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
