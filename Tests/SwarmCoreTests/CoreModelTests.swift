import Foundation
@testable import SwarmCore
import Testing

/// Lineage labelling, path finding, person derivations, and Codable persistence.
struct CoreModelTests {

    /// gf+gm → dad; dad+mom → me, sis; me+spouse → son.
    private func threeGenerationTree() -> (FamilyTree, [String: Person]) {
        let gf = Person(givenNames: "Дед", sex: .male)
        let gm = Person(givenNames: "Баба", sex: .female)
        let dad = Person(givenNames: "Папа", sex: .male)
        let mom = Person(givenNames: "Мама", sex: .female)
        let me = Person(givenNames: "Я", sex: .male)
        let sis = Person(givenNames: "Сестра", sex: .female)
        let spouse = Person(givenNames: "Жена", sex: .female)
        let son = Person(givenNames: "Сын", sex: .male)
        let t = FamilyTree(name: "T")
        t.people = [gf, gm, dad, mom, me, sis, spouse, son]
        t.unions = [
            Union(partner1Id: gf.id, partner2Id: gm.id, childrenIds: [dad.id]),
            Union(partner1Id: dad.id, partner2Id: mom.id, childrenIds: [me.id, sis.id]),
            Union(partner1Id: me.id, partner2Id: spouse.id, childrenIds: [son.id]),
        ]
        t.homePersonId = me.id
        return (t, ["gf": gf, "gm": gm, "dad": dad, "mom": mom, "me": me, "sis": sis, "spouse": spouse, "son": son])
    }

    @Test func lineageLabelsAncestorsDescendantsAndSpouse() throws {
        let (t, p) = threeGenerationTree()
        let result = try LineageCalculator(index: FamilyIndex(tree: t)).compute(for: #require(p["me"]))
        #expect(try result.labels[#require(p["me"]?.id)] == "Я")
        #expect(try result.labels[#require(p["dad"]?.id)] == "Отец")
        #expect(try result.labels[#require(p["mom"]?.id)] == "Мать")
        #expect(try result.labels[#require(p["gf"]?.id)] == "Дедушка")
        #expect(try result.labels[#require(p["gm"]?.id)] == "Бабушка")
        #expect(try result.labels[#require(p["son"]?.id)] == "Сын")
        #expect(try result.labels[#require(p["spouse"]?.id)] == "Жена")
        // A sibling is not part of direct lineage.
        #expect(try result.ids.contains(#require(p["sis"]?.id)) == false)
    }

    @Test func pathFinderConnectsMeToGrandfather() throws {
        let (t, p) = threeGenerationTree()
        let finder = RelationshipPathFinder(index: FamilyIndex(tree: t))
        let result = try finder.findPath(from: #require(p["me"]?.id), to: #require(p["gf"]?.id))
        #expect(result != nil)
        #expect(result?.path.first == p["me"]!.id)
        #expect(result?.path.last == p["gf"]!.id)
        #expect(result?.path.count == 3) // me → dad → gf
        #expect(try result?.ids.contains(#require(p["dad"]?.id)) == true)
    }

    @Test func personDerivedNamesAndLifespan() {
        let deceased = Person(
            givenNames: "Иван", patronymic: "Петрович", surname: "Сидоров", sex: .male,
            birthDate: "1900", deathDate: "1970", isLiving: false
        )
        #expect(deceased.fullName == "Иван Петрович Сидоров")
        #expect(deceased.listName == "Сидоров Иван Петрович")
        #expect(deceased.lifespan.contains("1900"))
        #expect(deceased.lifespan.contains("1970"))

        let maiden = Person(givenNames: "Анна", surname: "Сидорова", maidenName: "Иванова", sex: .female)
        #expect(maiden.displaySurname == "Сидорова")
        let living = Person(givenNames: "Пётр", surname: "Сидоров", birthDate: "1990", isLiving: true)
        #expect(living.lifespan.hasPrefix("р. 1990"))
    }

    @Test func familyTreeJSONRoundTrips() throws {
        let (t, p) = threeGenerationTree()
        // Exercises Person/Union/FamilyTree Codable (the legacy JSON migration path).
        let data = try JSONEncoder().encode(t)
        let decoded = try JSONDecoder().decode(FamilyTree.self, from: data)
        #expect(decoded.people.count == t.people.count)
        #expect(decoded.unions.count == t.unions.count)
        #expect(decoded.homePersonId == p["me"]!.id)
        let decodedMe = decoded.people.first { $0.id == p["me"]!.id }
        #expect(decodedMe?.givenNames == "Я")
        let idx = FamilyIndex(tree: decoded)
        #expect(try idx.mergedParentIds(#require(p["me"]?.id)).father == p["dad"]!.id)
    }

    @Test func attachmentFormatAndImageDetection() {
        let pdf = Attachment(storedName: "x.pdf", originalName: "Документ.pdf")
        #expect(pdf.format == "PDF")
        #expect(pdf.isImage == false)
        let jpg = Attachment(storedName: "y.jpg", originalName: "Фото.JPG")
        #expect(jpg.isImage == true)
    }
}
