import Foundation
@testable import SwarmCore
import Testing

/// Kinship naming coverage. Builds one tree spanning blood, half-blood, cousin and
/// in-law relations, then asserts the Russian term RelationshipCalculator returns.
struct RelationshipTests {

    private final class Fixture {
        let tree = FamilyTree(name: "Род")
        var people: [String: Person] = [:]

        func person(_ key: String, _ given: String, _ sex: Person.Sex) -> Person {
            let p = Person(givenNames: given, surname: "Тест", sex: sex)
            people[key] = p
            tree.people.append(p)
            return p
        }

        init() {
            let gf = person("gf", "Дед", .male)
            let gm = person("gm", "Баба", .female)
            let father = person("father", "Отец", .male)
            let uncle = person("uncle", "Дядя", .male)
            let uncleWife = person("uncleWife", "Тётя", .female)
            let mother = person("mother", "Мать", .female)
            let me = person("me", "Я", .male)
            let bro = person("bro", "Брат", .male)
            let sister = person("sister", "Сестра", .female)
            let wife = person("wife", "Жена", .female)
            let son = person("son", "Сын", .male)
            let stepmother = person("stepmother", "Мачеха", .female)
            let halfBro = person("halfBro", "Полубрат", .male)
            let cousin = person("cousin", "Кузина", .female)
            let wifeFather = person("wifeFather", "ТестьО", .male)
            let wifeMother = person("wifeMother", "ТёщаМ", .female)
            let wifeBro = person("wifeBro", "Шурин", .male)
            let wifeSis = person("wifeSis", "Свояченица", .female)
            let sisterHusband = person("sisterHusband", "ЗятьМ", .male)
            let nephew = person("nephew", "Племяш", .male)

            tree.unions = [
                Union(partner1Id: gf.id, partner2Id: gm.id, childrenIds: [father.id, uncle.id]),
                Union(partner1Id: father.id, partner2Id: mother.id, childrenIds: [me.id, bro.id, sister.id]),
                Union(partner1Id: me.id, partner2Id: wife.id, childrenIds: [son.id]),
                Union(partner1Id: father.id, partner2Id: stepmother.id, childrenIds: [halfBro.id]),
                Union(partner1Id: uncle.id, partner2Id: uncleWife.id, childrenIds: [cousin.id]),
                Union(partner1Id: wifeFather.id, partner2Id: wifeMother.id, childrenIds: [wife.id, wifeBro.id, wifeSis.id]),
                Union(partner1Id: sisterHusband.id, partner2Id: sister.id, childrenIds: [nephew.id]),
            ]
        }
    }

    private func name(from a: String, to b: String, in f: Fixture) -> String? {
        RelationshipCalculator(tree: f.tree).relationship(from: f.people[a]!, to: f.people[b]!)?.name
    }

    @Test func directAncestorsAndDescendants() {
        let f = Fixture()
        #expect(name(from: "me", to: "father", in: f) == "Отец")
        #expect(name(from: "me", to: "mother", in: f) == "Мать")
        #expect(name(from: "me", to: "gf", in: f) == "Дед")
        #expect(name(from: "me", to: "gm", in: f) == "Бабушка")
        #expect(name(from: "me", to: "son", in: f) == "Сын")
    }

    @Test func siblingsFullAndHalf() {
        let f = Fixture()
        #expect(name(from: "me", to: "sister", in: f) == "Сестра")
        // Shares only the father → единокровный.
        #expect(name(from: "me", to: "halfBro", in: f) == "Единокровный брат")
    }

    @Test func unclesAndCousins() {
        let f = Fixture()
        #expect(name(from: "me", to: "uncle", in: f) == "Дядя")
        #expect(name(from: "me", to: "cousin", in: f) == "Двоюродная сестра")
    }

    @Test func nephewAndSpouse() {
        let f = Fixture()
        #expect(name(from: "me", to: "nephew", in: f) == "Племянник")
        #expect(name(from: "me", to: "wife", in: f) == "Жена")
    }

    @Test func inLawBrother() {
        let f = Fixture()
        // Wife's brother, from a male subject → Шурин.
        #expect(name(from: "me", to: "wifeBro", in: f) == "Шурин")
    }

    /// The full in-law matrix: every named term, from both subject sexes.
    /// (свёкор/свекровь = husband's parents, viewed by the wife;
    ///  тесть/тёща = wife's parents, viewed by the husband;
    ///  деверь/золовка = husband's siblings; шурин/свояченица = wife's siblings;
    ///  зять/невестка = daughter's/sister's husband, son's/brother's wife.)
    @Test func inLawMatrix() {
        let f = Fixture()
        let cases: [(from: String, to: String, expected: String)] = [
            // Spouse's parents
            ("me", "wifeFather", "Тесть"),
            ("me", "wifeMother", "Тёща"),
            ("wife", "father", "Свёкор"),
            ("wife", "mother", "Свекровь"),
            // Spouse's siblings
            ("me", "wifeBro", "Шурин"),
            ("me", "wifeSis", "Свояченица"),
            ("wife", "bro", "Деверь"),
            ("wife", "sister", "Золовка"),
            // Child's / sibling's spouse
            ("father", "wife", "Невестка (сноха)"),
            ("father", "sisterHusband", "Зять (муж дочери)"),
            ("me", "sisterHusband", "Зять (муж сестры)"),
            ("father", "uncleWife", "Невестка (жена брата)"),
        ]
        for c in cases {
            #expect(name(from: c.from, to: c.to, in: f) == c.expected,
                    "\(c.from) → \(c.to) должен быть «\(c.expected)»")
        }
    }

    @Test func unrelatedPeopleReportNoLink() throws {
        let f = Fixture()
        let stranger = Person(givenNames: "Чужак", surname: "Нет", sex: .male)
        f.tree.people.append(stranger)
        let result = try RelationshipCalculator(tree: f.tree).relationship(from: #require(f.people["me"]), to: stranger)
        #expect(result?.name == "Связь не найдена")
    }
}
