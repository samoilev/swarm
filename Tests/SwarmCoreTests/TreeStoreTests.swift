import Foundation
@testable import SwarmCore
import Testing

/// Integration tests for TreeStore's persistence, migration and folder-reconcile
/// logic. Each test runs against a throwaway temp directory (injected via
/// `TreeStore(storageFolder:)`), so nothing touches the real Application Support.
@Suite(.serialized)
struct TreeStoreTests {

    /// A unique temp directory that is removed when the test's `Temp` goes away.
    private final class Temp {
        let url: URL
        init() {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("swarm-tests-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    private func makeTree() -> FamilyTree {
        let tree = FamilyTree(name: "Семья Ивановых", subtitle: "Ветвь")
        let a = Person(givenNames: "Иван", surname: "Иванов", sex: .male)
        let b = Person(givenNames: "Мария", surname: "Иванова", sex: .female)
        tree.people = [a, b]
        tree.unions = [Union(partner1Id: a.id, partner2Id: b.id)]
        tree.homePersonId = a.id
        return tree
    }

    @Test func defaultStorageMigrationMovesLegacyRootAndMetadata() throws {
        let temp = Temp()
        let fm = FileManager.default
        let legacyRoot = temp.url.appendingPathComponent("FamilyTreeStudio", isDirectory: true)
        let history = legacyRoot
            .appendingPathComponent("Tree/.FamilyTreeStudio/History", isDirectory: true)
        try fm.createDirectory(at: history, withIntermediateDirectories: true)
        try Data("revision".utf8).write(to: history.appendingPathComponent("one.ged"))

        let preparation = TreeStore.prepareDefaultStorage(in: temp.url)
        let currentRoot = temp.url.appendingPathComponent("Swarm", isDirectory: true)
        let migratedHistory = currentRoot
            .appendingPathComponent("Tree/.Swarm/History/one.ged")

        #expect(preparation.folder == currentRoot)
        #expect(preparation.warning == nil)
        #expect(!fm.fileExists(atPath: legacyRoot.path))
        #expect(try Data(contentsOf: migratedHistory) == Data("revision".utf8))
    }

    @Test func defaultStorageMigrationNeverMergesExistingRoots() throws {
        let temp = Temp()
        let fm = FileManager.default
        let currentRoot = temp.url.appendingPathComponent("Swarm", isDirectory: true)
        let legacyRoot = temp.url.appendingPathComponent("FamilyTreeStudio", isDirectory: true)
        try fm.createDirectory(at: currentRoot, withIntermediateDirectories: true)
        try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        try Data("current".utf8).write(to: currentRoot.appendingPathComponent("current.txt"))
        try Data("legacy".utf8).write(to: legacyRoot.appendingPathComponent("legacy.txt"))

        let preparation = TreeStore.prepareDefaultStorage(in: temp.url)

        #expect(preparation.folder == currentRoot)
        #expect(preparation.warning != nil)
        #expect(preparation.warningURL == legacyRoot)
        #expect(try Data(contentsOf: currentRoot.appendingPathComponent("current.txt")) == Data("current".utf8))
        #expect(try Data(contentsOf: legacyRoot.appendingPathComponent("legacy.txt")) == Data("legacy".utf8))
    }

    @Test func defaultStorageMigrationNeverMergesMetadataFolders() throws {
        let temp = Temp()
        let fm = FileManager.default
        let treeRoot = temp.url.appendingPathComponent("Swarm/Tree", isDirectory: true)
        let currentMetadata = treeRoot.appendingPathComponent(".Swarm", isDirectory: true)
        let legacyMetadata = treeRoot.appendingPathComponent(".FamilyTreeStudio", isDirectory: true)
        try fm.createDirectory(at: currentMetadata, withIntermediateDirectories: true)
        try fm.createDirectory(at: legacyMetadata, withIntermediateDirectories: true)
        try Data("current".utf8).write(to: currentMetadata.appendingPathComponent("current.txt"))
        try Data("legacy".utf8).write(to: legacyMetadata.appendingPathComponent("legacy.txt"))

        let preparation = TreeStore.prepareDefaultStorage(in: temp.url)

        #expect(preparation.warning != nil)
        #expect(preparation.warningURL == temp.url.appendingPathComponent("Swarm", isDirectory: true))
        #expect(try Data(contentsOf: currentMetadata.appendingPathComponent("current.txt")) == Data("current".utf8))
        #expect(try Data(contentsOf: legacyMetadata.appendingPathComponent("legacy.txt")) == Data("legacy".utf8))
    }

    @Test func saveThenLoadRoundTrips() async throws {
        let temp = Temp()
        let store = TreeStore(storageFolder: temp.url)
        let tree = makeTree()
        _ = try await store.addTreeVerified(tree)
        let id = tree.id

        // A fresh store over the same folder must re-read the tree from disk.
        let reloaded = TreeStore(storageFolder: temp.url)
        #expect(reloaded.trees.count == 1)
        let loaded = try #require(reloaded.trees.first)
        #expect(loaded.id == id) // identity preserved via _TREEID
        #expect(loaded.name == "Семья Ивановых")
        #expect(loaded.subtitle == "Ветвь")
        #expect(loaded.people.count == 2)
        #expect(loaded.unions.count == 1)
        // Person ids are regenerated on parse, so home resolves within the reloaded
        // tree (the home person was serialized first → is people[0] on reload).
        #expect(loaded.homePersonId == loaded.people.first?.id)
    }

    @Test func readableFolderNamedAfterTree() async throws {
        let temp = Temp()
        let store = TreeStore(storageFolder: temp.url)
        _ = try await store.addTreeVerified(makeTree())
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: temp.url.path)) ?? []
        // Folder is named after the tree (readable), not a bare UUID.
        #expect(entries.contains("Семья Ивановых"))
    }

