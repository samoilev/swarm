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
        #expect(try result.connections.contains(FamilyConnection(
            #require(p["me"]?.id),
            #require(p["dad"]?.id)
        )))
        #expect(try result.connections.contains(FamilyConnection(
            #require(p["me"]?.id),
            #require(p["son"]?.id)
        )))
        #expect(try result.connections.contains(FamilyConnection(
            #require(p["me"]?.id),
            #require(p["spouse"]?.id)
        )))
        #expect(try result.connections.contains(FamilyConnection(
            #require(p["me"]?.id),
            #require(p["sis"]?.id)
        )) == false)
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
        #expect(result?.connections.count == 2)
        #expect(try result?.connections == [
            FamilyConnection(#require(p["me"]?.id), #require(p["dad"]?.id)),
            FamilyConnection(#require(p["dad"]?.id), #require(p["gf"]?.id)),
        ])
    }

    @Test func personDerivedNamesAndLifespan() {
        let deceased = Person(
            givenNames: "Иван", patronymic: "Петрович", surname: "Сидоров", sex: .male,
            birthDate: "1900", deathDate: "1970", isLiving: false
        )
        #expect(deceased.fullName == "Иван Петрович Сидоров")
        #expect(deceased.listName == "Сидоров Иван Петрович")
        #expect(deceased.displayName(language: .russian) == "Сидоров Иван Петрович")
        #expect(deceased.displayName(language: .english) == "Иван Петрович Сидоров")
        #expect(deceased.sortName(language: .english).hasPrefix("сидоров"))
        #expect(deceased.lifespan.contains("1900"))
        #expect(deceased.lifespan.contains("1970"))

        let maiden = Person(givenNames: "Анна", surname: "Сидорова", maidenName: "Иванова", sex: .female)
        #expect(maiden.displaySurname == "Сидорова")
        let living = Person(givenNames: "Пётр", surname: "Сидоров", birthDate: "1990", isLiving: true)
        #expect(living.lifespan.hasPrefix("р. 1990"))
        // Deceased with unknown death date: never age up to today.
        let deceasedNoDeathDate = Person(givenNames: "Фома", surname: "Сидоров", birthDate: "1900", isLiving: false)
        #expect(deceasedNoDeathDate.lifespan == "1900–?")
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

    @Test func webLinkNormalizesAndRefusesUnsafeSchemes() {
        let bare = WebLink(url: "  archive.org/details/x  ")
        #expect(WebLink.normalize(bare.url) == "https://archive.org/details/x")
        #expect(bare.openableURL?.absoluteString == "https://archive.org/details/x")
        #expect(bare.displayHost == "archive.org")
        #expect(bare.displayTitle == bare.url)

        let titled = WebLink(url: "https://www.familysearch.org/x", title: "Метрика")
        #expect(titled.displayTitle == "Метрика")
        #expect(titled.displayHost == "familysearch.org")

        // An imported GEDCOM is untrusted: local and custom schemes must never open.
        #expect(WebLink(url: "file:///etc/passwd").openableURL == nil)
        #expect(WebLink(url: "javascript:alert(1)").openableURL == nil)
        #expect(WebLink(url: "").openableURL == nil)
        #expect(WebLink(url: "mailto:archive@example.org").openableURL != nil)
    }

    // MARK: - Source records

    @Test func archivalKeyIgnoresCaseSpacingAndYo() {
        let a = SourceRecord(title: "Метрическая книга", publication: "350", repository: "2", callNumber: "1841")
        let b = SourceRecord(title: "  метрическая   КНИГА ", publication: "350", repository: "2", callNumber: "1841")
        #expect(a.archivalKey == b.archivalKey)

        let differentFile = SourceRecord(title: "Метрическая книга", publication: "350", repository: "2", callNumber: "1842")
        #expect(a.archivalKey != differentFile.archivalKey)

        #expect(SourceRecord.fold("Ёлка") == SourceRecord.fold("елка"))
    }

    @Test func shelfmarkSummaryOmitsEmptyParts() {
        let full = SourceRecord(title: "X", publication: "350", repository: "2", callNumber: "1841")
        #expect(full.shelfmarkSummary == "Ф. 350 · Оп. 2 · Д. 1841")

        let partial = SourceRecord(title: "X", publication: "350")
        #expect(partial.shelfmarkSummary == "Ф. 350")

        #expect(SourceRecord(title: "X").shelfmarkSummary.isEmpty)
    }

    /// The editor used to hold a typed author and `parseSource` wrote `AUTH` only there,
    /// so a library saved before the field was removed would lose it on the next save
    /// unless decoding folds it into the preserved branches.
    @Test func decodingALegacySourceKeepsItsAuthorAsAPreservedBranch() throws {
        let legacy = """
        {"id":"\(UUID().uuidString)","title":"Метрическая книга","author":"Приход Св. Николая","rawGEDCOMBranches":[]}
        """
        let decoded = try JSONDecoder().decode(SourceRecord.self, from: Data(legacy.utf8))
        #expect(decoded.rawGEDCOMBranches == [["1 AUTH Приход Св. Николая"]])

        // Decoding a record that already carries the branch must not double it.
        let alreadyPreserved = """
        {"id":"\(UUID().uuidString)","title":"Метрическая книга","author":"Приход Св. Николая",\
        "rawGEDCOMBranches":[["1 AUTH Приход Св. Николая"]]}
        """
        let second = try JSONDecoder().decode(SourceRecord.self, from: Data(alreadyPreserved.utf8))
        #expect(second.rawGEDCOMBranches.count == 1)

        // A record saved by this version has no author key at all.
        let current = """
        {"id":"\(UUID().uuidString)","title":"X","rawGEDCOMBranches":[]}
        """
        #expect(try JSONDecoder().decode(SourceRecord.self, from: Data(current.utf8)).rawGEDCOMBranches.isEmpty)
    }
}
