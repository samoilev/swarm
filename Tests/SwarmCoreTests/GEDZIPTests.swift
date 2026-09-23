import Foundation
@testable import SwarmCore
import Testing

/// GEDZIP (`.gdz`) is the GEDCOM 7.0 packaging format: one ZIP holding `gedcom.ged` at
/// its root beside the media its `FILE` payloads name.
struct GEDZIPTests {

    private func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("gedzip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Every *file* path inside an archive, via the same `ditto` round trip a reader
    /// uses. Directories are left out so this lines up with the manifest, which hashes
    /// regular files only.
    private func entries(in archive: URL) throws -> Set<String> {
        let unpacked = try temporaryDirectory()
        try GEDZIPArchive.extract(archive, to: unpacked)
        let root = unpacked.standardizedFileURL.path
        var found: Set<String> = []
        let walker = FileManager.default.enumerator(at: unpacked, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = walker?.nextObject() as? URL {
            guard try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(root) else { continue }
            var relative = String(path.dropFirst(root.count))
            if relative.hasPrefix("/") { relative.removeFirst() }
            if !relative.isEmpty { found.insert(relative) }
        }
        return found
    }

    // MARK: - Archive shape

    /// Written before anything depends on it: the whole design rests on `ditto` placing
    /// a directory's *contents* at the archive root, with no parent prefix and no
    /// `__MACOSX/` folder for readers on other systems to trip over.
    @Test func archivingADirectoryPutsItsContentsAtTheRoot() throws {
        let source = try temporaryDirectory()
        let fm = FileManager.default
        try fm.createDirectory(at: source.appendingPathComponent("Media"), withIntermediateDirectories: true)
        try fm.createDirectory(at: source.appendingPathComponent("Attachments"), withIntermediateDirectories: true)
        try "0 HEAD\n0 TRLR".write(
            to: source.appendingPathComponent(GEDZIPArchive.gedcomEntryName),
            atomically: true,
            encoding: .utf8
        )
        try Data([0xFF, 0xD8]).write(to: source.appendingPathComponent("Media/portrait.jpg"))
        try Data([0x25, 0x50]).write(to: source.appendingPathComponent("Attachments/deed.pdf"))

        let archive = try temporaryDirectory().appendingPathComponent("Род.gdz")
        try GEDZIPArchive.write(contentsOf: source, to: archive)

        let found = try entries(in: archive)
        #expect(found.contains("gedcom.ged"))
        #expect(found.contains("Media/portrait.jpg"))
        #expect(found.contains("Attachments/deed.pdf"))
        // The three ways this could go wrong: a wrapping parent folder, macOS metadata,
        // or the one path the spec reserves for something else.
        #expect(!found.contains { $0.hasPrefix("__MACOSX") })
        #expect(!found.contains { $0.hasPrefix("META-INF") })
        #expect(!found.contains { $0.hasPrefix(source.lastPathComponent) })
    }

    @Test func extractionRestoresContentByteForByte() throws {
        let source = try temporaryDirectory()
        let gedcom = "0 HEAD\n1 GEDC\n2 VERS 7.0.18\n0 TRLR"
        let bytes = Data((0 ..< 512).map { UInt8($0 % 251) })
        try gedcom.write(
            to: source.appendingPathComponent(GEDZIPArchive.gedcomEntryName),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createDirectory(
            at: source.appendingPathComponent("Media"),
            withIntermediateDirectories: true
        )
        try bytes.write(to: source.appendingPathComponent("Media/portrait.jpg"))

        let archive = try temporaryDirectory().appendingPathComponent("Род.gdz")
        try GEDZIPArchive.write(contentsOf: source, to: archive)
        let unpacked = try temporaryDirectory()
        try GEDZIPArchive.extract(archive, to: unpacked)

        #expect(
            try String(contentsOf: unpacked.appendingPathComponent(GEDZIPArchive.gedcomEntryName), encoding: .utf8)
                == gedcom
        )
        #expect(try Data(contentsOf: unpacked.appendingPathComponent("Media/portrait.jpg")) == bytes)
    }

    /// A damaged or mislabelled file must surface as an archive problem, not crash or
    /// read as something else.
    @Test func extractingSomethingThatIsNotAnArchiveFails() throws {
        let notAnArchive = try temporaryDirectory().appendingPathComponent("Род.gdz")
        try "0 HEAD\n0 TRLR".write(to: notAnArchive, atomically: true, encoding: .utf8)
        #expect(throws: GEDZIPArchive.Failure.self) {
            try GEDZIPArchive.extract(notAnArchive, to: temporaryDirectory())
        }
    }

    // MARK: - Export and round trip

    @MainActor
    private func storeWithTree() throws -> (TreeStore, FamilyTree, URL) {
        let root = try temporaryDirectory()
        let store = TreeStore(storageFolder: root)
        let tree = FamilyTree(name: "Род Ивановых")
        let father = Person(
            givenNames: "Иван", surname: "Иванов", sex: .male,
            birthDate: "05.03.1901", birthPlace: "Москва",
            deathDate: "12.11.1970", isLiving: false
        )
        let child = Person(givenNames: "Пётр", surname: "Иванов", sex: .male, isLiving: true)
        tree.people = [father, child]
        return (store, tree, root)
    }

    @MainActor
    @Test func exportWritesOneArchiveWithTheGEDCOMAtItsRoot() async throws {
        let (store, tree, root) = try storeWithTree()
        _ = try await store.addTreeVerified(tree)
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let receipt = try await store.exportTree(tree, to: destination)
        #expect(receipt.finalURL.pathExtension == "gdz")

        let found = try entries(in: receipt.finalURL)
        #expect(found.contains(GEDZIPArchive.gedcomEntryName))
        #expect(!found.contains { $0.hasPrefix("__MACOSX") || $0.hasPrefix("META-INF") })
        // Swarm's own bookkeeping belongs beside the archive, never inside it.
        #expect(!found.contains { $0.contains("original-import") })
        #expect(!found.contains { $0.contains("manifest.json") })
    }

    /// GEDZIP is defined only by GEDCOM 7.0, so a `.gdz` must never carry 5.5.1 however
    /// the caller asked for it.
    @MainActor
    @Test func anArchiveAlwaysCarriesSevenZeroEvenWhenFiveFiveOneWasRequested() async throws {
        let (store, tree, root) = try storeWithTree()
        tree.sourceVersion = .v551
        _ = try await store.addTreeVerified(tree)
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let receipt = try await store.exportTree(tree, to: destination, version: .v551)
        let unpacked = try temporaryDirectory()
        try GEDZIPArchive.extract(receipt.finalURL, to: unpacked)
        let text = try String(
            contentsOf: unpacked.appendingPathComponent(GEDZIPArchive.gedcomEntryName),
            encoding: .utf8
        )
        #expect(text.contains("2 VERS 7.0.18"))
        #expect(!text.contains("2 VERS 5.5.1"))
    }

    @MainActor
    @Test func theSidecarCarriesTheManifestBesideTheArchive() async throws {
        let (store, tree, root) = try storeWithTree()
        _ = try await store.addTreeVerified(tree)
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let receipt = try await store.exportTree(tree, to: destination)
        let sidecar = destination.appendingPathComponent(
            "\(receipt.finalURL.deletingPathExtension().lastPathComponent).swarm-manifest",
            isDirectory: true
        )
        let manifest = sidecar.appendingPathComponent("manifest.json")
        #expect(FileManager.default.fileExists(atPath: manifest.path))
        // The manifest describes the archive's contents, so its paths must be the
        // archive's entry paths.
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any]
        let hashes = json?["hashes"] as? [String: String] ?? [:]
        #expect(hashes.keys.contains(GEDZIPArchive.gedcomEntryName))
        #expect(try Set(hashes.keys) == entries(in: receipt.finalURL))
    }

