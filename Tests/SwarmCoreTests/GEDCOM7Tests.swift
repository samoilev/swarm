import Foundation
@testable import SwarmCore
import Testing

/// Coverage for reading FamilySearch GEDCOM 7.0 and for writing it back out.
///
/// The 5.5.1 behaviour these tests sit next to is asserted by `GEDCOMRoundTripTests`
/// and must stay untouched: 7.0 is an export choice, not a change to how a tree that
/// is already on disk gets saved.
struct GEDCOM7Tests {

    private func fixture(_ name: String) throws -> URL {
        try #require(Bundle.module.url(forResource: name, withExtension: "ged", subdirectory: "Fixtures"))
    }

    private func makeTree() -> FamilyTree {
        let tree = FamilyTree(name: "Дерево", subtitle: "Подзаголовок")
        let father = Person(
            givenNames: "Иван", surname: "Сидоров", sex: .male,
            birthDate: "05.03.1901", birthPlace: "Москва",
            deathDate: "12.11.1970", isLiving: false,
            notes: String(repeating: "длинная заметка ", count: 60),
            sources: ["Перепись 1926"]
        )
        father.birthLat = 55.7558
        father.birthLon = 37.6173
        let mother = Person(
            givenNames: "Анна", surname: "Сидорова", maidenName: "Иванова",
            sex: .female, birthDate: "1905", deathDate: "1980", isLiving: false
        )
        let child = Person(givenNames: "Пётр", surname: "Сидоров", sex: .male, isLiving: true)
        tree.people = [father, mother, child]
        let union = Union(
            partner1Id: father.id, partner2Id: mother.id,
            marriageDate: "14.04.1928", childrenIds: [child.id]
        )
        tree.unions = [union]
        tree.sourceRecords = [SourceRecord(title: "Метрическая книга", url: "https://example.org/book")]
        return tree
    }

    private func v7(_ tree: FamilyTree) -> String {
        GEDCOMSerializer.serialize(tree: tree, options: .init(version: .v70)).gedcom
    }

    // MARK: - Version detection

    @Test func detectsTheVersionEachFixtureDeclares() throws {
        #expect(try GEDCOMCodec.parse(fixture("gedcom7-minimal")).tree.sourceVersion == .v70)
        #expect(try GEDCOMCodec.parse(fixture("gedcom7-features")).tree.sourceVersion == .v70)
        #expect(try GEDCOMCodec.parse(fixture("gramps-anonymized")).tree.sourceVersion == .v551)
        #expect(try GEDCOMCodec.parse(fixture("corpus-curie")).tree.sourceVersion == .v551)
    }

    /// A header with no GEDC at all is the common shape of a damaged or hand-edited
    /// file. It must read as 5.5.1 rather than throwing or guessing 7.0.
    @Test func aHeaderWithoutAVersionDeclarationReadsAs551() throws {
        let result = try GEDCOMCodec.parse("0 HEAD\n1 SOUR X\n0 TRLR")
        #expect(result.tree.sourceVersion == .v551)
    }

    // MARK: - Reading 7.0

    @Test func aValidSevenZeroFileImportsWithoutUnsupportedTagNoise() throws {
        let result = try GEDCOMCodec.parse(fixture("gedcom7-features"))
        #expect(result.report.blockingErrors.isEmpty)
        // The whole point of widening the tolerated set: a file that is simply current
        // must not arrive looking broken.
        #expect(result.report.preservedUnsupportedTags.isEmpty)
        #expect(result.report.unresolvedPointers.isEmpty)
        #expect(result.tree.people.count == 2)
        #expect(result.tree.unions.count == 1)
    }

    @Test func readsSevenZeroPeopleNamesDatesAndCoordinates() throws {
        let tree = try GEDCOMCodec.parse(fixture("gedcom7-features")).tree
        let anna = try #require(tree.people.first { $0.givenNames == "Anna" })
        #expect(anna.surname == "Vance")
        #expect(anna.sex == .female)
        #expect(anna.birthPlace == "Riga, Latvia")
        #expect(anna.birthLat.map { abs($0 - 56.946) < 0.001 } == true)
        #expect(anna.birthLon.map { abs($0 - 24.1061) < 0.001 } == true)
    }

