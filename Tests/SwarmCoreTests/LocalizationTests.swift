import Foundation
@testable import SwarmCore
import Testing

struct LocalizationTests {
    @Test func translatesStaticAndInterpolatedCopy() {
        let name = "Anna"

        #expect(L10n.tr("Новое дерево", language: .english) == "New Tree")
        #expect(L10n.tr("Добавлен: \(name)", language: .english) == "Added: Anna")
        #expect(L10n.tr("Добавлен: \(name)", language: .russian) == "Добавлен: Anna")
    }

    @Test func swarmBrandAndMigrationCopyAreBilingual() {
        #expect(L10n.tr("Swarm", language: .russian) == "Swarm")
        #expect(L10n.tr("Swarm", language: .english) == "Swarm")
        #expect(L10n.tr("Проверка старого хранилища", language: .english) == "Check Previous Storage")
    }

    @Test func migratesLegacyLanguagePreferenceOnlyWhenCurrentIsUnset() throws {
        let currentName = "swarm-current-\(UUID().uuidString)"
        let legacyName = "swarm-legacy-\(UUID().uuidString)"
        let current = try #require(UserDefaults(suiteName: currentName))
        let legacy = try #require(UserDefaults(suiteName: legacyName))
        defer {
            UserDefaults.standard.removePersistentDomain(forName: currentName)
            UserDefaults.standard.removePersistentDomain(forName: legacyName)
        }

        legacy.set(AppLanguage.english.rawValue, forKey: AppLanguage.storageKey)
        AppLanguage.migrateLegacyPreferenceIfNeeded(currentDefaults: current, legacyDefaults: legacy)
        #expect(current.string(forKey: AppLanguage.storageKey) == AppLanguage.english.rawValue)

        current.set(AppLanguage.russian.rawValue, forKey: AppLanguage.storageKey)
        AppLanguage.migrateLegacyPreferenceIfNeeded(currentDefaults: current, legacyDefaults: legacy)
        #expect(current.string(forKey: AppLanguage.storageKey) == AppLanguage.russian.rawValue)
    }

    @Test func translatesGeneratedKinshipCopy() {
        #expect(L10n.dynamic("Двоюродная сестра", language: .english) == "First Cousin")
        #expect(L10n.dynamic("5-й предок", language: .english) == "5th-generation ancestor")
        #expect(L10n.dynamic("4-юродный племянник", language: .english) == "3rd cousin once removed")
    }
}