    @MainActor
    @Test func anExportedArchiveReimportsWithItsPeopleIntact() async throws {
        let (store, tree, root) = try storeWithTree()
        _ = try await store.addTreeVerified(tree)
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let receipt = try await store.exportTree(tree, to: destination)

        // E350-01: merge parses whatever staging hands it, so staging must unpack.
        let staged = try store.stageImport(from: receipt.finalURL)
        #expect(staged.lastPathComponent == GEDZIPArchive.gedcomEntryName)
        let reread = try GEDCOMCodec.parse(staged)
        #expect(reread.report.blockingErrors.isEmpty)
        #expect(reread.tree.people.count == tree.people.count)
        #expect(Set(reread.tree.people.map(\.id)) == Set(tree.people.map(\.id)))
        #expect(reread.tree.sourceVersion == .v70)
    }

    @MainActor
    private func pendingEntries(in root: URL) -> [String] {
        let pending = root.appendingPathComponent(".Pending", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(atPath: pending.path)) ?? []
    }

    /// E350-03: the unpacked archive is only a stepping stone into the staged copy; it
    /// must be gone once staging returns, and nothing may be left after cancel or commit.
    @MainActor
    @Test func stagingAnArchiveLeavesNoExtractionBehind() async throws {
        let (store, tree, root) = try storeWithTree()
        _ = try await store.addTreeVerified(tree)
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let receipt = try await store.exportTree(tree, to: destination)

        let cancelled = try store.stageImport(from: receipt.finalURL)
        #expect(!pendingEntries(in: root).contains { $0.hasPrefix("Unpacked-") })
        store.discardImportPreview(at: cancelled)
        #expect(pendingEntries(in: root).isEmpty)

        let committed = try store.stageImport(from: receipt.finalURL)
        _ = try await store.importGEDCOM(from: committed)
        store.discardImportPreview(at: committed)
        #expect(pendingEntries(in: root).isEmpty)
    }