    /// 7.0 moved a date's free-text explanation out of the payload into `PHRASE`.
    @Test func readsADatePhraseIntoTheDateRatherThanLosingIt() throws {
        let tree = try GEDCOMCodec.parse(fixture("gedcom7-features")).tree
        let anna = try #require(tree.people.first { $0.givenNames == "Anna" })
        let birth = try #require(anna.event(ofKind: .birth))
        #expect(birth.date?.phrase == "the spring before the move")
    }

    /// `UID` is what 7.0 calls the stable record id Swarm writes as `_FTSID`, so a
    /// 7.0 file's identities must survive import the same way.
    @Test func adoptsTheUIDInASevenZeroFileAsTheRecordIdentity() throws {
        let tree = try GEDCOMCodec.parse(fixture("gedcom7-features")).tree
        let expected = UUID(uuidString: "6E8F2C1A-4B3D-4E7F-9A12-0C5D8B6E1F40")
        #expect(tree.people.contains { $0.id == expected })
    }

    @Test func keepsForeignSchemaDeclarationsAndTheTagsTheyCover() throws {
        let result = try GEDCOMCodec.parse(fixture("gedcom7-features"))
        #expect(result.tree.foreignSchemaTags["_CUSTOM"] == "https://example.com/terms/custom")
        let exported = try GEDCOMCodec.serialize(
            tree: result.tree,
            document: result.document,
            options: .init(version: .v70)
        ).gedcom
        #expect(exported.contains("_CUSTOM kept by the schema above"))
    }

    @Test func aMinimalSevenZeroFileIsReadableAndCarriesNoPeople() throws {
        let result = try GEDCOMCodec.parse(fixture("gedcom7-minimal"))
        #expect(result.report.blockingErrors.isEmpty)
        #expect(result.tree.people.isEmpty)
        #expect(result.tree.sourceVersion == .v70)
    }

    /// Regression: a UTF-8 BOM used to make the first line unparseable, which failed
    /// the whole file. 7.0 says a file should open with one.
    @Test func aFileOpeningWithAByteOrderMarkStillImports() throws {
        let result = try GEDCOMCodec.parse(fixture("utf8-bom-551"))
        #expect(result.report.blockingErrors.isEmpty)
        #expect(result.tree.people.count == 1)
        #expect(result.tree.people.first?.surname == "Holt")
    }

    // MARK: - Writing 7.0

    @Test func sevenZeroHeaderDeclaresTheSpecAndDropsWhatSevenZeroRemoved() {
        let text = v7(makeTree())
        #expect(text.contains("2 VERS 7.0.18"))
        #expect(!text.contains("2 VERS 5.5.1"))
        // UTF-8 is the only encoding in 7.0, so CHAR has no meaning; LINEAGE-LINKED
        // is not one of its forms.
        #expect(!text.contains("1 CHAR"))
        #expect(!text.contains("FORM LINEAGE-LINKED"))
        #expect(text.hasSuffix("0 TRLR"))
    }

    /// CONC does not exist in 7.0 and there is no line-length limit to need it.
    @Test func sevenZeroOutputCarriesNoCONCAndKeepsTheWholeValue() {
        let tree = makeTree()
        let text = v7(tree)
        #expect(!text.contains(" CONC "))
        #expect(!text.contains("\n2 CONC"))
        let note = tree.people[0].notes ?? ""
        #expect(!note.isEmpty)
        #expect(text.contains(note))
    }

    /// The 5.5.1 writer is untouched: it still splits, because 5.5.1 still needs it.
    @Test func fiveFiveOneOutputStillSplitsLongValuesWithCONC() {
        let text = GEDCOMSerializer.serialize(tree: makeTree()).gedcom
        #expect(text.contains("CONC"))
        #expect(text.contains("2 VERS 5.5.1"))
    }

