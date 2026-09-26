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
    func recoverInterruptedCommits() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: storageFolderURL, includingPropertiesForKeys: nil) else { return }
        let rollbacks = entries.filter { $0.lastPathComponent.hasPrefix(".rollback-") }
        guard !rollbacks.isEmpty else { return }
        let liveIDs = Set(entries
            .filter { !$0.lastPathComponent.hasPrefix(".") }
            .compactMap { gedFile(in: $0).flatMap(Self.declaredTreeID) })
        for rollback in rollbacks {
            guard let ged = gedFile(in: rollback) else { continue }
            if let id = Self.declaredTreeID(in: ged), liveIDs.contains(id) { continue }
            let name = FileNaming.sanitizedFileName(ged.deletingPathExtension().lastPathComponent)
            do {
                try fm.moveItem(at: rollback, to: uniqueFolderURL(named: name, excluding: nil))
            } catch {
                log.error("Could not restore \(rollback.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
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
    /// Sub-folders are still walked whole — the media and attachment folders the filter
    /// is used on are flat.
    func copyDirectoryContents(
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
                try copyDirectoryContents(from: item, to: target)
            } else {
                if let keepingOnly, !keepingOnly.contains(item.lastPathComponent) { continue }
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    /// Read in 16 MB pieces: a video attachment read whole doubled the app's memory
    /// for the length of a save, while a photo still takes a single read.
    func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 16 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Manifest

    struct BundleManifest: Codable {
        let generationID: UUID
        let createdAt: Date
        let hashes: [String: String]
    }

    func writeManifest(generationID: UUID, hashes: [String: String], in folder: URL) throws {
        let metadata = folder.appendingPathComponent(Self.metadataName, isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let manifest = BundleManifest(generationID: generationID, createdAt: Date(), hashes: hashes)
        let data = try JSONEncoder.pretty.encode(manifest)
        try data.write(to: metadata.appendingPathComponent(Self.manifestName), options: .atomic)
    }

    /// SHA-256 of every file in `folder`, keyed by relative path.
    ///
    /// `committed` is the folder `folder` was cloned from. A file there with the same
    /// size and modification date at the same path is the same file — a clone keeps
    /// both, and any write changes the date — so its hash comes from the committed
    /// manifest instead of reading the bytes again.
    func hashes(in folder: URL, includeRecoveryData: Bool, reusingFrom committed: URL? = nil) throws -> [String: String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { throw TreeStoreError.treeFolderMissing }

        let known = committed.map(committedHashes) ?? [:]
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
            if let digest = known[relative], let committed,
               Self.isUnchanged(file, since: committed.appendingPathComponent(relative)) {
                result[relative] = digest
            } else {
                result[relative] = try sha256(file)
            }
        }
        return result
    }

    func verify(hashes expected: [String: String], in folder: URL, reusingFrom committed: URL? = nil) throws {
        let actual = try hashes(in: folder, includeRecoveryData: false, reusingFrom: committed)
        for (path, digest) in expected where actual[path] != digest {
            throw TreeStoreError.verificationFailed(path: path)
        }
        guard Set(actual.keys) == Set(expected.keys) else {
            let path = Set(actual.keys).symmetricDifference(Set(expected.keys)).sorted().first ?? folder.path
            throw TreeStoreError.verificationFailed(path: path)
        }
    }

    /// The committed manifest's hashes; empty when there is none to trust (a bundle
    /// from before manifests, or one that fails to decode), which just means hashing.
    private func committedHashes(in folder: URL) -> [String: String] {
        let url = folder
            .appendingPathComponent(Self.metadataName, isDirectory: true)
            .appendingPathComponent(Self.manifestName)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(BundleManifest.self, from: Data(contentsOf: url)))?.hashes ?? [:]
    }

    private static func isUnchanged(_ file: URL, since committed: URL) -> Bool {
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