    @Test func renameMovesFolderAndKeepsIdentity() async throws {
        let temp = Temp()
        let store = TreeStore(storageFolder: temp.url)
        let tree = makeTree()
        _ = try await store.addTreeVerified(tree)
        _ = try await store.renameTreeVerified(tree, name: "Род Петровых", subtitle: nil)

        let entries = Set((try? FileManager.default.contentsOfDirectory(atPath: temp.url.path)) ?? [])
        #expect(entries.contains("Род Петровых"))
        #expect(!entries.contains("Семья Ивановых")) // old folder gone

        let reloaded = TreeStore(storageFolder: temp.url)
        #expect(reloaded.trees.count == 1)
        #expect(reloaded.trees.first?.id == tree.id) // same identity after rename
    }

    @Test func collidingNamesGetDistinctFolders() async throws {
        let temp = Temp()
        let store = TreeStore(storageFolder: temp.url)
        let t1 = FamilyTree(name: "Дерево")
        let t2 = FamilyTree(name: "Дерево")
        _ = try await store.addTreeVerified(t1)
        _ = try await store.addTreeVerified(t2)
        let entries = Set((try? FileManager.default.contentsOfDirectory(atPath: temp.url.path)) ?? [])
        #expect(entries.contains("Дерево"))
        #expect(entries.contains("Дерево 2")) // second tree suffixed, not clobbered
        #expect(TreeStore(storageFolder: temp.url).trees.count == 2)
    }

    @Test func corruptGedIsSkippedNotFatal() async throws {
        let temp = Temp()
        let store = TreeStore(storageFolder: temp.url)
        _ = try await store.addTreeVerified(makeTree())

        // Drop a garbage tree folder alongside the good one.
        let bad = temp.url.appendingPathComponent("Битое", isDirectory: true)
        try? FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try? "not a gedcom at all".write(to: bad.appendingPathComponent("Битое.ged"), atomically: true, encoding: .utf8)

        let reloaded = TreeStore(storageFolder: temp.url)
        // The good tree still loads; a garbage .ged parses to an empty tree rather
        // than crashing the whole library.
        #expect(reloaded.trees.contains { $0.name == "Семья Ивановых" })
    }