    @Test func everyExtensionTagEmittedIsDeclaredInTheSchema() {
        let text = v7(makeTree())
        let lines = text.components(separatedBy: "\n")
        let declared = Set(
            lines
                .filter { $0.hasPrefix("2 TAG ") }
                .compactMap { $0.dropFirst(6).split(separator: " ").first.map(String.init) }
        )
        let used = Set(
            lines.compactMap { line -> String? in
                let parts = line.split(separator: " ", maxSplits: 2).map(String.init)
                guard parts.count >= 2 else { return nil }
                let tag = parts[1].hasPrefix("@") ? (parts.count > 2 ? parts[2] : "") : parts[1]
                return tag.hasPrefix("_") ? tag : nil
            }
        )
        #expect(!used.isEmpty)
        // This is the assertion that keeps the mapping table honest: adding a custom
        // tag to the serializer without declaring it fails here.
        #expect(used.subtracting(declared).isEmpty)
    }

    @Test func mapsTheCustomTagsSevenZeroHasARealStructureFor() {
        let text = v7(makeTree())
        #expect(text.contains("1 UID "))
        #expect(!text.contains("_FTSID"))
        #expect(text.contains("1 WWW https://example.org/book"))
        #expect(!text.contains("_URL"))
    }

    @Test func mediaFormatBecomesAMediaType() {
        let tree = makeTree()
        tree.people[0].photoFilename = "portrait.png"
        tree.people[0].photoData = Data([0x89, 0x50, 0x4E, 0x47])
        let text = v7(tree)
        #expect(text.contains("2 FORM image/png"))
        #expect(!text.contains("2 FORM PNG"))
    }

    // MARK: - Round trips

    @Test func sevenZeroOutputParsesBackWithItsContentIntact() throws {
        let tree = makeTree()
        let result = try GEDCOMCodec.parse(v7(tree))
        #expect(result.report.blockingErrors.isEmpty)
        #expect(result.tree.sourceVersion == .v70)
        #expect(result.tree.people.count == tree.people.count)
        #expect(result.tree.unions.count == tree.unions.count)
        #expect(Set(result.tree.people.map(\.id)) == Set(tree.people.map(\.id)))
        let father = try #require(result.tree.people.first { $0.givenNames == "Иван" })
        #expect(father.notes == tree.people[0].notes)
        #expect(father.birthPlace == "Москва")
        #expect(result.tree.sourceRecords.first?.url == "https://example.org/book")
    }

    /// Serialize → parse → serialize must reach a fixed point, or every save would
    /// drift the file a little further.
    @Test func sevenZeroSerializationIsAFixedPoint() throws {
        let first = v7(makeTree())
        let second = try v7(GEDCOMCodec.parse(first).tree)
        let third = try v7(GEDCOMCodec.parse(second).tree)
        #expect(second == third)
    }

    @Test func aFiveFiveOneFileConvertsToSevenZeroAndKeepsItsPeople() throws {
        let source = try GEDCOMCodec.parse(fixture("corpus-curie"))
        let converted = try GEDCOMCodec.serialize(
            tree: source.tree,
            document: source.document,
            options: .init(version: .v70)
        ).gedcom
        #expect(converted.contains("2 VERS 7.0.18"))
        #expect(!converted.contains(" CONC "))
        let reread = try GEDCOMCodec.parse(converted)
        #expect(reread.report.blockingErrors.isEmpty)
        #expect(reread.tree.people.count == source.tree.people.count)
        #expect(reread.tree.unions.count == source.tree.unions.count)
        #expect(Set(reread.tree.people.map(\.id)) == Set(source.tree.people.map(\.id)))
    }

    /// A converting export must not splice byte-for-byte 5.5.1 records into a file
    /// that declares 7.0, so the preserved document is deliberately ignored.
    @Test func convertingIgnoresThePreservedDocumentInsteadOfMixingVersions() throws {
        let source = try GEDCOMCodec.parse(fixture("gramps-anonymized"))
        let converted = try GEDCOMCodec.serialize(
            tree: source.tree,
            document: source.document,
            options: .init(version: .v70)
        ).gedcom
        #expect(!converted.contains("2 VERS 5.5.1"))
        #expect(!converted.contains("1 CHAR UTF-8"))
    }

