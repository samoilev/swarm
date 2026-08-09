import Foundation
@testable import SwarmCore
import Testing

/// A verified archive is only worth exporting if it comes back whole. These cover the
/// export → import round trip and the permission failures that used to be reported as a
/// damaged file.
@Suite(.serialized)
struct ArchiveRoundTripTests {
    private final class Temp {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-archive-tests-\(UUID().uuidString)", isDirectory: true)
        init() throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    private let portrait = Data("portrait-bytes".utf8)
    private let record = Data("birth certificate".utf8)

    /// Build a saved tree carrying both a portrait and an attachment, then export it.
    private func exportedArchive(in temp: Temp, exports: Temp) async throws -> URL {
        let sourceFolder = try Temp()
        let attachmentSource = sourceFolder.url.appendingPathComponent("certificate.txt")
        try record.write(to: attachmentSource)

        let store = TreeStore(storageFolder: temp.url)
        let tree = FamilyTree(name: "Архив")
        let person = Person(givenNames: "Анна", surname: "Иванова")
        tree.people = [person]
        _ = try await store.addTreeVerified(tree)

        let attachment = try store.prepareAttachment(in: tree, sourceURL: attachmentSource)
        person.photoData = portrait
        person.attachments = [attachment]
        _ = try await store.saveTree(tree)

        return try await store.exportTree(tree, to: exports.url).finalURL
    }

    @Test func exportedArchiveReimportsWithPhotosAndAttachments() async throws {
        let exports = try Temp()
        let library = try Temp()
        let bundle = try await exportedArchive(in: library, exports: exports)

        // A second library, as if the archive had been handed to another machine.
        let destination = try Temp()
        let store = TreeStore(storageFolder: destination.url)
        let source = try store.resolveImportSource(bundle)
        let staged = try store.prepareImportPreview(from: source)
        #expect(store.stagedImportDiagnostics(for: staged).isEmpty)

        let result: ImportResult = try await store.importGEDCOM(from: staged)
        let imported = result.tree
        store.refreshMediaFolders(for: imported)
        let person = try #require(imported.people.first)

        #expect(person.photoData == portrait)
        let attachment = try #require(person.attachments.first)
        #expect(attachment.originalName == "certificate.txt")
        #expect(try Data(contentsOf: store.attachmentURL(attachment, in: imported)) == record)
    }

    @Test func selectingArchiveFolderResolvesToItsGEDCOM() async throws {
        let exports = try Temp()
        let library = try Temp()
        let bundle = try await exportedArchive(in: library, exports: exports)
        let destination = try Temp()
        let store = TreeStore(storageFolder: destination.url)

        let resolved = try store.resolveImportSource(bundle)
        #expect(resolved.pathExtension == "ged")
        #expect(resolved.deletingLastPathComponent().standardizedFileURL == bundle.standardizedFileURL)
        // A plain file selection is passed through untouched.
        #expect(try store.resolveImportSource(resolved) == resolved)
    }

    @Test func folderWithoutUsableGEDCOMIsReportedPlainly() throws {
        let fm = FileManager.default
        let temp = try Temp()
        let destination = try Temp()
        let store = TreeStore(storageFolder: destination.url)

        let empty = temp.url.appendingPathComponent("Пусто", isDirectory: true)
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        // The safety-net copy of an import is not the folder's own tree.
        try "0 HEAD\n0 TRLR".write(
            to: empty.appendingPathComponent("original-import.ged"), atomically: true, encoding: .utf8
        )
        #expect(throws: TreeStoreError.self) { try store.resolveImportSource(empty) }

        let ambiguous = temp.url.appendingPathComponent("Двое", isDirectory: true)
        try fm.createDirectory(at: ambiguous, withIntermediateDirectories: true)
        for name in ["one.ged", "two.ged"] {
            try "0 HEAD\n0 TRLR".write(
                to: ambiguous.appendingPathComponent(name), atomically: true, encoding: .utf8
            )
        }
        #expect(throws: TreeStoreError.self) { try store.resolveImportSource(ambiguous) }
    }

    /// Repeated ids made every finding after the first disappear from the import preview,
    /// leaving the reader scrolling past blank space where the warnings should have been.
    @Test func repeatedFindingsEachGetTheirOwnDiagnosticIdentity() throws {
        let temp = try Temp()
        let bundle = temp.url.appendingPathComponent("Пропавшие файлы", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        let gedcom = bundle.appendingPathComponent("Пропавшие файлы.ged")
        try """
        0 HEAD
        1 _NAME Пропавшие файлы
        0 @I1@ INDI
        1 NAME Анна /Иванова/
        1 OBJE
        2 FILE Attachments/first.pdf
        1 OBJE
        2 FILE Attachments/second.pdf
        1 OBJE
        2 FILE Attachments/third.pdf
        0 @I2@ INDI
        1 NAME Пётр /Иванов/
        1 FAMC @F9@
        0 TRLR
        """.write(to: gedcom, atomically: true, encoding: .utf8)

        let report = try GEDCOMCodec.parse(gedcom).report
        let ids = report.diagnostics.map(\.id)
        #expect(ids.count == Set(ids).count)
        #expect(report.diagnostics.filter { $0.id.hasPrefix("gedcom.missing-media") }.count == 3)
        #expect(report.diagnostics.contains { $0.id == "gedcom.unresolved-pointer.F9" })
    }

    /// The bug this file was written for: an unreadable `Media/` used to abort the whole
    /// import and surface as “the file is damaged”.
    @Test func unreadableMediaFolderWarnsInsteadOfFailingTheImport() async throws {
        // Root ignores the permission bits this test relies on.
        try #require(getuid() != 0)
        let fm = FileManager.default
        let archives = try Temp()
        let bundle = archives.url.appendingPathComponent("Закрытая папка", isDirectory: true)
        let media = bundle.appendingPathComponent("Media", isDirectory: true)
        try fm.createDirectory(at: media, withIntermediateDirectories: true)
        try portrait.write(to: media.appendingPathComponent("portrait.jpg"))
        try "0 HEAD\n1 _NAME Закрытая папка\n0 @I1@ INDI\n1 NAME Анна /Иванова/\n0 TRLR"
            .write(to: bundle.appendingPathComponent("Закрытая папка.ged"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: media.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: media.path) }

        let destination = try Temp()
        let store = TreeStore(storageFolder: destination.url)
        let source = try store.resolveImportSource(bundle)
        let staged = try store.prepareImportPreview(from: source)

        let warnings = store.stagedImportDiagnostics(for: staged)
        #expect(warnings.count == 1)
        #expect(warnings.first?.id == "import.sibling-unreadable.Media")
        #expect(warnings.first?.severity == .warning)

        // The tree still lands, and carries the warning in its permanent report.
        let result: ImportResult = try await store.importGEDCOM(from: staged)
        #expect(result.tree.people.count == 1)
        #expect(result.report.diagnostics.contains { $0.id == "import.sibling-unreadable.Media" })
        #expect(store.trees.count == 1)
    }
}
