import Foundation
@testable import SwarmCore
import Testing

@Suite(.serialized)
struct DefectRegressionTests {
    private final class Temp {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-defect-regressions-\(UUID().uuidString)", isDirectory: true)

        init() throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    @Test func utf16GEDCOMIsDecodedBeforeSingleByteFallback() throws {
        let temp = try Temp()
        let text = "0 HEAD\n1 CHAR UNICODE\n1 _NAME Семья\n0 @I1@ INDI\n1 NAME Анна /Иванова/\n0 TRLR"
        for (name, encoding) in [
            ("bom", String.Encoding.utf16),
            ("little", .utf16LittleEndian),
            ("big", .utf16BigEndian),
        ] {
            let source = temp.url.appendingPathComponent("utf16-\(name).ged")
            try #require(text.data(using: encoding)).write(to: source)
            let result = try GEDCOMCodec.parse(source)
            #expect(result.tree.name == "Семья")
            #expect(result.tree.people.first?.givenNames == "Анна")
        }
    }

    @Test func modeledEvidenceEventsNamesAndPlaceIdentityRoundTrip() throws {
        let tree = FamilyTree(name: "Round trip")
        let source = SourceRecord(title: "Register")
        tree.sourceRecords = [source]

        let parent = Person(givenNames: "Anna", surname: "Sokolova", maidenName: "Petrova")
        parent.setStructuredPlace(PlaceReference(
            datasetID: "625144",
            displayName: "Minsk, Belarus",
            latitude: 53.9,
            longitude: 27.5667,
            isCustom: false
        ), for: .birth)
        let child = Person(givenNames: "Ilya", surname: "Sokolov")
        tree.people = [parent, child]

        let union = Union(partner1Id: parent.id, childrenIds: [child.id])
        union.setStructuredEvent(GenealogyEvent(
            kind: .partnership,
            date: GenealogyDate(userInput: "1999"),
            notes: "Civil registry",
            rawGEDCOMBranches: [["2 _CUSTOM retained"]]
        ))
        union.setStructuredEvent(GenealogyEvent(kind: .divorce))
        union.setStructuredEvent(GenealogyEvent(kind: .separation, date: GenealogyDate(userInput: "2005")))
        tree.unions = [union]
        tree.parentLinks = [ParentLink(
            parentID: parent.id,
            childID: child.id,
            unionID: union.id,
            kind: .adoptive,
            citations: [Citation(sourceID: source.id, page: "12")],
            notes: "Adoption order"
        )]

        let gedcom = try GEDCOMCodec.serialize(tree: tree).gedcom
        #expect(gedcom.contains("_MARNM Anna /Sokolova/"))
        #expect(gedcom.contains("_PART"))
        #expect(gedcom.contains("_SEPR"))
        #expect(gedcom.contains("_PLACID 625144"))
        #expect(gedcom.contains("_PLINK"))

        let parsed = try GEDCOMCodec.parse(gedcom).tree
        let parsedParent = try #require(parsed.people.first { $0.givenNames == "Anna" })
        #expect(parsedParent.surname == "Sokolova")
        #expect(parsedParent.maidenName == "Petrova")
        #expect(parsedParent.event(ofKind: .birth)?.place?.datasetID == "625144")
        #expect(parsed.unions.first?.event(ofKind: .partnership)?.date?.year == 1999)
        #expect(parsed.unions.first?.event(ofKind: .partnership)?.notes == "Civil registry")
        #expect(parsed.unions.first?.event(ofKind: .partnership)?.rawGEDCOMBranches == [["2 _CUSTOM retained"]])
        #expect(parsed.unions.first?.event(ofKind: .divorce) != nil)
        #expect(parsed.unions.first?.event(ofKind: .separation)?.date?.year == 2005)
        #expect(parsed.parentLinks.first?.notes == "Adoption order")
        #expect(parsed.parentLinks.first?.citations.first?.page == "12")
    }

