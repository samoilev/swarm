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

    /// Every `L10n.tr` literal in the sources must have an English entry. Spot checks
    /// can't prove that, and an untranslated string silently falls back to Russian in
    /// the English interface rather than failing loudly.
    @Test func everyTranslatableLiteralHasAnEnglishEntry() throws {
        let catalogue = try LocalizationCatalogue.load()
        let missing = try LocalizationCatalogue.keysUsedInSources()
            .filter { catalogue[$0] == nil }
            .sorted()

        let report = "No English translation for \(missing.count) key(s):\n" + missing.joined(separator: "\n")
        #expect(missing.isEmpty, "\(report)")
    }
}

/// Reads the shipped English catalogue and the `L10n.tr` call sites straight from the
/// working tree. Test-only, so it locates the repository through `#filePath`.
private enum LocalizationCatalogue {
    static let repositoryRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // SwarmCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repository root

    static func load() throws -> [String: String] {
        let url = repositoryRoot
            .appending(path: "Swarm/Core/Resources/Localization/en.lproj/Localizable.strings")
        let contents = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(from: contents, format: nil)
        return try #require(parsed as? [String: String])
    }

    static func keysUsedInSources() throws -> Set<String> {
        var keys: Set<String> = []
        for file in swiftSources() {
            let source = try String(contentsOf: file, encoding: .utf8)
            var searchFrom = source.startIndex
            while let call = source.range(of: "L10n.tr(", range: searchFrom ..< source.endIndex) {
                searchFrom = call.upperBound
                var index = call.upperBound
                while index < source.endIndex, source[index].isWhitespace {
                    index = source.index(after: index)
                }
                // A non-literal argument (a variable or an already-built Key) has no
                // key to check.
                guard index < source.endIndex, source[index] == "\"" else { continue }
                keys.insert(key(in: source, openingQuote: index))
            }
        }
        return keys
    }

    /// Reads one Swift string literal and rebuilds the key `L10n.Key` produces at
    /// runtime: `%` doubled in literal segments, `%@` for each `\(…)`.
    ///
    /// A regular expression can't do this — an interpolation may contain its own string
    /// literal, as in `L10n.tr("Удалить дерево «\(tree?.name ?? "")»?")`, and the inner
    /// quote would end the match early.
    private static func key(in source: String, openingQuote: String.Index) -> String {
        var key = ""
        var index = source.index(after: openingQuote)

        while index < source.endIndex {
            let character = source[index]
            if character == "\"" { return key }

            if character == "\\" {
                let next = source.index(after: index)
                guard next < source.endIndex else { return key }
                if source[next] == "(" {
                    key += "%@"
                    index = endOfInterpolation(in: source, openParen: next)
                } else {
                    key += unescaped(source[next])
                    index = source.index(after: next)
                }
                continue
            }

            key += character == "%" ? "%%" : String(character)
            index = source.index(after: index)
        }
        return key
    }

    /// Index just past the `)` closing the `\(` that starts at `openParen`, skipping
    /// over nested parentheses and over string literals inside the interpolation.
    private static func endOfInterpolation(in source: String, openParen: String.Index) -> String.Index {
        var depth = 0
        var inString = false
        var index = openParen

        while index < source.endIndex {
            let character = source[index]
            if inString {
                if character == "\\" {
                    index = source.index(after: index)
                } else if character == "\"" {
                    inString = false
                }
            } else if character == "\"" {
                inString = true
            } else if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth == 0 { return source.index(after: index) }
            }
            index = source.index(after: index)
        }
        return source.endIndex
    }

    private static func swiftSources() -> [URL] {
        let root = repositoryRoot.appending(path: "Swarm")
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }
        return files.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }

    private static func unescaped(_ character: Character) -> String {
        switch character {
        case "n": "\n"
        case "t": "\t"
        default: String(character)
        }
    }
}