    @Test func importPreservesOriginalFileVerbatim() async throws {
        let temp = Temp()
        let inbox = Temp() // source lives outside the storage folder
        let fm = FileManager.default
        let src = inbox.url.appendingPathComponent("incoming.ged")
        let raw = """
        0 HEAD
        1 _NAME Импортированное
        0 @I1@ INDI
        1 NAME Фёдор /Достоевский/
        1 SEX M
        2 CUSTOMTAG что-то незнакомое
        0 TRLR
        """
        try raw.write(to: src, atomically: true, encoding: .utf8)

        let store = TreeStore(storageFolder: temp.url)
        let tree = try await store.importGEDCOM(from: src).tree

        // The verbatim copy exists and matches the source byte-for-byte.
        let original = store.gedFileURL(for: tree).deletingLastPathComponent()
            .appendingPathComponent("original-import.ged")
        #expect(fm.fileExists(atPath: original.path))
        #expect(try Data(contentsOf: original) == Data(contentsOf: src))

        // A subsequent save (which prunes stale .ged files) must not delete it.
        _ = try await store.saveTree(tree)
        #expect(fm.fileExists(atPath: original.path))

        // Reloading must pick the working file, not the original copy.
        let reloaded = TreeStore(storageFolder: temp.url)
        #expect(reloaded.trees.count == 1)
        #expect(reloaded.trees.first?.name == "Импортированное")
    }