    /// An imported citation carries detail this app doesn't model — another program's
    /// place id, a second NOTE. The modeled citation replaces the whole imported branch
    /// on export, so that detail used to disappear on the first save, taking the place id
    /// of every event in the file with it.
    @Test func foreignCitationDetailSurvivesEverySave() {
        let gedcom = """
        0 HEAD
        1 _NAME Foreign detail
        0 @S1@ SOUR
        1 TITL Register
        0 @I1@ INDI
        1 NAME Anna /Petrova/
        1 BIRT
        2 DATE 20 OCT 1832
        2 PLAC Kielce
        2 SOUR @S1@
        3 PAGE 12
        3 QUAY high
        3 NOTE An institutional citation remains attached to the event.
        3 _PID place-q102317
        3 NOTE Locality coordinates, not a street address.
        0 TRLR
        """
        let first = GEDCOMSerializer.serialize(tree: tree(from: GEDCOMParser.parse(gedcom: gedcom))).gedcom
        #expect(first.contains("3 _PID place-q102317"))
        #expect(first.contains("An institutional citation remains attached to the event."))
        #expect(first.contains("Locality coordinates, not a street address."))

        // Saving the saved file must be a fixed point, not a slow leak or a duplicator.
        let second = GEDCOMSerializer.serialize(tree: tree(from: GEDCOMParser.parse(gedcom: first))).gedcom
        #expect(second.components(separatedBy: "3 _PID place-q102317").count - 1 == 1)
        #expect(second.contains("An institutional citation remains attached to the event."))
    }

    /// A record read into the model and also preserved verbatim gets written twice, and
    /// the next parse reads both copies — so every save used to multiply union citations
    /// and residence events, growing an example tree from 1803 to 2925 lines in three
    /// saves. Saving a saved file has to be a fixed point.
    @Test func repeatedSavesDoNotMultiplyCitationsOrEvents() {
        let gedcom = """
        0 HEAD
        1 _NAME Fixed point
        0 @S1@ SOUR
        1 TITL Register
        0 @I1@ INDI
        1 NAME Marie /Curie/
        1 SEX F
        1 RESI
        2 DATE 1891
        2 PLAC Paris
        3 MAP
        4 LATI N48.856600
        4 LONG E2.352200
        2 SOUR @S1@
        3 PAGE 4
        1 FAMS @F1@
        0 @I2@ INDI
        1 NAME Pierre /Curie/
        1 SEX M
        1 FAMS @F1@
        0 @F1@ FAM
        1 HUSB @I2@
        1 WIFE @I1@
        1 MARR
        2 DATE 1895
        1 SOUR @S1@
        2 PAGE 12
        0 TRLR
        """
        let first = GEDCOMSerializer.serialize(tree: tree(from: GEDCOMParser.parse(gedcom: gedcom))).gedcom
        let second = GEDCOMSerializer.serialize(tree: tree(from: GEDCOMParser.parse(gedcom: first))).gedcom
        let third = GEDCOMSerializer.serialize(tree: tree(from: GEDCOMParser.parse(gedcom: second))).gedcom
        // The tree id is regenerated by the rebuild helper, so compare everything else.
        #expect(withoutTreeID(second) == withoutTreeID(third))
        #expect(second.split(separator: "\n").count == first.split(separator: "\n").count)

        // The residence survives the round trip in full rather than as a bare tag.
        #expect(first.contains("1 RESI"))
        #expect(first.contains("2 DATE 1891"))
        #expect(first.contains("2 PLAC Paris"))
        #expect(first.contains("4 LATI N48.856600"))
        #expect(third.components(separatedBy: "2 PAGE 12").count - 1 == 1)
        #expect(third.components(separatedBy: "1 RESI").count - 1 == 1)
    }

    /// The scalar name fields are what the person editor loads and writes back, so they
    /// have to describe the primary name. A record that lists an alternate name after the
    /// primary one used to leave them describing the alternate, and saving that person
    /// then flattened the primary — Marie Skłodowska-Curie came back surnameless.
    @Test func alternateNamesDoNotOverwriteTheScalarPrimaryName() {
        let gedcom = """
        0 HEAD
        1 _NAME Alternate names
        0 @I1@ INDI
        1 NAME Maria Salomea /Skłodowska-Curie/
        2 TYPE married
        2 GIVN Maria Salomea
        2 SURN Skłodowska-Curie
        1 NAME Maria Salomea Skłodowska //
        2 TYPE birth
        2 GIVN Maria Salomea Skłodowska
        0 TRLR
        """
        let parsed = GEDCOMParser.parse(gedcom: gedcom)
        let marie = parsed.people[0]
        #expect(marie.givenNames == "Maria Salomea")
        #expect(marie.surname == "Skłodowska-Curie")
        #expect(marie.names.first(where: \.isPrimary)?.surname == "Skłodowska-Curie")

        // An edit that touches nothing but re-applies the scalars — what saving a person
        // does — must leave the primary name intact.
        let given = marie.givenNames
        marie.givenNames = given
        #expect(marie.names.first(where: \.isPrimary)?.givenNames == "Maria Salomea")
        #expect(marie.names.first(where: \.isPrimary)?.surname == "Skłodowska-Curie")
        #expect(GEDCOMSerializer.serialize(tree: tree(from: parsed)).gedcom
            .contains("1 NAME Maria Salomea /Skłodowska-Curie/"))
    }

