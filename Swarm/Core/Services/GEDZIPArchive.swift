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
        // Watching the folder grow stops `ditto` only at the next look, by which time a
        // fast expansion has already written far past the budget. The size the archive
        // declares is refused before anything is written; the watch stays for an
        // archive whose directory understates it.
        if let declared = declaredExpandedSize(of: archive), declared > limit {
            throw Failure.extractFailed("declares \(declared) bytes, past \(limit)")
        }
        try run(["-x", "-k", archive.path, directory.path], failure: Failure.extractFailed, limit: (directory, limit))
        let entries = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey])
        while let entry = entries?.nextObject() as? URL {
            if (try? entry.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                throw Failure.extractFailed("symbolic link: \(entry.lastPathComponent)")
            }
        }
    }

    /// The total uncompressed size the ZIP central directory declares, ZIP64 included;
    /// nil when there is no directory to read, which `ditto` then reports as damage.
    static func declaredExpandedSize(of archive: URL) -> UInt64? {
        guard let handle = try? FileHandle(forReadingFrom: archive) else { return nil }
        defer { try? handle.close() }
        func read(_ offset: UInt64, _ count: UInt64) -> [UInt8]? {
            guard (try? handle.seek(toOffset: offset)) != nil,
                  let data = try? handle.read(upToCount: Int(count)), data.count == count else { return nil }
            return [UInt8](data)
        }
        func number(_ bytes: [UInt8], _ at: Int, _ width: Int) -> UInt64 {
            (0 ..< width).reduce(0) { $0 | UInt64(bytes[at + $1]) << (8 * $1) }
        }
        // The end record sits in the last 22 bytes plus a comment of up to 64 KiB.
        guard let end = try? handle.seekToEnd(), end >= 22 else { return nil }
        let tailLength = min(end, 22 + 0xFFFF)
        guard let tail = read(end - tailLength, tailLength),
              let eocd = stride(from: tail.count - 22, through: 0, by: -1)
              .first(where: { number(tail, $0, 4) == 0x0605_4B50 }) else { return nil }
        var directorySize = number(tail, eocd + 12, 4)
        var directoryOffset = number(tail, eocd + 16, 4)
        if directorySize == 0xFFFF_FFFF || directoryOffset == 0xFFFF_FFFF {
            guard eocd >= 20, number(tail, eocd - 20, 4) == 0x0706_4B50,
                  let zip64 = read(number(tail, eocd - 20 + 8, 8), 56),
                  number(zip64, 0, 4) == 0x0606_4B50 else { return nil }
            directorySize = number(zip64, 40, 8)
            directoryOffset = number(zip64, 48, 8)
        }
        guard directoryOffset <= end, directorySize <= end - directoryOffset,
              let directory = read(directoryOffset, directorySize) else { return nil }
        var total: UInt64 = 0
        var at = 0
        while at + 46 <= directory.count, number(directory, at, 4) == 0x0201_4B50 {
            var size = number(directory, at + 24, 4)
            let nameLength = Int(number(directory, at + 28, 2))
            let extraLength = Int(number(directory, at + 30, 2))
            let commentLength = Int(number(directory, at + 32, 2))
            var extra = at + 46 + nameLength
            let extraEnd = min(extra + extraLength, directory.count)
            // A ZIP64 entry keeps its real size in extra field 1, uncompressed size first.
            while size == 0xFFFF_FFFF, extra + 4 <= extraEnd {
                let fieldLength = Int(number(directory, extra + 2, 2))
                if number(directory, extra, 2) == 1, extra + 12 <= extraEnd { size = number(directory, extra + 4, 8) }
                extra += 4 + fieldLength
            }
            total = total.addingReportingOverflow(size).overflow ? .max : total + size
            at += 46 + nameLength + extraLength + commentLength
        }
        return total
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
