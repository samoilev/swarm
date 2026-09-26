import Foundation

/// Reads and writes GEDZIP (`.gdz`) archives — the GEDCOM 7.0 packaging format: a ZIP
/// carrying `gedcom.ged` at its root beside the media its `FILE` payloads name, so a
/// tree travels as one file instead of a folder someone has to keep intact.
///
/// ponytail: shells out to `ditto` rather than taking a ZIP dependency. The app has no
/// third-party packages and no sandbox entitlements, so a subprocess is free and two
/// calls are not worth a supply chain. Sandboxing the app is what would break this —
/// at that point this type needs a real ZIP library behind the same two functions.
/// How an export leaves the app: one portable file, or the folder bundle.
public enum TreeExportPackaging: String, CaseIterable, Sendable, Identifiable {
    /// A single `.gdz`. The default — it is what lets a tree be emailed intact.
    case gedzip
    /// A folder holding the GEDCOM beside `Media/` and `Attachments/`.
    case folder

    public var id: String { rawValue }
}

public enum GEDZIPArchive {
    /// The one filename the GEDZIP spec reserves at an archive's root.
    public static let gedcomEntryName = "gedcom.ged"

    public enum Failure: LocalizedError, Equatable {
        case archiveFailed(String)
        case extractFailed(String)

        public var errorDescription: String? {
            switch self {
            case .archiveFailed:
                L10n.tr("Не удалось упаковать архив GEDZIP.")
            case .extractFailed:
                L10n.tr("Не удалось распаковать архив GEDZIP. Возможно, файл повреждён.")
            }
        }
    }

    /// Archive a directory's *contents* — not the directory itself — so `gedcom.ged`
    /// lands at the archive root where the spec requires it.
    ///
    /// `--norsrc --noextattr` keep macOS resource forks and extended attributes out,
    /// which is what stops a `__MACOSX/` folder appearing for readers on other systems.
    public static func write(contentsOf directory: URL, to destination: URL) throws {
        try run(
            ["-c", "-k", "--norsrc", "--noextattr", directory.path, destination.path],
            failure: Failure.archiveFailed
        )
    }

    /// `ditto` confines `..` entries to `directory` but recreates symbolic links as they
    /// were stored, so an archive could plant `Media/photo.jpg -> /any/file`. No tree
    /// needs one, and an archive carrying one is refused here instead of failing later
    /// as an unexplained checksum mismatch.
    public static func extract(_ archive: URL, to directory: URL) throws {
        try run(["-x", "-k", archive.path, directory.path], failure: Failure.extractFailed)
        let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let entry = entries?.nextObject() as? URL {
            if (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                throw Failure.extractFailed("symbolic link: \(entry.lastPathComponent)")
            }
        }
    }

    /// Whether a URL names a GEDZIP by extension. Content is not sniffed: the picker and
    /// the importer both decide on the name, and a mislabelled file fails later with a
    /// message about the archive rather than silently reading as something else.
    public static func isArchive(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "gdz"
    }

    /// Move staged files that must not travel inside the archive — Swarm's own
    /// bookkeeping, like the verbatim `original-import.ged` — into the sidecar beside
    /// it, so the archive stays something any GEDZIP reader accepts.
    ///
    /// Called before the caller hashes the staging folder, so the manifest ends up
    /// describing the archive's contents and nothing else.
    public static func moveAside(_ extras: [URL], to sidecar: URL) throws {
        let fm = FileManager.default
        let present = extras.filter { fm.fileExists(atPath: $0.path) }
        guard !present.isEmpty else { return }
        try fm.createDirectory(at: sidecar, withIntermediateDirectories: true)
        for extra in present {
            try fm.moveItem(at: extra, to: sidecar.appendingPathComponent(extra.lastPathComponent))
        }
    }

    private static func run(_ arguments: [String], failure: (String) -> Failure) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        do {
            try process.run()
        } catch {
            throw failure(error.localizedDescription)
        }
        // Read before waiting: a full pipe buffer would deadlock a chatty failure.
        let stderrData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw failure(String(decoding: stderrData, as: UTF8.self))
        }
    }
}