    /// `2 SURN` carries the current surname, so a `_MARNM` read after it must take the
    /// maiden name from the `1 NAME` slash form rather than from whatever was read last.
    @Test func maidenNameComesFromTheNameLineNotTheSurnameTag() {
        let gedcom = """
        0 HEAD
        1 _NAME Maiden
        0 @I1@ INDI
        1 NAME Анна /Иванова/
        2 GIVN Анна
        2 SURN Сидорова
        2 _MARNM Анна /Сидорова/
        0 TRLR
        """
        let anna = GEDCOMParser.parse(gedcom: gedcom).people[0]
        #expect(anna.surname == "Сидорова")
        #expect(anna.maidenName == "Иванова")
        #expect(anna.names.first?.maidenName == "Иванова")
    }

    private func withoutTreeID(_ gedcom: String) -> [String] {
        gedcom.split(separator: "\n").map(String.init).filter { !$0.hasPrefix("1 _TREEID ") }
    }

    /// Rebuild a tree from a parse result, the way the store does after an import.
    private func tree(from parsed: GEDCOMParser.ParsedTree) -> FamilyTree {
        let tree = FamilyTree(name: parsed.name)
        tree.people = parsed.people
        tree.unions = parsed.unions
        tree.sourceRecords = parsed.sourceRecords
        tree.parentLinks = parsed.parentLinks
        tree.unknownRecords = parsed.unknownRecords
        tree.headUnknownBranches = parsed.headUnknownBranches
        return tree
    }

    @Test func validationSeveritiesMissingNamesAndMalformedLinksAreSafe() {
        let tree = FamilyTree(name: "Validation")
        let nameless = Person()
        nameless.events = [
            GenealogyEvent(kind: .birth, date: GenealogyDate(userInput: "1900")),
            GenealogyEvent(kind: .death, date: GenealogyDate(userInput: "1800")),
        ]
        nameless.citations = [Citation(sourceID: UUID())]
        tree.people = [nameless]
        tree.unions = [Union(partner1Id: nameless.id, partner2Id: nameless.id)]
        tree.sourceRecords = [SourceRecord(title: "Register"), SourceRecord(title: "register")]

        let issues = TreeValidator.validate(tree)
        #expect(issues.contains { $0.code == "identity.missing-name" })
        #expect(issues.contains { $0.code == "chronology.death-before-birth" && $0.severity == .error })
        #expect(issues.contains { $0.code == "citation.missing-source" && $0.severity == .warning && !$0.isBlocking })
        #expect(issues.contains { $0.code == "source.possible-duplicate" && $0.severity == .warning && !$0.isBlocking })
        _ = TreeLayoutEngine().layout(tree: tree, direction: .topDown)
    }