    /// E350-06/E350-03: an archive with two GEDCOMs and no `gedcom.ged` is refused by
    /// its own name — never a temporary folder's — and leaves nothing unpacked.
    @MainActor
    @Test func anAmbiguousArchiveNamesTheArchiveNotATempFolder() throws {
        let (store, _, root) = try storeWithTree()
        let source = try temporaryDirectory()
        for name in ["a.ged", "b.ged"] {
            try "0 HEAD\n0 TRLR".write(to: source.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let archive = try temporaryDirectory().appendingPathComponent("Двойной.gdz")
        try GEDZIPArchive.write(contentsOf: source, to: archive)

        do {
            _ = try store.stageImport(from: archive)
            Issue.record("An archive without gedcom.ged and two candidates must be refused")
        } catch let error as TreeStoreError {
            guard case let .invalidGEDZIP(name) = error else { throw error }
            #expect(name == "Двойной.gdz")
            #expect(error.errorDescription?.contains("Unpacked") == false)
        }
        #expect(pendingEntries(in: root).isEmpty)
    }

    /// E350-04: a sidecar already sitting under the archive's name belongs to someone
    /// else. The export takes the next free *pair* and leaves it alone.
    @MainActor
    @Test func anOrphanSidecarIsNeverAdopted() async throws {
        let (store, tree, root) = try storeWithTree()
        _ = try await store.addTreeVerified(tree)
        let destination = root.appendingPathComponent("out", isDirectory: true)
        let orphan = destination.appendingPathComponent("Род Ивановых.swarm-manifest", isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        try Data("stale".utf8).write(to: orphan.appendingPathComponent("orphan-marker.txt"))

        let receipt = try await store.exportTree(tree, to: destination)
        #expect(receipt.finalURL.lastPathComponent == "Род Ивановых 2.gdz")
        let sidecar = destination.appendingPathComponent("Род Ивановых 2.swarm-manifest", isDirectory: true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: sidecar.path) == ["manifest.json"])
        #expect(try FileManager.default.contentsOfDirectory(atPath: orphan.path) == ["orphan-marker.txt"])
    }

    /// E350-08: a failure after the archive is written must not leave a final-named
    /// `.gdz` (or sidecar) that looks like a finished export.
    @MainActor
    @Test(arguments: [PersistenceFaultPoint.gedzipReadback, .gedzipFinalize])
    func aFailedPackagingLeavesNothingBehind(_ point: PersistenceFaultPoint) async throws {
        let (store, tree, root) = try storeWithTree()
        _ = try await store.addTreeVerified(tree)
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        store.faultInjector = { if $0 == point { throw CocoaError(.fileWriteUnknown) } }

        await #expect(throws: (any Error).self) { try await store.exportTree(tree, to: destination) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    /// The folder bundle must keep behaving exactly as it did before GEDZIP existed.
    @MainActor
    @Test func folderPackagingStillProducesABundleNotAnArchive() async throws {
        let (store, tree, root) = try storeWithTree()
        _ = try await store.addTreeVerified(tree)
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let receipt = try await store.exportTree(tree, to: destination, packaging: .folder)
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: receipt.finalURL.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
        #expect(receipt.finalURL.pathExtension != "gdz")
        let inside = try FileManager.default.contentsOfDirectory(
            at: receipt.finalURL,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent)
        // A bundle names its GEDCOM after itself; only an archive uses gedcom.ged.
        #expect(inside.contains("\(receipt.finalURL.lastPathComponent).ged"))
        #expect(!inside.contains(GEDZIPArchive.gedcomEntryName))
    }

    /// Packaging must not open a hole in the privacy export: the archive carries no
    /// living person's details, and the sidecar carries no verbatim pre-redaction file.
    @MainActor
    @Test func aPrivacyArchiveLeaksNothingAndKeepsNoOriginalImport() async throws {
        let (store, tree, root) = try storeWithTree()
        let living = try #require(tree.people.first { $0.isLiving })
        living.birthDate = "20.06.1930"
        living.birthPlace = "Секретный город"
        living.notes = "Секретная заметка"
        _ = try await store.addTreeVerified(tree)
        let destination = root.appendingPathComponent("out", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let receipt = try await store.exportTree(tree, to: destination, hidingLivingPeople: true)
        let unpacked = try temporaryDirectory()
        try GEDZIPArchive.extract(receipt.finalURL, to: unpacked)
        let text = try String(
            contentsOf: unpacked.appendingPathComponent(GEDZIPArchive.gedcomEntryName),
            encoding: .utf8
        )
        for secret in ["Секретный город", "Секретная заметка", "20.06.1930", "1930"] {
            #expect(!text.contains(secret), "leaked \(secret)")
        }
        // The deceased are still there, so the export is worth having.
        #expect(text.contains("Иван"))

        let sidecar = destination.appendingPathComponent(
            "\(receipt.finalURL.deletingPathExtension().lastPathComponent).swarm-manifest",
            isDirectory: true
        )
        let carried = (try? FileManager.default.contentsOfDirectory(at: sidecar, includingPropertiesForKeys: nil))?
            .map(\.lastPathComponent) ?? []
        #expect(!carried.contains { $0.contains("original-import") })
    }

    @Test func recognizesArchivesByExtension() {
        #expect(GEDZIPArchive.isArchive(URL(fileURLWithPath: "/tmp/Род.gdz")))
        #expect(GEDZIPArchive.isArchive(URL(fileURLWithPath: "/tmp/Род.GDZ")))
        #expect(!GEDZIPArchive.isArchive(URL(fileURLWithPath: "/tmp/Род.ged")))
        #expect(!GEDZIPArchive.isArchive(URL(fileURLWithPath: "/tmp/Род")))
    }
}
