@testable import FamilyTreeCore
import Testing

struct LocalizationTests {
    @Test func translatesStaticAndInterpolatedCopy() {
        let name = "Anna"

        #expect(L10n.tr("Новое дерево", language: .english) == "New Tree")
        #expect(L10n.tr("Добавлен: \(name)", language: .english) == "Added: Anna")
        #expect(L10n.tr("Добавлен: \(name)", language: .russian) == "Добавлен: Anna")
    }

    @Test func translatesGeneratedKinshipCopy() {
        #expect(L10n.dynamic("Двоюродная сестра", language: .english) == "First Cousin")
        #expect(L10n.dynamic("5-й предок", language: .english) == "5th-generation ancestor")
        #expect(L10n.dynamic("4-юродный племянник", language: .english) == "3rd cousin once removed")
    }
}