    @Test func importCarriesPhotosAndLazyLoads() async throws {
        let temp = Temp()
        let inbox = Temp()
        let fm = FileManager.default
        let src = inbox.url.appendingPathComponent("withphoto.ged")
        let gedcom = """
        0 HEAD
        1 _NAME С фото
        0 @I1@ INDI
        1 NAME Лев /Толстой/
        1 SEX M
        1 OBJE
        2 FILE I1.jpg
        2 FORM JPEG
        0 TRLR
        """
        try gedcom.write(to: src, atomically: true, encoding: .utf8)
        // A sibling Media/ folder holds the portrait bytes.
        let srcMedia = inbox.url.appendingPathComponent("Media", isDirectory: true)
        try fm.createDirectory(at: srcMedia, withIntermediateDirectories: true)
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x11, 0x22, 0x33]) // stand-in JPEG bytes
        try bytes.write(to: srcMedia.appendingPathComponent("I1.jpg"))

        let store = TreeStore(storageFolder: temp.url)
        let tree = try await store.importGEDCOM(from: src).tree
        // The portrait was copied into the tree's own Media/ folder…
        let treeMedia = store.gedFileURL(for: tree).deletingLastPathComponent()
            .appendingPathComponent("Media/I1.jpg")
        #expect(fm.fileExists(atPath: treeMedia.path))
        // …and loads lazily through the model (bytes were never eagerly read on parse).
        #expect(tree.people.first?.photoData == bytes)

        // A fresh store loads the same tree and can still resolve the portrait.
        let reloaded = TreeStore(storageFolder: temp.url)
        let person = try #require(reloaded.trees.first?.people.first)
        #expect(person.photoFilename == "I1.jpg")
        #expect(person.photoData == bytes)

        // Editing a non-photo field and saving must NOT drop or rewrite the portrait.
        person.occupation = "Писатель"
        _ = try await reloaded.saveTree(reloaded.trees[0])
        #expect(fm.fileExists(atPath: treeMedia.path))
        #expect(try Data(contentsOf: treeMedia) == bytes)
    }

    /// An editor works on `deepCopy()` of the tree, and that copy goes through JSON,
    /// which cannot carry the transient Media/ folder each person loads its portrait
    /// from. Unless the copy's folders are refreshed, the draft reads back no portrait
    /// and saving the draft erases the photo of anyone edited for any other reason.
    @Test func draftCopyStillResolvesPortraitsAfterRefresh() async throws {
        let temp = Temp()
        let store = TreeStore(storageFolder: temp.url)
        let tree = makeTree()
        try await store.addTreeVerified(tree)
        let bytes = Data([0xFF, 0xD8, 0xFF, 0xD9])
        tree.people[0].photoData = bytes
        _ = try await store.saveTree(tree)

        let draft = try tree.deepCopy()
        #expect(draft.people[0].photoFilename != nil)
        #expect(draft.people[0].photoData == nil) // no Media/ folder survived the copy
        store.refreshMediaFolders(for: draft)
        #expect(draft.people[0].photoData == bytes)
    }

    @Test func migratesLegacyFlatLayout() throws {
        let temp = Temp()
        let fm = FileManager.default
        // Old flat layout: <UUID>.ged + Media_<UUID>/ at the storage root.
        let id = UUID()
        let ged = """
        0 HEAD
        1 _TREEID \(id.uuidString)
        1 _NAME Старое дерево
        0 @I1@ INDI
        1 NAME Пётр /Сидоров/
        1 SEX M
        0 TRLR
        """
        try ged.write(to: temp.url.appendingPathComponent("\(id.uuidString).ged"), atomically: true, encoding: .utf8)
        let oldMedia = temp.url.appendingPathComponent("Media_\(id.uuidString)", isDirectory: true)
        try fm.createDirectory(at: oldMedia, withIntermediateDirectories: true)
        try Data([0x1, 0x2, 0x3]).write(to: oldMedia.appendingPathComponent("I1.jpg"))

        let store = TreeStore(storageFolder: temp.url)
        #expect(store.trees.count == 1)
        let tree = try #require(store.trees.first)
        #expect(tree.name == "Старое дерево")
        #expect(tree.id == id) // _TREEID preserved through migration

        // Discovery is read-only: the old bytes remain untouched until the user runs
        // the explicit, backup-protected migration transaction.
        #expect(store.pendingMigrations.count == 1)
        #expect(fm.fileExists(atPath: temp.url.appendingPathComponent("\(id.uuidString).ged").path))

        // A pending migration is not a load failure — this tree opened. Reporting it as
        // one told the user their file hadn't been read, which was false and unactionable.
        #expect(store.lastLoadError == nil)
        let pending = try #require(store.pendingMigrations.first)
        #expect(pending.title == "Старое дерево") // names the tree, not just a count
        #expect(pending.source == .legacyFile)
        #expect(pending.url.lastPathComponent == "\(id.uuidString).ged")

        let receipts = try store.performPendingMigrations()
        #expect(receipts.count == 1)

        // Only after the verified transaction is the flat source moved into Recovery.
        let entries = Set((try? fm.contentsOfDirectory(atPath: temp.url.path)) ?? [])
        #expect(!entries.contains("\(id.uuidString).ged")) // flat file consumed
        #expect(store.pendingMigrations.count == 0)
    }

    @Test func oldFolderLayoutIsPendingMigrationNotLoadFailure() throws {
        let temp = Temp()
        let fm = FileManager.default
        // Old folder layout: <UUID>/tree.ged instead of a readable folder + filename.
        let id = UUID()
        let folder = temp.url.appendingPathComponent(id.uuidString, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let ged = """
        0 HEAD
        1 _TREEID \(id.uuidString)
        1 _NAME Юлия и Лев
        0 @I1@ INDI
        1 NAME Тимофей /Соколов/
        1 SEX M
        0 TRLR
        """
        try ged.write(to: folder.appendingPathComponent("tree.ged"), atomically: true, encoding: .utf8)

        let store = TreeStore(storageFolder: temp.url)
        // The tree opens and is fully usable; only its on-disk layout is old.
        #expect(store.trees.count == 1)
        #expect(store.lastLoadError == nil)
        #expect(store.pendingMigrations.count == 1)
        let pending = try #require(store.pendingMigrations.first)
        #expect(pending.title == "Юлия и Лев")
        #expect(pending.source == .treeFolder)

        try store.performPendingMigrations()
        #expect(store.pendingMigrations.isEmpty)
        #expect(store.lastLoadError == nil)
    }
}