    /// A 7.0 tree that is merely saved, not converted, keeps its version rather than
    /// being quietly downgraded to the app's historical default.
    @Test func savingASevenZeroTreeKeepsItSevenZero() throws {
        let result = try GEDCOMCodec.parse(fixture("gedcom7-features"))
        let saved = try GEDCOMCodec.serialize(
            tree: result.tree,
            document: result.document,
            options: .init(version: result.tree.sourceVersion)
        ).gedcom
        #expect(saved.contains("2 VERS 7.0.18"))
    }

    /// The redacted copy is the same tree with people removed, so it must agree with
    /// its source about which specification it is written in.
    @Test func redactionKeepsTheVersionItsSourceWasReadIn() throws {
        let tree = try GEDCOMCodec.parse(fixture("gedcom7-features")).tree
        #expect(tree.redactingLivingPeople().sourceVersion == .v70)
    }

    // MARK: - What a new tree is written as

    /// A tree that has never been saved has no file to protect, so it starts current.
    @Test func aNewlyCreatedTreeIsSevenZero() {
        #expect(FamilyTree(name: "Fresh").sourceVersion == .v70)
    }

    @Test func aNewTreeSavedThroughTheStoreLandsOnDiskAsSevenZero() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("newtree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = await TreeStore(storageFolder: root)
        let tree = FamilyTree(name: "Fresh")
        tree.people = [Person(givenNames: "A", surname: "B", sex: .male, isLiving: false)]
        _ = try await store.addTreeVerified(tree)

        let text = try await String(contentsOf: store.gedFileURL(for: tree), encoding: .utf8)
        #expect(text.contains("2 VERS 7.0.18"))
        #expect(text.contains("1 SCHMA"))
        #expect(!text.contains("1 CHAR"))
        #expect(!text.contains(" CONC "))
    }

    /// The regression that matters most: an existing file is never rewritten into
    /// another specification just because the app's default moved.
    @Test func anImportedFiveFiveOneTreeStillSavesAsFiveFiveOne() async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("oldtree-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let store = await TreeStore(storageFolder: root)
        let imported = try GEDCOMCodec.parse(fixture("gramps-anonymized")).tree
        #expect(imported.sourceVersion == .v551)
        _ = try await store.addTreeVerified(imported)

        let text = try await String(contentsOf: store.gedFileURL(for: imported), encoding: .utf8)
        #expect(text.contains("2 VERS 5.5.1"))
        #expect(!text.contains("2 VERS 7.0.18"))
    }

    /// Undo snapshots, rollback snapshots and `deepCopy` all round-trip a tree through
    /// JSON, and none of them may lose the version it is stored in.
    @Test func theVersionSurvivesAJSONRoundTrip() throws {
        let fresh = FamilyTree(name: "Fresh")
        #expect(try fresh.deepCopy().sourceVersion == .v70)

        let imported = try GEDCOMCodec.parse(fixture("gramps-anonymized")).tree
        #expect(try imported.deepCopy().sourceVersion == .v551)
    }

    /// The file needs "7.0.18"; a label wants "7.0". Keeping both honest matters
    /// because the card and the export picker now read the same property.
    @Test func displayNameIsNotTheHeaderValue() {
        #expect(GEDCOMVersion.v70.headerValue == "7.0.18")
        #expect(GEDCOMVersion.v70.displayName == "7.0")
        #expect(GEDCOMVersion.v551.headerValue == "5.5.1")
        #expect(GEDCOMVersion.v551.displayName == "5.5.1")
    }

    // MARK: - Escaping

    @Test func aValueShapedLikeAPointerSurvivesSevenZeroEscaping() throws {
        let tree = makeTree()
        tree.people[0].notes = "@I1@"
        let text = v7(tree)
        #expect(text.contains("1 NOTE @@I1@"))
        let reread = try GEDCOMCodec.parse(text)
        let father = try #require(reread.tree.people.first { $0.givenNames == "Иван" })
        #expect(father.notes == "@I1@")
    }

    /// The 5.5.1 form has to keep reading too — every file already on disk uses it.
    @Test func theFiveFiveOneEscapingStillReadsBack() throws {
        let reread = try GEDCOMCodec.parse("0 HEAD\n0 @I1@ INDI\n1 NOTE @@X@@\n0 TRLR")
        #expect(reread.tree.people.first?.notes == "@X@")
    }
}
