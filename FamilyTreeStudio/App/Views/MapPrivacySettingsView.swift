import FamilyTreeCore
import SwiftUI

struct MapPrivacySettingsView: View {
    @AppStorage("mapProvider") private var providerRaw = MapProviderSetting.default.rawValue

    var body: some View {
        Form {
            Section("Карта и конфиденциальность") {
                Picker("Провайдер карты", selection: providerBinding) {
                    ForEach(MapProviderSetting.allCases) { provider in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                            Text(provider.summary).font(.caption).foregroundColor(.secondary)
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)

                if providerRaw == MapProviderSetting.offlineVector.rawValue {
                    Label("Карта, подписи и координаты обрабатываются на этом Mac без сетевых тайлов.", systemImage: "network.slash")
                        .foregroundColor(.secondary)
                } else {
                    Label("Apple Maps загружает сетевые тайлы. Apple может получить область просмотра карты.", systemImage: "network")
                        .foregroundColor(.secondary)
                }

                Text("FamilyTreeStudio не передаёт Apple имена людей, события, заметки или подписи маркеров. Для Apple Maps передаётся только необходимая самому системному картографическому сервису область просмотра. Переключитесь на офлайн-карту, если не хотите и этого.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Локальные данные") {
                Text("Поиск мест использует встроенный локальный индекс. Выбранный идентификатор, подпись и координаты сохраняются в GEDCOM, поэтому обновление справочника не перемещает историческое место.")
                Text("Справочник мест основан на GeoNames; в приложении хранится локальная производная выборка. Офлайн-карта использует встроенные упрощённые векторы Natural Earth 1:110m (public domain).")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Восстановление") {
                Text("Хранятся последние 50 редакций GEDCOM. Удалённые и заменённые файлы доступны 30 дней. Резервная копия перед миграцией v2 не удаляется автоматически.")
                    .font(.caption)
            }
        }
        .formStyle(.grouped)
        .padding(16)
        .frame(width: 520, height: 440)
    }

    private var providerBinding: Binding<MapProviderSetting> {
        Binding(
            get: { MapProviderSetting(rawValue: providerRaw) ?? .default },
            set: { providerRaw = $0.rawValue }
        )
    }
}
