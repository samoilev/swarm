import SwarmCore
import SwiftUI

struct MapPrivacySettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.default.rawValue
    @AppStorage(AppLanguage.choiceCompletedKey) private var languageChoiceCompleted = false
    @AppStorage("mapProvider") private var providerRaw = MapProviderSetting.default.rawValue

    var body: some View {
        ZStack {
            LiquidGlassPanelBackground()

            VStack(spacing: 0) {
                LiquidGlassPanelHeader(title: L10n.tr("Настройки Swarm"))
                    .padding(14)

                ScrollView {
                    VStack(alignment: .leading, spacing: 26) {
                        settingsSection(L10n.tr("Язык"), systemImage: "globe") {
                            LiquidGlassActionRow {
                                ForEach(AppLanguage.allCases) { language in
                                    languageButton(language)
                                }
                            }
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

                        settingsSection(L10n.tr("Локальные данные"), systemImage: "internaldrive") {
                            Text(L10n.tr("Поиск мест использует встроенный локальный индекс. Выбранный идентификатор, подпись и координаты сохраняются в GEDCOM, поэтому обновление справочника не перемещает историческое место."))
                                .font(SepiaTheme.body(size: 12.5))
                                .foregroundStyle(SepiaTheme.ink)

                            Text(L10n.tr("Справочник мест основан на GeoNames и охватывает бывший СССР, Европу и всю Северную Америку. Офлайн-карта использует встроенные упрощённые векторы Natural Earth 1:110m (public domain)."))
                                .font(SepiaTheme.ui(size: 11))
                                .foregroundStyle(SepiaTheme.inkSoft)
                        }

                        settingsSection(L10n.tr("Восстановление"), systemImage: "clock.arrow.circlepath") {
                            Text(L10n.tr("Хранятся последние 50 редакций GEDCOM. Удалённые и заменённые файлы доступны 30 дней. Резервная копия перед миграцией v2 не удаляется автоматически."))
                                .font(SepiaTheme.body(size: 12.5))
                                .foregroundStyle(SepiaTheme.ink)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
        }
        .frame(width: 560, height: 590)
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

            Divider()
                .overlay(SepiaTheme.fieldLine)
        }
    }

    @ViewBuilder
    private func languageButton(_ language: AppLanguage) -> some View {
        let isSelected = currentLanguage == language
        choiceButton(
            title: language.displayName,
            subtitle: language == .russian ? "Русский интерфейс" : "English interface",
            isSelected: isSelected
        ) {
            languageBinding.wrappedValue = language
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
        subtitle: String,
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

    private func choiceLabel(title: String, subtitle: String, isSelected: Bool) -> some View {
        HStack(spacing: 7) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(SepiaTheme.ui(size: 11.5))
                    .fontWeight(.semibold)
                Text(subtitle)
                    .font(SepiaTheme.ui(size: 9.5))
                    .opacity(0.82)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 42)
    }

    private var privacyNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(
                currentProvider == .offlineVector
                    ? L10n.tr("Карта, подписи и координаты обрабатываются на этом Mac без сетевых тайлов.")
                    : L10n.tr("Apple Maps загружает сетевые тайлы. Apple может получить область просмотра карты."),
                systemImage: currentProvider == .offlineVector ? "network.slash" : "network"
            )
            .font(SepiaTheme.body(size: 12.5))
            .foregroundStyle(SepiaTheme.ink)

            Text(L10n.tr("Swarm не передаёт Apple имена людей, события, заметки или подписи маркеров. Для Apple Maps передаётся только необходимая самому системному картографическому сервису область просмотра. Переключитесь на офлайн-карту, если не хотите и этого."))
                .font(SepiaTheme.ui(size: 11))
                .foregroundStyle(SepiaTheme.inkSoft)
        }
    }

    private var currentProvider: MapProviderSetting {
        MapProviderSetting(rawValue: providerRaw) ?? .default
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
