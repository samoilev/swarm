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

    private func name(from a: String, to b: String, in f: Fixture, language: AppLanguage) -> String? {
        RelationshipCalculator(tree: f.tree)
            .relationship(from: f.people[a]!, to: f.people[b]!, language: language)?
            .name
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

    @Test func englishRelationshipsAreFormattedFromDescriptors() {
        let f = Fixture()
        #expect(name(from: "me", to: "father", in: f, language: .english) == "Father")
        #expect(name(from: "me", to: "sister", in: f, language: .english) == "Sister")
        #expect(name(from: "me", to: "halfBro", in: f, language: .english) == "Paternal Half-brother")
        #expect(name(from: "me", to: "cousin", in: f, language: .english) == "First Cousin")
        #expect(name(from: "me", to: "wifeFather", in: f, language: .english) == "Father-in-law")
        #expect(name(from: "father", to: "wife", in: f, language: .english) == "Daughter-in-law")
        #expect(KinshipFormatter(language: .english).label(
            for: .parent(sex: .unknown, kind: .biological)
        ) == "Parent")
        #expect(KinshipFormatter(language: .english).label(
            for: .descendant(generation: 2, sex: .unknown)
        ) == "Grandchild")
    }

    @Test func firstCousinTwiceRemovedWorksInBothDirections() {
        let tree = FamilyTree(name: "Removed cousins")
        let root = Person(givenNames: "Root", sex: .unknown)
        let a1 = Person(givenNames: "A1", sex: .unknown)
        let b1 = Person(givenNames: "B1", sex: .unknown)
        let subject = Person(givenNames: "Subject", sex: .unknown)
        let b2 = Person(givenNames: "B2", sex: .unknown)
        let b3 = Person(givenNames: "B3", sex: .unknown)
        let cousin = Person(givenNames: "Cousin", sex: .unknown)
        tree.people = [root, a1, b1, subject, b2, b3, cousin]
        tree.parentLinks = [
            ParentLink(parentID: root.id, childID: a1.id),
            ParentLink(parentID: root.id, childID: b1.id),
            ParentLink(parentID: a1.id, childID: subject.id),
            ParentLink(parentID: b1.id, childID: b2.id),
            ParentLink(parentID: b2.id, childID: b3.id),
            ParentLink(parentID: b3.id, childID: cousin.id),
        ]

        let calculator = RelationshipCalculator(tree: tree)
        let younger = calculator.relationship(from: subject, to: cousin, language: .english)
        let older = calculator.relationship(from: cousin, to: subject, language: .english)
        #expect(younger?.name == "First Cousin Twice Removed")
        #expect(older?.name == "First Cousin Twice Removed")
        #expect(younger?.descriptor == .cousin(
            degree: 1,
            removed: 2,
            direction: .younger,
            sex: .unknown
        ))
        #expect(older?.descriptor == .cousin(
            degree: 1,
            removed: 2,
            direction: .older,
            sex: .unknown
        ))
    }

    @Test func bilingualFormatterCoversGenerationsParentageNeutralSexAndRemovedCousins() {
        let english = KinshipFormatter(language: .english)
        let russian = KinshipFormatter(language: .russian)

        for generation in 1 ... 6 {
            #expect(!english.label(for: .ancestor(generation: generation, sex: .unknown)).isEmpty)
            #expect(!english.label(for: .descendant(generation: generation, sex: .unknown)).isEmpty)
            #expect(!russian.label(for: .ancestor(generation: generation, sex: .unknown)).isEmpty)
            #expect(!russian.label(for: .descendant(generation: generation, sex: .unknown)).isEmpty)
        }
        for kind in ParentageKind.allCases {
            #expect(!english.label(for: .parent(sex: .unknown, kind: kind)).isEmpty)
            #expect(!english.label(for: .child(sex: .unknown, kind: kind)).isEmpty)
            #expect(!russian.label(for: .parent(sex: .unknown, kind: kind)).isEmpty)
            #expect(!russian.label(for: .child(sex: .unknown, kind: kind)).isEmpty)
        }

        let ordinals = ["First", "Second", "Third", "Fourth"]
        let removals = ["Once", "Twice", "Three Times"]
        for degree in 1 ... 4 {
            for removed in 1 ... 3 {
                for direction in [
                    KinshipDescriptor.CousinDirection.younger,
                    .older,
                ] {
                    let descriptor = KinshipDescriptor.cousin(
                        degree: degree,
                        removed: removed,
                        direction: direction,
                        sex: .unknown
                    )
                    #expect(
                        english.label(for: descriptor)
                            == "\(ordinals[degree - 1]) Cousin \(removals[removed - 1]) Removed"
                    )
                    #expect(!russian.label(for: descriptor).isEmpty)
                }
            }
        }
    }

    @Test func calculatedLineageKeepsEveryParentAndParentageKind() throws {
        let expected: [(ParentageKind, String)] = [
            (.biological, "Grandmother"),
            (.adoptive, "Grandmother through adoption"),
            (.foster, "Grandmother through foster care"),
            (.step, "Grandmother through a step-family connection"),
            (.uncertain, "Grandmother through uncertain parentage"),
        ]

        for (kind, label) in expected {
            let tree = FamilyTree(name: kind.rawValue)
            let subject = Person(givenNames: "Subject", sex: .unknown)
            let parent = Person(givenNames: "Parent", sex: .male)
            let otherFather = Person(givenNames: "Other", sex: .male)
            let grandmother = Person(givenNames: "Grandmother", sex: .female)
            tree.people = [subject, parent, otherFather, grandmother]
            tree.parentLinks = [
                ParentLink(parentID: parent.id, childID: subject.id, kind: kind),
                ParentLink(parentID: otherFather.id, childID: subject.id, kind: .biological),
                ParentLink(parentID: grandmother.id, childID: parent.id, kind: .biological),
            ]

            let index = FamilyIndex(tree: tree)
            #expect(index.parentEdges(of: subject.id).count == 2)
            #expect(
                RelationshipCalculator(tree: tree)
                    .relationship(from: subject, to: parent, language: .english)?
                    .descriptor == .parent(sex: .male, kind: kind)
            )
            let relationship = try #require(
                RelationshipCalculator(tree: tree)
                    .relationship(from: subject, to: grandmother, language: .english)
            )
            #expect(relationship.name == label)

            let lineage = LineageCalculator(index: index).compute(for: subject, language: .english)
            #expect(lineage.ids.contains(parent.id))
            #expect(lineage.ids.contains(otherFather.id))
            #expect(lineage.descriptors[parent.id] == .parent(sex: .male, kind: kind))
            #expect(lineage.labels[grandmother.id] == label)
        }
    }
}
