import CryptoKit
import Foundation
import os

private let log = Logger(subsystem: "com.samoilev.swarm", category: "TreeStore")

/// File-level helpers for tree bundles on disk, kept out of `TreeStore.swift`: locating
/// a tree's GEDCOM, naming its folder, copying, hashing and manifests, and putting back
/// a folder an interrupted save left hidden.
extension TreeStore {
    /// A save swaps folders with two renames: the committed folder to `.rollback-<id>`,
    /// then the staged one into place. A crash between them left no visible folder, and
    /// since `load()` skips hidden folders the tree vanished from the library. The
    /// committed folder goes back whenever no visible folder holds the same tree. A
    /// rollback whose tree is still present is debris of a cleanup that failed, and a
    /// recovery copy is never deleted here, so it is left alone.
    ///
    /// Returns the rollbacks it could neither read nor put back. Each may hold the only
    /// copy of a tree, and skipping one quietly looked exactly like a tree that was lost.
    func recoverInterruptedCommits() -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: storageFolderURL, includingPropertiesForKeys: nil) else { return [] }
        let rollbacks = entries.filter { $0.lastPathComponent.hasPrefix(".rollback-") }
        guard !rollbacks.isEmpty else { return [] }
        let liveIDs = Set(entries
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { gedFile(in: $0).flatMap(Self.declaredTreeID) })
        var unrecovered: [String] = []
        for rollback in rollbacks {
            guard (try? fm.contentsOfDirectory(at: rollback, includingPropertiesForKeys: nil)) != nil else {
                unrecovered.append(rollback.lastPathComponent)
                continue
            }
            guard let ged = gedFile(in: rollback) else { continue }
            if let id = Self.declaredTreeID(in: ged), liveIDs.contains(id) { continue }
            let name = FileNaming.sanitizedFileName(ged.deletingPathExtension().lastPathComponent)
            do {
                try fm.moveItem(at: rollback, to: uniqueFolderURL(named: name, excluding: nil))
            } catch {
                log.error("Could not restore \(rollback.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                unrecovered.append(rollback.lastPathComponent)
            }
        }
        return unrecovered
    }

    /// Import previews and attachments waiting for a save are staged in `.Pending` and
    /// removed once committed or discarded. After a crash nothing removed them, so the
    /// folder only grew; each launch now clears whatever has sat there for a week.
    func discardStalePendingItems(addedBefore cutoff: Date = Date().addingTimeInterval(-7 * 24 * 60 * 60)) {
        let fm = FileManager.default
        let pending = storageFolderURL.appendingPathComponent(Self.pendingName, isDirectory: true)
        guard let items = try? fm.contentsOfDirectory(at: pending, includingPropertiesForKeys: [.addedToDirectoryDateKey]) else { return }
        for item in items {
            // When it arrived here, not its own dates: a copied attachment keeps the
            // modification date of a file that may be years old.
            guard let added = try? item.resourceValues(forKeys: [.addedToDirectoryDateKey]).addedToDirectoryDate,
                  added < cutoff else { continue }
            try? fm.removeItem(at: item)
        }
        cleanupPendingFolderIfEmpty()
    }

    /// The `_TREEID` a GEDCOM declares, read from the text alone: recovery only needs the
    /// identity, and `load()` parses every tree fully right after.
    private static func declaredTreeID(in ged: URL) -> String? {
        guard let text = try? String(contentsOf: ged, encoding: .utf8) else { return nil }
        let marker = "1 _TREEID "
        for line in text.split(whereSeparator: \.isNewline) where line.hasPrefix(marker) {
            return line.dropFirst(marker.count).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// The canonical .ged path inside a tree folder: "<folder name>.ged".
    func gedURL(in folder: URL) -> URL {
        folder.appendingPathComponent("\(folder.lastPathComponent).ged")
    }

    /// The first .ged file inside a folder, if any (its name may differ pre-migration).
    /// The preserved `original-import.ged` is never the tree's working file.
    func gedFile(in folder: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        return files.first { $0.pathExtension.lowercased() == "ged" && $0.lastPathComponent != Self.originalImportName }
    }

    /// A storage-folder URL named `base`, suffixed " 2", " 3", … to avoid colliding
    /// with any folder other than `excluding` (the tree's own current folder).
    func uniqueFolderURL(named base: String, excluding current: URL?) -> URL {
        let fm = FileManager.default
        func isFree(_ url: URL) -> Bool {
            if let c = current, url.standardizedFileURL == c.standardizedFileURL { return true }
            // `load()` skips these folders, so a tree saved under one vanished from the
            // library. Case-insensitive: APFS usually is.
            let name = url.lastPathComponent
            if [Self.archivedName, Self.recoveryName].contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
                return false
            }
            return !fm.fileExists(atPath: url.path)
        }
        let first = storageFolderURL.appendingPathComponent(base, isDirectory: true)
        if isFree(first) { return first }
        var i = 2
        while true {
            let candidate = storageFolderURL.appendingPathComponent("\(base) \(i)", isDirectory: true)
            if isFree(candidate) { return candidate }
            i += 1
        }
    }

    /// `keepingOnly` filters the files copied at this level by name; nil copies them all.
    /// A filtered copy skips sub-folders: a tree names flat files only, so anything
    /// nested — an imported `Media/.private/`, say — is exactly what a privacy export
    /// must leave behind.
    nonisolated func copyDirectoryContents(
        from source: URL,
        to destination: URL,
        keepingOnly: Set<String>? = nil
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let isDirectory = try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            if isDirectory {
                if keepingOnly != nil { continue }
                try copyDirectoryContents(from: item, to: target)
            } else {
                if let keepingOnly, !keepingOnly.contains(item.lastPathComponent) { continue }
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    /// Keeps the newest 50 revisions and 30 days of trash. A trashed file's age is
    /// read from the deletion stamp its name starts with: its own modification date
    /// is the original file's, so an old photo would otherwise be pruned by the very
    /// save that deleted it.
    func pruneRecoveryData(in staging: URL) throws {
        try inject(.historyPrune)
        let fm = FileManager.default
        let metadata = staging.appendingPathComponent(Self.metadataName, isDirectory: true)
        let history = metadata.appendingPathComponent(Self.historyName, isDirectory: true)
        if fm.fileExists(atPath: history.path) {
            let revisions = try fm.contentsOfDirectory(at: history, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension.lowercased() == "ged" }
                .sorted { $0.lastPathComponent > $1.lastPathComponent }
            for old in revisions.dropFirst(50) { try fm.removeItem(at: old) }
        }

        let trash = metadata.appendingPathComponent(Self.trashName, isDirectory: true)
        if fm.fileExists(atPath: trash.path) {
            let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
            let files = try fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: [.contentModificationDateKey])
            for file in files {
                let deleted = Self.timestampFormatter.date(from: String(file.lastPathComponent.prefix(19)))
                let date = try deleted ?? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantFuture
                if date < cutoff { try fm.removeItem(at: file) }
            }
        }
    }

    /// Read in 16 MB pieces: a video attachment read whole doubled the app's memory
    /// for the length of a save, while a photo still takes a single read. Each piece
    /// is released before the next: the reads are autoreleased, and on a detached
    /// task nothing drained them until the whole file had been held at once anyway.
    nonisolated func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while try autoreleasepool(invoking: {
            guard let chunk = try handle.read(upToCount: 16 << 20), !chunk.isEmpty else { return false }
            hasher.update(data: chunk)
            return true
        }) {}
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Manifest

    struct BundleManifest: Codable, Sendable {
        let generationID: UUID
        let createdAt: Date
        let hashes: [String: String]
        /// Each file as it stood when the manifest was written. Absent from manifests
        /// written before stamps existed, which only means hashing those files again.
        var stamps: [String: FileStamp]? = nil
    }

    /// Size and both change dates of a file. The status-change date moves on every
    /// write and cannot be set back, so a file rewritten with its old modification
    /// date still reads as changed.
    struct FileStamp: Codable, Equatable, Sendable {
        let size: Int
        let modified: Double
        let changed: Double

        init?(_ url: URL) {
            let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .attributeModificationDateKey]
            guard let values = try? url.resourceValues(forKeys: keys), let size = values.fileSize,
                  let modified = values.contentModificationDate, let changed = values.attributeModificationDate else { return nil }
            self.size = size
            self.modified = modified.timeIntervalSinceReferenceDate
            self.changed = changed.timeIntervalSinceReferenceDate
        }
    }

    nonisolated func writeManifest(generationID: UUID, hashes: [String: String], in folder: URL) throws {
        let metadata = folder.appendingPathComponent(Self.metadataName, isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let stamps = hashes.keys.reduce(into: [String: FileStamp]()) { stamps, path in
            stamps[path] = FileStamp(folder.appendingPathComponent(path))
        }
        let manifest = BundleManifest(generationID: generationID, createdAt: Date(), hashes: hashes, stamps: stamps)
        let data = try JSONEncoder.pretty.encode(manifest)
        try data.write(to: metadata.appendingPathComponent(Self.manifestName), options: .atomic)
    }

    /// SHA-256 of every file in `folder`, keyed by relative path.
    ///
    /// `committed` is the folder `folder` was cloned from. Its manifest's hash is reused
    /// only for a file that is still exactly as that manifest stamped it, and whose copy
    /// here has the same size and modification date — a clone keeps both, and any write
    /// changes the date. Matching the copy alone missed an edit made to the committed
    /// file itself, and the manifest went on certifying bytes no longer there.
    nonisolated func hashes(in folder: URL, includeRecoveryData: Bool, reusingFrom committed: URL? = nil) throws -> [String: String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { throw TreeStoreError.treeFolderMissing }

        let known = committed.flatMap(committedManifest)
        var result: [String: String] = [:]
        let basePath = folder.resolvingSymlinksInPath().path
        for case let file as URL in enumerator {
            guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { continue }
            let filePath = file.resolvingSymlinksInPath().path
            guard filePath.hasPrefix(basePath + "/") else {
                throw TreeStoreError.verificationFailed(path: file.lastPathComponent)
            }
            let relative = String(filePath.dropFirst(basePath.count + 1))
            if relative == "\(Self.metadataName)/\(Self.manifestName)" { continue }
            if !includeRecoveryData,
               relative.hasPrefix("\(Self.metadataName)/\(Self.historyName)/") ||
               relative.hasPrefix("\(Self.metadataName)/\(Self.trashName)/") { continue }
            if let digest = known?.hashes[relative], let stamp = known?.stamps?[relative], let committed,
               FileStamp(committed.appendingPathComponent(relative)) == stamp,
               Self.isUnchanged(file, since: committed.appendingPathComponent(relative)) {
                result[relative] = digest
            } else {
                result[relative] = try sha256(file)
            }
        }
        return result
    }

    nonisolated func verify(hashes expected: [String: String], in folder: URL, reusingFrom committed: URL? = nil) throws {
        let actual = try hashes(in: folder, includeRecoveryData: false, reusingFrom: committed)
        for (path, digest) in expected where actual[path] != digest {
            throw TreeStoreError.verificationFailed(path: path)
        }
        guard Set(actual.keys) == Set(expected.keys) else {
            let path = Set(actual.keys).symmetricDifference(Set(expected.keys)).sorted().first ?? folder.path
            throw TreeStoreError.verificationFailed(path: path)
        }
    }

    /// The committed manifest; nil when there is none to trust (a bundle from before
    /// manifests, or one that fails to decode), which just means hashing.
    private nonisolated func committedManifest(in folder: URL) -> BundleManifest? {
        let url = folder
            .appendingPathComponent(Self.metadataName, isDirectory: true)
            .appendingPathComponent(Self.manifestName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(BundleManifest.self, from: Data(contentsOf: url))
    }

    private nonisolated static func isUnchanged(_ file: URL, since committed: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        guard let now = try? file.resourceValues(forKeys: keys),
              let then = try? committed.resourceValues(forKeys: keys),
              let size = now.fileSize, let date = now.contentModificationDate else { return false }
        return size == then.fileSize && date == then.contentModificationDate
    }
}

extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
