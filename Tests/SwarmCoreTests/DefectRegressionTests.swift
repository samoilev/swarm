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
    @Test func foreignCitationDetailSurvivesEverySave() throws {
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
}
