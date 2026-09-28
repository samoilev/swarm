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
    ///
    /// `ditto` has no size limit either, and a small archive can expand to fill the disk,
    /// so the unpacked folder is held to `budget` bytes — by default 50 times the archive,
    /// at least 1 GiB, and never more than half the volume's free space.
    public static func extract(_ archive: URL, to directory: URL, budget: Int64? = nil) throws {
        let size = Int64((try? archive.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        let free = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?
            .volumeAvailableCapacityForImportantUsage ?? .max
        let limit = budget ?? min(max(size * 50, 1 << 30), free / 2)
        try run(["-x", "-k", archive.path, directory.path], failure: Failure.extractFailed, limit: (directory, limit))
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

    /// `limit` stops the process once `folder` holds more than `bytes`, checked every
    /// 0.2 s while it runs and once more after it exits.
    private static func run(
        _ arguments: [String],
        failure: (String) -> Failure,
        limit: (folder: URL, bytes: Int64)? = nil
    ) throws {
        let fm = FileManager.default
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        // A file, not a pipe: nothing has to drain it while this thread watches the size.
        let errors = fm.temporaryDirectory.appendingPathComponent("ditto-\(UUID().uuidString).log")
        fm.createFile(atPath: errors.path, contents: nil)
        let errorHandle = try FileHandle(forWritingTo: errors)
        defer {
            try? errorHandle.close()
            try? fm.removeItem(at: errors)
        }
        process.standardError = errorHandle
        process.standardOutput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw failure(error.localizedDescription)
        }
        func overLimit() -> Bool {
            guard let limit else { return false }
            var total: Int64 = 0
            let walker = fm.enumerator(at: limit.folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
            while let url = walker?.nextObject() as? URL {
                total += Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
                if total > limit.bytes { return true }
            }
            return false
        }
        while exited.wait(timeout: .now() + 0.2) == .timedOut {
            if overLimit() { process.terminate() }
        }
        process.waitUntilExit()
        if overLimit() { throw failure("expanded past \(limit?.bytes ?? 0) bytes") }
        guard process.terminationStatus == 0 else {
            throw failure((try? String(contentsOf: errors, encoding: .utf8)) ?? "")
        }
    }
}
