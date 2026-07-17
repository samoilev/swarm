@testable import FamilyTreeCore
import Foundation
import Testing

struct TrustCompletenessTests {
    private final class Temp {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("fts-v2-tests-\(UUID().uuidString)", isDirectory: true)
        init() throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    @Test func genealogyDatesKeepQualifiersRangesAndImportedText() {
        let about = GenealogyDate(rawGEDCOM: "ABT 1901")
        #expect(about.qualifier == .about)
        #expect(about.canonicalGEDCOMValue == "ABT 1901")
        #expect(about.isValid)

        let range = GenealogyDate(rawGEDCOM: "BET 1 JAN 1900 AND 31 DEC 1901")
        #expect(range.qualifier == .between)
        #expect(range.start?.year == 1900)
        #expect(range.end?.year == 1901)
        #expect(range.isValid)

        let invalidImported = GenealogyDate(rawGEDCOM: "около весны неизвестного года")
        #expect(!invalidImported.isValid)
        #expect(invalidImported.canonicalGEDCOMValue == "около весны неизвестного года")
        #expect(GenealogyDate(userInput: "31.02.2000").isValid == false)
    }

    @Test func editSessionCancelCannotMutateLiveTree() throws {
        let tree = FamilyTree(name: "Живое дерево")
        let person = Person(givenNames: "Анна")
        tree.people = [person]
        let session = try EditSession(tree: tree)
        let draftPerson = try #require(session.draftTree.people.first)
        draftPerson.notes = "Черновик"
        draftPerson.attachments = [Attachment(storedName: "draft.pdf", originalName: "draft.pdf")]
        session.draftTree.sourceRecords = [SourceRecord(title: "Черновой источник")]
        session.draftTree.unions = [Union(partner1Id: draftPerson.id)]

        #expect(person.notes == nil)
        #expect(person.attachments.isEmpty)
        #expect(tree.sourceRecords.isEmpty)
        #expect(tree.unions.isEmpty)
    }

    @Test func preservationCodecReportsAndRetainsForeignStructures() throws {
        let temp = try Temp()
        let gedcom = """
        0 HEAD
        1 SOUR ForeignApp
        2 VERS 9.2
        1 CHAR UTF-8
        1 NOTE header note
        0 @S1@ SOUR
        1 TITL Перепись
        1 RIN source-rin
        0 @I1@ INDI
        1 _FTSID 11111111-1111-1111-1111-111111111111
        1 NAME Иван /Иванов/
        2 TYPE birth
        2 GIVN Иван
        2 SURN Иванов
        1 BIRT
        2 DATE BET 1900 AND 1902
        2 PLAC Москва
        2 SOUR @S1@
        3 PAGE л. 4
        2 AGNC Архив
        1 OBJE
        2 FILE missing.jpg
        1 FAMC @F404@
        1 CHAN
        2 DATE 1 JAN 2020
        1 RIN person-rin
        1 ALIA @I404@
        """
        let source = temp.url.appendingPathComponent("foreign.ged")
        try gedcom.write(to: source, atomically: true, encoding: .utf8)

        let result = try GEDCOMCodec.parse(source)
        #expect(result.report.warnings.contains { $0.id == "gedcom.missing-trailer" })
        #expect(result.report.unresolvedPointers.contains("F404"))
        #expect(result.report.unresolvedPointers.contains("I404"))
        #expect(result.report.missingMedia.contains("missing.jpg"))
        #expect(result.report.preservedUnsupportedTags.contains("AGNC"))
        #expect(result.tree.sourceRecords.first?.title == "Перепись")
        #expect(result.tree.people.first?.event(ofKind: .birth)?.citations.first?.page == "л. 4")

        let exported = try GEDCOMCodec.serialize(tree: result.tree, document: result.document).gedcom
        #expect(exported.contains("2 AGNC Архив"))
        #expect(exported.contains("1 RIN person-rin"))
        #expect(exported.contains("0 @S1@ SOUR"))
        #expect(exported.contains("1 FAMC @F404@") || result.report.unresolvedPointers.contains("F404"))
    }

