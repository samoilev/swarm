import CryptoKit
import Foundation
import os

private let log = Logger(subsystem: "com.samoilev.swarm", category: "TreeStore")

/// File-level helpers for tree bundles on disk, kept out of `TreeStore.swift`: locating
/// a tree's GEDCOM, naming its folder, copying and hashing, and putting back a folder an
/// interrupted save left hidden.
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

    func sha256(_ url: URL) throws -> String {
        let digest = try SHA256.hash(data: Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
