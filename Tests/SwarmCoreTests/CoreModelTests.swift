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
        #expect(try result.labels[#require(p["me"]?.id)] == "Выбранный человек")
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
        // A bare identifier must not become a scheme-less host that opens nothing.
        #expect(WebLink(url: "javascript:LZDP-6M9").openableURL == nil)
    }

    // MARK: - Genealogy sites

    @Test func bareFamilySearchIdentifierExpandsToItsPersonPage() {
        let expanded = WebLink.normalize("  LZDP-6M9  ")
        #expect(expanded == "https://www.familysearch.org/tree/person/details/LZDP-6M9")
        // Idempotent: the expansion carries a scheme, so a second pass leaves it alone.
        #expect(WebLink.normalize(expanded) == expanded)

        let link = WebLink(url: "LZDP-6M9")
        #expect(link.site?.id == "familysearch")
        #expect(link.externalID == "LZDP-6M9")
        #expect(link.displaySubtitle == "FamilySearch · LZDP-6M9")
        #expect(link.openableURL?.absoluteString == expanded)
    }

    @Test(arguments: [
        ("https://www.familysearch.org/tree/person/details/LZDP-6M9", "familysearch", "LZDP-6M9"),
        ("https://www.wikitree.com/wiki/Sidorov-123", "wikitree", "Sidorov-123"),
        ("https://www.findagrave.com/memorial/12345/ivan-sidorov", "findagrave", "12345"),
        ("https://www.geni.com/people/Ivan-Sidorov/6000000012345678901", "geni", "6000000012345678901"),
        ("https://www.myheritage.com/person-1_123456_789012/ivan", "myheritage", "1_123456_789012"),
    ])
    func recognizesPersonPagesOfEachKnownSite(url: String, siteID: String, identifier: String) {
        let link = WebLink(url: url)
        #expect(link.site?.id == siteID)
        #expect(link.externalID == identifier)
    }

    @Test func recognizesGeneanetByHostWithoutClaimingAnIdentifier() {
        // Geneanet addresses a person with query pairs, so there is no id to show.
        let link = WebLink(url: "https://gw.geneanet.org/someuser?p=jean&n=dupont")
        #expect(link.site?.id == "geneanet")
        #expect(link.externalID == nil)
        #expect(link.displaySubtitle == "Geneanet")
    }

    @Test func unrecognizedAddressesFallBackToTheirHost() {
        let link = WebLink(url: "https://www.prlib.ru/item/42")
        #expect(link.site == nil)
        #expect(link.displaySubtitle == "prlib.ru")
    }

    @Test func anAmbiguousBareIdentifierIsLeftAsTyped() {
        // "WXYZ-123" reads as both a FamilySearch PID and a WikiTree id. Filing it under
        // the wrong archive silently is worse than not expanding it at all.
        #expect(GenealogySite.matchingBareID("WXYZ-123") == nil)
        #expect(WebLink.normalize("WXYZ-123") == "https://WXYZ-123")
        // Each shape on its own still resolves.
        #expect(GenealogySite.matchingBareID("LZDP-6M9")?.site.id == "familysearch")
        #expect(GenealogySite.matchingBareID("Saint-Exupery-12")?.site.id == "wikitree")
        #expect(GenealogySite.matchingBareID("не идентификатор") == nil)
    }

    // MARK: - External identifiers carried in from other programs

    @Test func readsExternalIdentifiersOutOfPreservedBranches() {
        let ids = GenealogySite.externalIDs(in: [
            ["1 _APID 1,0000::42"],
            ["1 _UID foreign-uid-must-remain-foreign"],
            ["1 _FSFTID LZDP-6M9"],
            ["1 EXID Q7186", "2 TYPE https://www.wikitree.com/wiki/"],
            ["1 CHAN", "2 DATE 1 JAN 2020"],
        ])
        #expect(ids.map(\.label) == ["Ancestry", "UID", "FamilySearch", "WikiTree"])
        // Ancestry's _APID names a citation, not a person page — nothing to open.
        #expect(ids[0].url == nil)
        #expect(ids[1].url == nil)
        #expect(ids[2].url?.absoluteString == "https://www.familysearch.org/tree/person/details/LZDP-6M9")
        #expect(ids[3].url?.absoluteString == "https://www.wikitree.com/wiki/Q7186")
    }

    @Test func externalIdentifierAuthoritiesCannotSmuggleInAnUnsafeScheme() {
        let ids = GenealogySite.externalIDs(in: [["1 EXID passwd", "2 TYPE file:///etc/"]])
        #expect(ids.count == 1)
        #expect(ids[0].url == nil)
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

    /// A FAM that lists the same person as partner and child says someone is their
    /// own parent. GEDCOM can express it, the validator reports it as an error, and
    /// an accepted baseline still reaches lineage and the canvas — where an edge from
    /// a person to themselves used to trip `FamilyConnection`'s precondition and take
    /// the app down.
    @Test func selfParentingUnionIsIgnoredRatherThanCrashing() {
        let tree = FamilyTree(name: "Повреждённое")
        let person = Person(givenNames: "Сам", sex: .male)
        let child = Person(givenNames: "Ребёнок", sex: .female)
        tree.people = [person, child]
        tree.unions = [Union(partner1Id: person.id, partner2Id: person.id, childrenIds: [person.id, child.id])]

        let index = FamilyIndex(tree: tree)
        let parents = index.parentsOf(person)
        #expect(parents.father == nil)
        #expect(parents.mother == nil)

        let lineage = LineageCalculator(index: index).compute(for: person)
        #expect(lineage.ids.contains(person.id))
        #expect(lineage.connections.allSatisfy { $0.firstID != $0.secondID })
    }

    /// The card's photo gallery is exactly this list, and it is hidden below two
    /// entries — so what counts as a photo, and in what order, is the whole rule.
    @Test func photoRefsListThePortraitFirstThenImageAttachmentsOnly() {
        let image = Attachment(storedName: "\(UUID().uuidString).jpg", originalName: "Свадьба.jpg")
        let document = Attachment(storedName: "\(UUID().uuidString).pdf", originalName: "Метрика.pdf")

        let withPortrait = Person(givenNames: "С портретом", sex: .female)
        withPortrait.photoFilename = "portrait.jpg"
        withPortrait.attachments = [document, image]
        #expect(withPortrait.photoRefs == [.portrait, .attachment(image)])

        // A portrait on its own, and a person with no pictures at all: no gallery.
        let portraitOnly = Person(givenNames: "Только портрет", sex: .male)
        portraitOnly.photoFilename = "portrait.jpg"
        portraitOnly.attachments = [document]
        #expect(portraitOnly.photoRefs == [.portrait])
        #expect(Person(givenNames: "Пусто", sex: .male).photoRefs.isEmpty)

        // No portrait: the attachments keep their own order and stand alone.
        let second = Attachment(storedName: "\(UUID().uuidString).png", originalName: "Дом.png")
        let noPortrait = Person(givenNames: "Без портрета", sex: .female)
        noPortrait.attachments = [image, document, second]
        #expect(noPortrait.photoRefs == [.attachment(image), .attachment(second)])
    }

    /// The card header breaks the name itself rather than leaving it to whatever width
    /// the inspector has been dragged to. The invariant that keeps that honest: the two
    /// lines rejoined are exactly the name the rest of the app shows.
    @Test func displayNameLinesSplitWithoutReordering() {
        let p = Person(givenNames: "Константин", patronymic: "Александрович", surname: "Преображенский", sex: .male)

        let ru = p.displayNameLines(language: .russian)
        #expect(ru.primary == "Преображенский")
        #expect(ru.secondary == "Константин Александрович")
        #expect(p.displayName(language: .russian) == "\(ru.primary) \(ru.secondary)")

        let en = p.displayNameLines(language: .english)
        #expect(en.primary == "Константин")
        #expect(en.secondary == "Александрович Преображенский")
        #expect(p.displayName(language: .english) == "\(en.primary) \(en.secondary)")

        // A missing part must not leave an empty line or a doubled space: the first
        // name there is the one that gets the big line.
        let surnameOnly = Person(surname: "Романов", sex: .male)
        #expect(surnameOnly.displayNameLines(language: .russian) == ("Романов", ""))
        let givenOnly = Person(givenNames: "Пётр", sex: .male)
        #expect(givenOnly.displayNameLines(language: .russian) == ("Пётр", ""))
        #expect(Person(sex: .unknown).displayNameLines(language: .russian) == ("", ""))
    }

    /// The medallion's stand-in when there is no photograph: the two identifying names,
    /// in the order the language shows them, and never the patronymic.
    @Test func monogramTakesTwoNamesInDisplayOrder() {
        let p = Person(givenNames: "Клавдия", patronymic: "Фёдоровна", surname: "Преображенская", sex: .female)
        #expect(p.monogram(language: .russian) == "ПК")
        #expect(p.monogram(language: .english) == "КП")

        // One name gives one letter; no name at all gives nothing, which is the view's
        // signal to fall back to the silhouette.
        #expect(Person(givenNames: "пётр", sex: .male).monogram(language: .russian) == "П")
        #expect(Person(sex: .unknown).monogram(language: .russian).isEmpty)
    }
}
