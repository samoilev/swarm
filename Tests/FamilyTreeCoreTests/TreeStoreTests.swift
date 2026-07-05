@testable import FamilyTreeCore
import Foundation
import Testing

/// Integration tests for TreeStore's persistence, migration and folder-reconcile
/// logic. Each test runs against a throwaway temp directory (injected via
/// `TreeStore(storageFolder:)`), so nothing touches the real Application Support.
struct TreeStoreTests {

    /// A unique temp directory that is removed when the test's `Temp` goes away.
    private final class Temp {
        let url: URL
        init() {
            url = FileManager.default.temporaryDirectory
                .appendingPathComponent("fts-tests-\(UUID().uuidString)", isDirectory: true)
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

    @Test func saveThenLoadRoundTrips() throws {
        let temp = Temp()
        let store = TreeStore(storageFolder: temp.url)
        let tree = makeTree()
        store.addTree(tree)
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

    @Test func readableFolderNamedAfterTree() {
        let temp = Temp()
        let store = TreeStore(storageFolder: temp.url)
        store.addTree(makeTree())
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: temp.url.path)) ?? []
        // Folder is named after the tree (readable), not a bare UUID.
        #expect(entries.contains("Семья Ивановых"))
    }

    @Test func renameMovesFolderAndKeepsIdentity() {
        let temp = Temp()
        let store = TreeStore(storageFolder: temp.url)
        let tree = makeTree()
        store.addTree(tree)
        store.renameTree(tree, name: "Род Петровых", subtitle: nil)

        let entries = Set((try? FileManager.default.contentsOfDirectory(atPath: temp.url.path)) ?? [])
        #expect(entries.contains("Род Петровых"))
        #expect(!entries.contains("Семья Ивановых")) // old folder gone

        let reloaded = TreeStore(storageFolder: temp.url)
        #expect(reloaded.trees.count == 1)
        #expect(reloaded.trees.first?.id == tree.id) // same identity after rename
    }

    @Test func collidingNamesGetDistinctFolders() {
        let temp = Temp()
        let store = TreeStore(storageFolder: temp.url)
        let t1 = FamilyTree(name: "Дерево")
        let t2 = FamilyTree(name: "Дерево")
        store.addTree(t1)
        store.addTree(t2)
        let entries = Set((try? FileManager.default.contentsOfDirectory(atPath: temp.url.path)) ?? [])
        #expect(entries.contains("Дерево"))
        #expect(entries.contains("Дерево 2")) // second tree suffixed, not clobbered
        #expect(TreeStore(storageFolder: temp.url).trees.count == 2)
    }

    @Test func corruptGedIsSkippedNotFatal() {
        let temp = Temp()
        let store = TreeStore(storageFolder: temp.url)
        store.addTree(makeTree())

        // Drop a garbage tree folder alongside the good one.
        let bad = temp.url.appendingPathComponent("Битое", isDirectory: true)
        try? FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try? "not a gedcom at all".write(to: bad.appendingPathComponent("Битое.ged"), atomically: true, encoding: .utf8)

        let reloaded = TreeStore(storageFolder: temp.url)
        // The good tree still loads; a garbage .ged parses to an empty tree rather
        // than crashing the whole library.
        #expect(reloaded.trees.contains { $0.name == "Семья Ивановых" })
    }

    @Test func importPreservesOriginalFileVerbatim() throws {
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
        let tree = try store.importGEDCOM(from: src)

        // The verbatim copy exists and matches the source byte-for-byte.
        let original = store.gedFileURL(for: tree).deletingLastPathComponent()
            .appendingPathComponent("original-import.ged")
        #expect(fm.fileExists(atPath: original.path))
        #expect(try Data(contentsOf: original) == Data(contentsOf: src))

        // A subsequent save (which prunes stale .ged files) must not delete it.
        store.saveTree(tree)
        #expect(fm.fileExists(atPath: original.path))

        // Reloading must pick the working file, not the original copy.
        let reloaded = TreeStore(storageFolder: temp.url)
        #expect(reloaded.trees.count == 1)
        #expect(reloaded.trees.first?.name == "Импортированное")
    }

    @Test func importCarriesPhotosAndLazyLoads() throws {
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
        let tree = try store.importGEDCOM(from: src)
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
        reloaded.saveTree(reloaded.trees[0])
        #expect(fm.fileExists(atPath: treeMedia.path))
        #expect(try Data(contentsOf: treeMedia) == bytes)
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

        // The flat .ged was folded into a per-tree folder with its Media alongside.
        let entries = Set((try? fm.contentsOfDirectory(atPath: temp.url.path)) ?? [])
        #expect(!entries.contains("\(id.uuidString).ged")) // flat file consumed
    }
}