    @Test func newArchivesHaveCompleteLayoutAndMissingActiveRootFailsClearly() async throws {
        let temp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        let tree = FamilyTree(name: "Layout")
        tree.people = [Person(givenNames: "Anna")]
        let receipt = try await store.addTreeVerified(tree)

        for relative in ["Media", "Attachments", ".Swarm/History", ".Swarm/Trash"] {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(
                atPath: receipt.finalURL.appendingPathComponent(relative).path,
                isDirectory: &isDirectory
            )
            #expect(exists && isDirectory.boolValue)
        }

        try FileManager.default.removeItem(at: receipt.finalURL)
        await #expect(throws: TreeStoreError.self) {
            _ = try await store.saveTree(tree)
        }
        #expect(!FileManager.default.fileExists(atPath: receipt.finalURL.path))
    }

    @MainActor
    @Test func asyncAttachmentPreparationCommitsTheCopiedFile() async throws {
        let temp = try Temp()
        let source = temp.url.appendingPathComponent("source.txt")
        try Data("attachment".utf8).write(to: source)
        let store = TreeStore(storageFolder: temp.url.appendingPathComponent("Library", isDirectory: true))
        let tree = FamilyTree(name: "Attachments")
        let person = Person(givenNames: "Anna")
        tree.people = [person]

        let attachment = try await store.prepareAttachmentAsync(in: tree, sourceURL: source)
        person.attachments = [attachment]
        let receipt = try await store.addTreeVerified(tree)

        let copied = receipt.finalURL
            .appendingPathComponent("Attachments", isDirectory: true)
            .appendingPathComponent(attachment.storedName)
        #expect(try Data(contentsOf: copied) == Data("attachment".utf8))
    }

    @Test func blockingPreviewIsReachableWithoutAllowingCommit() throws {
        let temp = try Temp()
        let source = temp.url.appendingPathComponent("broken.ged")
        try "0 HEAD\n2 CHAR UTF-8\n0 TRLR".write(to: source, atomically: true, encoding: .utf8)
        let preview = try GEDCOMCodec.preview(source)
        #expect(preview.report.blockingErrors.count == 1)
        #expect(preview.tree.people.isEmpty)
        #expect(throws: GEDCOMCodecError.self) { try GEDCOMCodec.parse(source) }
    }

    @Test func livingPeopleCannotSerializeHiddenDeathOrBurialData() throws {
        let tree = FamilyTree(name: "Living")
        let person = Person(givenNames: "Anna", deathDate: "2001", deathPlace: "Moscow", isLiving: true, burialPlace: "Cemetery")
        tree.people = [person]
        let gedcom = try GEDCOMCodec.serialize(tree: tree).gedcom
        #expect(!gedcom.contains("1 DEAT"))
        #expect(!gedcom.contains("1 BURI"))
    }

    @Test func livingDeathConflictIsReportedAndPreserved() throws {
        let input = "0 HEAD\n0 @I1@ INDI\n1 NAME Anna /Smith/\n1 _LIVING Y\n1 DEAT\n2 DATE 2001\n0 TRLR"
        let result = try GEDCOMCodec.parse(input)
        #expect(result.report.warnings.contains { $0.id.hasPrefix("gedcom.living-death-conflict") })
        let output = try GEDCOMCodec.serialize(tree: result.tree, document: result.document).gedcom
        #expect(output.contains("1 _LIVING Y"))
        #expect(output.contains("1 DEAT"))
    }

    // MARK: - Fields the editor no longer models

    /// `AUTH` lost its typed field when the editor dropped the author. The parser must
    /// stop claiming it so it rides out in the preserved branches instead, or every
    /// imported source silently loses its author on the first save.
    @Test func importedSourceAuthorSurvivesTheFieldBeingRemoved() {
        let gedcom = """
        0 HEAD
        0 @I1@ INDI
        1 NAME Фёдор /Достоевский/
        0 @S1@ SOUR
        1 TITL Метрическая книга
        1 AUTH Приход Св. Николая
        0 TRLR
        """
        let parsed = GEDCOMParser.parse(gedcom: gedcom)
        let source = parsed.sourceRecords.first
        #expect(source?.rawGEDCOMBranches.contains { $0.contains { $0.contains("AUTH Приход Св. Николая") } } == true)

        let first = GEDCOMSerializer.serialize(tree: tree(from: parsed)).gedcom
        #expect(first.components(separatedBy: "1 AUTH Приход Св. Николая").count - 1 == 1)

        // Saving the saved file is a fixed point, not a duplicator.
        let second = GEDCOMSerializer.serialize(tree: tree(from: GEDCOMParser.parse(gedcom: first))).gedcom
        #expect(second.components(separatedBy: "1 AUTH Приход Св. Николая").count - 1 == 1)
    }

    /// Same story for `QUAY`, which the reliability field used to carry. It is preserved
    /// through `rawGEDCOMBranches`, which only works while `preservedCitationDetail`
    /// stops suppressing it.
    @Test func importedCitationConfidenceSurvivesTheFieldBeingRemoved() {
        let gedcom = """
        0 HEAD
        0 @I1@ INDI
        1 NAME Анна /Иванова/
        1 BIRT
        2 DATE 1 JAN 1900
        2 SOUR @S1@
        3 PAGE 12
        3 QUAY 3
        0 @S1@ SOUR
        1 TITL Ревизская сказка
        0 TRLR
        """
        let first = GEDCOMSerializer.serialize(tree: tree(from: GEDCOMParser.parse(gedcom: gedcom))).gedcom
        #expect(first.contains("QUAY 3"))
        #expect(first.components(separatedBy: "QUAY 3").count - 1 == 1)

        let second = GEDCOMSerializer.serialize(tree: tree(from: GEDCOMParser.parse(gedcom: first))).gedcom
        #expect(second.components(separatedBy: "QUAY 3").count - 1 == 1)
    }

    // MARK: - Source URL

    @Test func sourceURLRoundTripsAsTheUnderscoreURLTag() {
        let tree = FamilyTree(name: "Ссылки")
        let person = Person(givenNames: "Пётр", surname: "Петров")
        let source = SourceRecord(title: "Ревизская сказка", url: "https://rgada.info/opisi/350-opis_2/")
        person.citations = [Citation(sourceID: source.id, page: "л. 214 об.")]
        tree.people = [person]
        tree.sourceRecords = [source]

        let out = GEDCOMSerializer.serialize(tree: tree).gedcom
        #expect(out.components(separatedBy: "1 _URL https://rgada.info/opisi/350-opis_2/").count - 1 == 1)

        let parsed = GEDCOMParser.parse(gedcom: out)
        #expect(parsed.sourceRecords.first?.url == "https://rgada.info/opisi/350-opis_2/")
        #expect(parsed.people.first?.citations.first?.page == "л. 214 об.")
    }

    /// An imported `_URL` must land in the typed field rather than the preserved
    /// branches, or the export emits it twice — once modelled, once verbatim.
    @Test func importedURLTagIsModelledRatherThanDuplicated() {
        let gedcom = """
        0 HEAD
        0 @I1@ INDI
        1 NAME Мария /Кюри/
        0 @S1@ SOUR
        1 TITL Emma Darwin
        1 _URL https://www.darwinproject.ac.uk/emma-darwin
        0 TRLR
        """
        let parsed = GEDCOMParser.parse(gedcom: gedcom)
        let source = parsed.sourceRecords.first
        #expect(source?.url == "https://www.darwinproject.ac.uk/emma-darwin")
        #expect(source?.rawGEDCOMBranches.contains { $0.contains { $0.contains("_URL") } } == false)

        let out = GEDCOMSerializer.serialize(tree: tree(from: parsed)).gedcom
        #expect(out.components(separatedBy: "_URL https://www.darwinproject.ac.uk/emma-darwin").count - 1 == 1)
    }

    // MARK: - REPO

    /// `REPO` now labels «опись» in the editor. A pointer-form REPO is a reference to a
    /// real repository record and must stay one; text the user typed must never be
    /// exported as a pointer to a record that does not exist.
    @Test func repositoryPointersSurviveAndTypedTextNeverBecomesOne() {
        let gedcom = """
        0 HEAD
        0 @I1@ INDI
        1 NAME Лев /Толстой/
        0 @S1@ SOUR
        1 TITL Метрическая книга
        1 REPO @R1@
        0 @R1@ REPO
        1 NAME ГАТО
        0 TRLR
        """
        let parsed = GEDCOMParser.parse(gedcom: gedcom)
        // The pointer is meaningless as «опись» text, so it stays out of the field.
        #expect(parsed.sourceRecords.first?.repository == nil)
        let out = GEDCOMSerializer.serialize(tree: tree(from: parsed)).gedcom
        #expect(out.contains("1 REPO @R1@"))
        #expect(out.contains("0 @R1@ REPO"))

        // Text that merely looks like a pointer must not be emitted as one.
        let typed = FamilyTree(name: "Опись")
        let person = Person(givenNames: "Лев")
        let source = SourceRecord(title: "Метрическая книга", repository: "@2@")
        person.citations = [Citation(sourceID: source.id)]
        typed.people = [person]
        typed.sourceRecords = [source]
        let typedOut = GEDCOMSerializer.serialize(tree: typed).gedcom
        let repoLine = typedOut.split(separator: "\n").first { $0.hasPrefix("1 REPO") }
        #expect(repoLine != nil)
        #expect(GEDCOMNode(rawLine: String(repoLine ?? ""))?.pointer == nil)
    }
}
