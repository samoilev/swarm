import SwarmCore
import SwiftUI

struct MapPrivacySettingsView: View {
    @AppStorage(AppLanguage.storageKey) private var languageRaw = AppLanguage.default.rawValue
    @AppStorage(AppLanguage.choiceCompletedKey) private var languageChoiceCompleted = false
    @AppStorage("mapProvider") private var providerRaw = MapProviderSetting.default.rawValue

    var body: some View {
        Form {
            Section(L10n.tr("Язык")) {
                Picker(L10n.tr("Язык интерфейса"), selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Section(L10n.tr("Карта и конфиденциальность")) {
                Picker(L10n.tr("Провайдер карты"), selection: providerBinding) {
                    ForEach(MapProviderSetting.allCases) { provider in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                            Text(provider.summary).font(.caption).foregroundColor(.secondary)
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)
                .id(languageRaw)

                if providerRaw == MapProviderSetting.offlineVector.rawValue {
                    Label(L10n.tr("Карта, подписи и координаты обрабатываются на этом Mac без сетевых тайлов."), systemImage: "network.slash")
                        .foregroundColor(.secondary)
                } else {
                    Label(L10n.tr("Apple Maps загружает сетевые тайлы. Apple может получить область просмотра карты."), systemImage: "network")
                        .foregroundColor(.secondary)
                }

                Text(L10n.tr("Swarm не передаёт Apple имена людей, события, заметки или подписи маркеров. Для Apple Maps передаётся только необходимая самому системному картографическому сервису область просмотра. Переключитесь на офлайн-карту, если не хотите и этого."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L10n.tr("Локальные данные")) {
                Text(L10n.tr("Поиск мест использует встроенный локальный индекс. Выбранный идентификатор, подпись и координаты сохраняются в GEDCOM, поэтому обновление справочника не перемещает историческое место."))
                Text(L10n.tr("Справочник мест основан на GeoNames и охватывает бывший СССР, Европу и всю Северную Америку. Офлайн-карта использует встроенные упрощённые векторы Natural Earth 1:110m (public domain)."))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(L10n.tr("Восстановление")) {
                Text(L10n.tr("Хранятся последние 50 редакций GEDCOM. Удалённые и заменённые файлы доступны 30 дней. Резервная копия перед миграцией v2 не удаляется автоматически."))
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 520, height: 540)
    }

    private var providerBinding: Binding<MapProviderSetting> {
        Binding(
            get: { MapProviderSetting(rawValue: providerRaw) ?? .default },
            set: { providerRaw = $0.rawValue }
        )
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { AppLanguage(rawValue: languageRaw) ?? .default },
            set: {
                languageRaw = $0.rawValue
                languageChoiceCompleted = true
            }
        )
    }
}