    @Test func preservationCodecKeepsForeignTopLevelOrderAndRawRecord() throws {
        let rawNote = "0 @N1@ NOTE\n1 CONT foreign raw text"
        let gedcom = "0 HEAD\n1 SOUR Foreign\n\(rawNote)\n0 @I1@ INDI\n1 NAME A /B/\n0 _CUSTOM untouched\n1 RIN custom-rin\n0 TRLR"
        let result = try GEDCOMCodec.parse(gedcom)
        result.tree.people[0].givenNames = "Changed"
        let exported = try GEDCOMCodec.serialize(tree: result.tree, document: result.document).gedcom
        let noteOffset = try #require(exported.range(of: rawNote)?.lowerBound)
        let personOffset = try #require(exported.range(of: "0 @I1@ INDI")?.lowerBound)
        let customOffset = try #require(exported.range(of: "0 _CUSTOM untouched\n1 RIN custom-rin")?.lowerBound)
        #expect(noteOffset < personOffset)
        #expect(personOffset < customOffset)
        #expect(exported.contains("1 NAME Changed /B/"))
    }

    @Test(arguments: [
        ("gramps-anonymized", "Gramps"),
        ("ancestry-anonymized", "_APID 1,0000::42"),
        ("myheritage-anonymized", "_UID foreign-uid-must-remain-foreign"),
    ])
    func anonymizedVendorFixturesRemainImportableAndPreserved(name: String, marker: String) throws {
        let fixture = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "ged",
            subdirectory: "Fixtures"
        ))
        let result = try GEDCOMCodec.parse(fixture)
        #expect(result.report.blockingErrors.isEmpty)
        #expect(!result.tree.people.isEmpty)
        let exported = try GEDCOMCodec.serialize(tree: result.tree, document: result.document).gedcom
        #expect(exported.contains(marker))
    }

    @Test func structurallyUnreadableGEDCOMIsRejected() {
        var rejected = false
        do { _ = try GEDCOMCodec.parse("0 HEAD\n2 CHAR UTF-8\n0 TRLR") }
        catch { rejected = true }
        #expect(rejected)

        rejected = false
        do { _ = try GEDCOMCodec.parse("not gedcom") }
        catch { rejected = true }
        #expect(rejected)
    }

    @Test func importedInvalidDataRemainsEditableUntilItIsWorsened() async throws {
        let temp = try Temp()
        let sourceFolder = try Temp()
        let source = sourceFolder.url.appendingPathComponent("invalid-date.ged")
        try "0 HEAD\n1 _NAME Imported\n0 @I1@ INDI\n1 NAME A /B/\n1 BIRT\n2 DATE 31 FEB 1900\n0 TRLR"
            .write(to: source, atomically: true, encoding: .utf8)
        let store = TreeStore(storageFolder: temp.url)
        let result = try await store.importGEDCOM(from: source)
        let tree = result.tree
        let person = try #require(tree.people.first)
        let initial = TreeValidator.validate(tree, context: .init(
            acceptedBaselineIssueIDs: tree.acceptedBaselineIssueIDs
        ))
        #expect(initial.contains { $0.code == "date.invalid" && !$0.isBlocking })

        person.notes = "Unrelated edit"
        _ = try await store.saveTree(tree)
        var event = try #require(person.event(ofKind: .birth))
        event.date = GenealogyDate(rawGEDCOM: "32 FEB 1900")
        person.replaceEvent(event)
        var blocked = false
        do { _ = try await store.saveTree(tree) }
        catch { blocked = true }
        #expect(blocked)
    }

    @Test func validatorBlocksNewStructuralErrorsButAcceptsImportedBaseline() {
        let tree = FamilyTree(name: "Проверка")
        let parent = Person(givenNames: "Родитель", sex: .unknown)
        let child = Person(givenNames: "Ребёнок", sex: .unknown)
        child.events = [GenealogyEvent(
            kind: .birth,
            date: GenealogyDate(rawGEDCOM: "31 FEB 2000"),
            place: PlaceReference(displayName: "Ошибка", latitude: 95, longitude: 200)
        )]
        tree.people = [parent, child]
        tree.parentLinks = [
            ParentLink(parentID: parent.id, childID: child.id),
            ParentLink(parentID: child.id, childID: parent.id),
        ]

        let issues = TreeValidator.validate(tree)
        #expect(issues.contains { $0.code == "relationship.ancestry-cycle" && $0.isBlocking })
        #expect(issues.contains { $0.code == "date.invalid" && $0.isBlocking })
        #expect(issues.contains { $0.code == "place.invalid-coordinate" && $0.isBlocking })

        let accepted = Set(issues.map(\.id))
        let baseline = TreeValidator.validate(tree, context: .init(acceptedBaselineIssueIDs: accepted))
        #expect(baseline.allSatisfy { !$0.isBlocking })

        child.events[0].place?.latitude = 96
        let worsened = TreeValidator.validate(tree, context: .init(acceptedBaselineIssueIDs: accepted))
        #expect(worsened.contains { $0.code == "place.invalid-coordinate" && $0.isBlocking })
    }

    @Test func neutralAndTypedParentageNamesAreUsed() {
        let tree = FamilyTree(name: "Термины")
        let parent = Person(givenNames: "А", sex: .unknown)
        let child = Person(givenNames: "Б", sex: .unknown)
        tree.people = [parent, child]
        let union = Union(partner1Id: parent.id, childrenIds: [child.id])
        tree.unions = [union]
        tree.parentLinks = [ParentLink(parentID: parent.id, childID: child.id, unionID: union.id, kind: .adoptive)]
        let result = RelationshipCalculator(tree: tree).relationship(from: child, to: parent)
        #expect(result?.name == "Приёмный родитель")
        #expect(result?.description == ParentageKind.adoptive.displayName)
    }

    @Test func selectedPlaceReferenceKeepsStableIdentityAndExactCoordinates() {
        let place = PlaceEntry(
            id: "625144",
            name: "Минск",
            region: "Минск",
            country: "Беларусь",
            latitude: 53.9,
            longitude: 27.5667,
            aliases: ["Менск"]
        )
        let reference = place.placeReference
        #expect(reference.datasetID == "625144")
        #expect(reference.displayName == "Минск, Минск, Беларусь")
        #expect(reference.latitude == 53.9)
        #expect(reference.longitude == 27.5667)
        #expect(!reference.isCustom)
    }

    @Test func bundledPlaceIndexUsesGeoNamesIdentityAndAliases() async throws {
        await withCheckedContinuation { continuation in
            PlacesDatabase.shared.whenReady { continuation.resume() }
        }
        let minsk = try #require(PlacesDatabase.shared.search("Менск").first { $0.id == "625144" })
        #expect(minsk.name == "Минск")
        #expect(minsk.latitude == 53.9)
        #expect(minsk.longitude == 27.56667)
    }

    @Test func mergePreviewNeverAutomaticallyAcceptsHeuristics() {
        let temp = try? Temp()
        let store = TreeStore(storageFolder: temp?.url)
        let local = FamilyTree(name: "Локальное")
        let left = Person(givenNames: "Анна", surname: "Иванова", birthDate: "1900", birthPlace: "Москва")
        local.people = [left]
        let incoming = FamilyTree(name: "Входящее")
        let right = Person(givenNames: "Анна", surname: "Иванова", birthDate: "1900", birthPlace: "Москва")
        incoming.people = [right]

        let preview = TreeMergeEngine(store: store).preview(local: local, incoming: incoming)
        #expect(preview.automaticMatches.isEmpty)
        #expect(preview.heuristicSuggestions.count == 1)
        #expect(preview.acceptedHeuristicMatchIDs.isEmpty)
    }

    @Test func verifiedMergeCreatesBackupAndAppliesSafeMatches() async throws {
        let temp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        let local = FamilyTree(name: "Локальное")
        let same = Person(givenNames: "Иван", surname: "Петров")
        local.people = [same]
        store.addTree(local)

        let incoming = FamilyTree(name: "Входящее")
        let matching = Person(givenNames: "Иван", surname: "Петров")
        matching.id = same.id
        matching.notes = "Из входящего файла"
        let newPerson = Person(givenNames: "Мария", surname: "Петрова")
        incoming.people = [matching, newPerson]

        let engine = TreeMergeEngine(store: store)
        let preview = engine.preview(local: local, incoming: incoming)
        #expect(preview.automaticMatches.count == 1)
        let receipt = try await engine.apply(preview, to: local)
        #expect(local.people.count == 2)
        #expect(local.person(byId: same.id)?.notes == "Из входящего файла")
        #expect(receipt.recoverySnapshotURL == nil)
        #expect(store.recoveryItems(for: local).contains { $0.kind == .migrationBackup && $0.displayName.contains("pre-merge") })
    }

    @Test func mergeCopiesAttachmentBytesEvidenceAndMediaLinks() async throws {
        let localTemp = try Temp()
        let incomingTemp = try Temp()
        let sourceTemp = try Temp()
        let localStore = TreeStore(storageFolder: localTemp.url)
        let incomingStore = TreeStore(storageFolder: incomingTemp.url)

        let local = FamilyTree(name: "Local")
        let localPerson = Person(givenNames: "Анна")
        local.people = [localPerson]
        localStore.addTree(local)

        let incoming = FamilyTree(name: "Incoming")
        let incomingPerson = Person(givenNames: "Анна")
        incomingPerson.id = localPerson.id
        incoming.people = [incomingPerson]
        incomingStore.addTree(incoming)
        let bytes = Data("merge evidence".utf8)
        let sourceFile = sourceTemp.url.appendingPathComponent("evidence.txt")
        try bytes.write(to: sourceFile)
        var attachment = try incomingStore.prepareAttachment(in: incoming, sourceURL: sourceFile)
        let source = SourceRecord(title: "Archive")
        incoming.sourceRecords = [source]
        attachment.notes = "Attachment note"
        attachment.citations = [Citation(sourceID: source.id, page: "7")]
        incomingPerson.attachments = [attachment]
        incomingPerson.events = [GenealogyEvent(
            kind: .birth,
            mediaIDs: [attachment.id.uuidString]
        )]
        _ = try await incomingStore.saveTree(incoming)

        let engine = TreeMergeEngine(store: localStore)
        let preview = engine.preview(local: local, incoming: incoming)
        _ = try await engine.apply(preview, to: local)
        let mergedAttachment = try #require(localPerson.attachments.first)
        #expect(try Data(contentsOf: localStore.attachmentURL(mergedAttachment, in: local)) == bytes)
        #expect(mergedAttachment.notes == "Attachment note")
        #expect(mergedAttachment.citations.first?.page == "7")
        #expect(local.sourceRecords.contains { $0.id == mergedAttachment.citations.first?.sourceID })
        #expect(localPerson.event(ofKind: .birth)?.mediaIDs == [mergedAttachment.id.uuidString])
    }

    @Test func stagedFaultsLeaveCommittedGEDCOMByteForByteUsable() throws {
        let temp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        let tree = FamilyTree(name: "Транзакция")
        let person = Person(givenNames: "До", surname: "Сбоя")
        tree.people = [person]
        store.addTree(tree)
        let gedcomURL = store.gedFileURL(for: tree)
        let committed = try Data(contentsOf: gedcomURL)

        for point in [PersistenceFaultPoint.gedcomWrite, .historyPrune, .directorySwap] {
            person.givenNames = "После \(point.rawValue)"
            store.faultInjector = { if $0 == point { throw CocoaError(.fileWriteUnknown) } }
            #expect(store.saveTree(tree) == nil)
            #expect(try Data(contentsOf: gedcomURL) == committed)
            #expect(TreeStore(storageFolder: temp.url).trees.first?.people.first?.givenNames == "До")
        }
        store.faultInjector = nil

        let exportFolder = temp.url.appendingPathComponent("Exports", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)
        store.faultInjector = { if $0 == .exportCopy { throw CocoaError(.fileWriteUnknown) } }
        var exportFailed = false
        do { _ = try store.exportTree(tree, toDirectory: exportFolder) }
        catch { exportFailed = true }
        #expect(exportFailed)
        #expect(try (FileManager.default.contentsOfDirectory(at: exportFolder, includingPropertiesForKeys: nil)).isEmpty)
    }

    @Test func originalImportFailureDoesNotCommitTree() throws {
        let temp = try Temp()
        let sourceFolder = try Temp()
        let source = sourceFolder.url.appendingPathComponent("input.ged")
        try "0 HEAD\n1 _NAME Import\n0 @I1@ INDI\n1 NAME A /B/\n0 TRLR".write(to: source, atomically: true, encoding: .utf8)
        let store = TreeStore(storageFolder: temp.url)
        store.faultInjector = { if $0 == .originalImportCopy { throw CocoaError(.fileWriteUnknown) } }
        var failed = false
        do { _ = try store.importGEDCOM(from: source) }
        catch { failed = true }
        #expect(failed)
        #expect(store.trees.isEmpty)
        #expect(try (FileManager.default.contentsOfDirectory(at: temp.url, includingPropertiesForKeys: nil)).allSatisfy { $0.lastPathComponent.hasPrefix(".") })
    }

    @Test func deletedAttachmentCanBeRestoredFromInternalTrash() async throws {
        let temp = try Temp()
        let sourceFolder = try Temp()
        let source = sourceFolder.url.appendingPathComponent("record.txt")
        try Data("family record".utf8).write(to: source)
        let store = TreeStore(storageFolder: temp.url)
        let tree = FamilyTree(name: "Восстановление")
        let person = Person(givenNames: "Анна")
        tree.people = [person]
        store.addTree(tree)

        let attachment = try store.prepareAttachment(in: tree, sourceURL: source)
        person.attachments.append(attachment)
        _ = try await store.saveTree(tree)
        person.attachments.removeAll()
        _ = try await store.saveTree(tree)
        let trashItem = try #require(store.recoveryItems(for: tree).first { $0.kind == .deletedFile })

        _ = try await store.restoreDeletedFile(trashItem, to: person, in: tree, asPortrait: false)
        #expect(person.attachments.count == 1)
        #expect(person.attachments.first?.originalName == "record.txt")
        #expect(FileManager.default.fileExists(atPath: store.attachmentURL(person.attachments[0], in: tree).path))
    }

    @Test func restoringAttachmentMetadataAlsoRestoresJournaledBytes() async throws {
        let temp = try Temp()
        let sourceFolder = try Temp()
        let source = sourceFolder.url.appendingPathComponent("journal.txt")
        let bytes = Data("undo restores these bytes".utf8)
        try bytes.write(to: source)
        let store = TreeStore(storageFolder: temp.url)
        let tree = FamilyTree(name: "Журнал файлов")
        let person = Person(givenNames: "Анна")
        tree.people = [person]
        store.addTree(tree)

        let attachment = try store.prepareAttachment(in: tree, sourceURL: source)
        person.attachments = [attachment]
        _ = try await store.saveTree(tree)
        person.attachments = []
        _ = try await store.saveTree(tree)
        #expect(!FileManager.default.fileExists(atPath: store.attachmentURL(attachment, in: tree).path))

        person.attachments = [attachment]
        _ = try await store.saveTree(tree)
        #expect(try Data(contentsOf: store.attachmentURL(attachment, in: tree)) == bytes)
    }

    @Test func portraitWriteFaultKeepsPreviousBundleAndDirtyBytes() async throws {
        let temp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        let tree = FamilyTree(name: "Портрет")
        let person = Person(givenNames: "До")
        tree.people = [person]
        store.addTree(tree)
        let gedcom = store.gedFileURL(for: tree)
        let before = try Data(contentsOf: gedcom)

        person.photoData = Data([0xFF, 0xD8, 0xFF, 0xD9])
        store.faultInjector = { if $0 == .portraitWrite { throw CocoaError(.fileWriteUnknown) } }
        var failed = false
        do { _ = try await store.saveTree(tree) }
        catch { failed = true }
        #expect(failed)
        #expect(person.photoIsDirty)
        #expect(try Data(contentsOf: gedcom) == before)
    }

    @Test func revisionHistoryIsBoundedToLatestFifty() async throws {
        let temp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        let tree = FamilyTree(name: "История")
        let person = Person(givenNames: "Редакция")
        tree.people = [person]
        store.addTree(tree)

        for revision in 0 ..< 55 {
            person.notes = "Версия \(revision)"
            _ = try await store.saveTree(tree)
        }
        let revisions = store.recoveryItems(for: tree).filter { $0.kind == .revision }
        #expect(revisions.count == 50)
    }

    @Test func archivedTreeCanBeRestoredIntoLibrary() throws {
        let temp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        let tree = FamilyTree(name: "Архив")
        tree.people = [Person(givenNames: "Анна")]
        store.addTree(tree)

        let archiveURL = store.archiveTree(tree)
        #expect(FileManager.default.fileExists(atPath: archiveURL.path))
        #expect(store.trees.isEmpty)
        let item = try #require(store.recoveryItems().first { $0.kind == .archivedTree })
        let restored = try store.restoreArchivedTree(item)
        #expect(restored.id == tree.id)
        #expect(store.trees.contains { $0.id == tree.id })
    }

    @Test func tenThousandPersonIndexesAvoidPortraitLoading() {
        let tree = FamilyTree(name: "Большое")
        tree.people = (0 ..< 10000).map { index in
            Person(
                givenNames: "Имя \(index)",
                surname: "Фамилия \(index % 250)",
                birthDate: String(1800 + index % 220),
                birthPlace: "Место \(index % 100)"
            )
        }
        let started = Date()
        let indexes = TreeWorkspaceIndexes(tree: tree)
        #expect(indexes.searchEntries.count == 10000)
        #expect(indexes.timelineEntries.count == 10000)
        #expect(tree.people.allSatisfy { !$0.photoIsDirty })
        #expect(Date().timeIntervalSince(started) < 10)
    }
}
