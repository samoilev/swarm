import Foundation
import os

private let log = Logger(subsystem: "com.familytreestudio.app", category: "TreeStore")

/// GEDCOM-based persistence for family trees. Everything is stored strictly
/// locally in ~/Library/Application Support/FamilyTreeStudio/.
///
/// Each tree owns a folder named after the tree (readable & made unique). The tree's
/// stable identity lives inside the GEDCOM (`_TREEID`), so the folder/file can be
/// renamed freely when the tree is renamed:
///   <Tree Name>/
///     ├── <Tree Name>.ged — the tree itself (identity stored as _TREEID)
///     ├── Media/          — person portrait photos (referenced by GEDCOM OBJE)
///     └── Attachments/    — arbitrary files attached to people (GEDCOM _ATTC)
///
/// `Archived/` holds tree folders the user removed but chose to keep.
@Observable
public final class TreeStore {
    public var trees: [FamilyTree] = []

    /// Set when a save/export write fails, so views can surface it (a silent write
    /// failure in a data-authoring app is undetectable data loss). Cleared by the
    /// view once shown.
    public var lastSaveError: String?

    /// Set when one or more trees on disk could not be parsed during `load()`. A tree
    /// that silently fails to load is indistinguishable from deleted data, so the
    /// library surfaces this to the user. Cleared by the view once shown.
    public var lastLoadError: String?

    private let storageFolder: URL

    /// The root storage directory (for "Reveal in Finder" when a load fails).
    public var storageFolderURL: URL { storageFolder }

    /// Maps tree UUID → its folder URL.
    private var folderMap: [UUID: URL] = [:]

    private static let gedName = "tree.ged"
    private static let mediaName = "Media"
    private static let attachmentsName = "Attachments"
    private static let archivedName = "Archived"
    /// Verbatim copy of an imported file, kept as a safety net and never treated as
    /// the tree's own working .ged (excluded from load/save/reconcile).
    private static let originalImportName = "original-import.ged"

    /// Default init: stores trees in ~/Library/Application Support/FamilyTreeStudio/.
    /// Tests pass an explicit `storageFolder` (a temp dir) to exercise the migration
    /// and folder-reconcile logic without touching the user's real library.
    public init(storageFolder: URL? = nil) {
        let appFolder: URL
        if let storageFolder {
            appFolder = storageFolder
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            appFolder = appSupport.appendingPathComponent("FamilyTreeStudio", isDirectory: true)
        }
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        self.storageFolder = appFolder
        load()
    }

    // MARK: - Load all tree folders from storage

    public func load() {
        trees = []
        folderMap = [:]

        let fm = FileManager.default

        // Bring any old flat-layout trees into the per-folder layout first.
        migrateLegacyLayoutIfNeeded()

        guard let entries = try? fm.contentsOfDirectory(at: storageFolder, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

        // A tree folder is any directory (other than Archived) containing a .ged file.
        let treeFolders = entries.filter { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return false }
            guard url.lastPathComponent != Self.archivedName else { return false }
            return gedFile(in: url) != nil
        }

        var needsReconcile: [FamilyTree] = []
        var failedFolders: [String] = []
        for folder in treeFolders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let ged = gedFile(in: folder) else { continue }
            do {
                let parsed = try GEDCOMParser.parse(from: ged)
                let tree = FamilyTree(name: parsed.name, subtitle: parsed.subtitle)
                // Identity: the embedded _TREEID is authoritative; fall back to a UUID
                // folder name (old layout) and finally to the freshly-generated id.
                tree.id = parsed.treeId ?? UUID(uuidString: folder.lastPathComponent) ?? tree.id
                tree.homePersonId = parsed.homePersonId
                tree.rootUnionId = parsed.rootUnionId
                tree.people = parsed.people
                tree.unions = parsed.unions
                tree.unknownRecords = parsed.unknownRecords

                trees.append(tree)
                folderMap[tree.id] = folder

                // Upgrade older layouts (UUID folder / "tree.ged" / no _TREEID) to a
                // readable folder + matching filename with the id embedded — once.
                let folderIsUUID = UUID(uuidString: folder.lastPathComponent) != nil
                let gedIsReadable = ged.lastPathComponent == gedURL(in: folder).lastPathComponent
                if parsed.treeId == nil || folderIsUUID || !gedIsReadable {
                    needsReconcile.append(tree)
                }
            } catch {
                log.error("Failed to load \(folder.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                failedFolders.append(folder.lastPathComponent)
            }
        }

        // Surface folders that look like a tree (have Media/ or Attachments/) but lack a
        // .ged — e.g. a save or migration that failed midway — rather than silently
        // dropping them, so the data is at least diagnosable instead of invisible.
        for url in entries where url.lastPathComponent != Self.archivedName {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  gedFile(in: url) == nil else { continue }
            let hasMedia = fm.fileExists(atPath: url.appendingPathComponent(Self.mediaName).path)
            let hasAttachments = fm.fileExists(atPath: url.appendingPathComponent(Self.attachmentsName).path)
            if hasMedia || hasAttachments {
                log.warning("Folder \(url.lastPathComponent, privacy: .public) has media/attachments but no .ged — not loaded.")
                failedFolders.append(url.lastPathComponent)
            }
        }

        // One-time: rename UUID/"tree.ged" layouts to readable names and embed _TREEID.
        for tree in needsReconcile {
            saveTree(tree)
        }

        // Migration: if old JSON exists and no trees were loaded, import it
        let legacyURL = storageFolder.appendingPathComponent("trees.json")
        if trees.isEmpty && fm.fileExists(atPath: legacyURL.path) {
            migrateFromJSON(legacyURL)
        }

        // Surface any unreadable trees: a folder that silently fails to load looks
        // exactly like data the user lost, so tell them which ones and where to look.
        if failedFolders.isEmpty {
            lastLoadError = nil
        } else {
            let list = failedFolders.map { "• \($0)" }.joined(separator: "\n")
            lastLoadError = "Не удалось прочитать \(failedFolders.count) дерев(о/а):\n\(list)\n\nФайлы не тронуты — откройте папку хранилища, чтобы проверить их."
        }
    }

    /// Migrate the old flat layout (`<UUID>.ged` + `Media_<UUID>/` at the storage
    /// root) into per-tree folders (`<UUID>/tree.ged` + `<UUID>/Media/`). Idempotent.
    /// This also fixes a long-standing bug where photos written to `Media_<UUID>/`
    /// were read back from a sibling `Media/` that never existed.
    private func migrateLegacyLayoutIfNeeded() {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: storageFolder, includingPropertiesForKeys: nil) else { return }
        let legacyGeds = entries.filter { $0.pathExtension.lowercased() == "ged" }
        for ged in legacyGeds {
            let stem = ged.deletingPathExtension().lastPathComponent
            let folderName = UUID(uuidString: stem) != nil ? stem : UUID().uuidString
            let folder = storageFolder.appendingPathComponent(folderName, isDirectory: true)
            let destGed = folder.appendingPathComponent(Self.gedName)
            // Already migrated (a tree.ged exists) → leave it be.
            if fm.fileExists(atPath: destGed.path) { continue }
            do {
                try fm.createDirectory(at: folder, withIntermediateDirectories: true)
                try fm.moveItem(at: ged, to: destGed)
            } catch {
                // Leave the legacy file untouched so it can be retried; don't move its
                // Media either, or we'd strand the .ged without its photos.
                log.error("Migration: could not move \(ged.lastPathComponent, privacy: .public), keeping legacy layout: \(error.localizedDescription, privacy: .public)")
                continue
            }
            let oldMedia = storageFolder.appendingPathComponent("Media_\(stem)", isDirectory: true)
            guard fm.fileExists(atPath: oldMedia.path) else { continue }
            let newMedia = folder.appendingPathComponent(Self.mediaName, isDirectory: true)
            if fm.fileExists(atPath: newMedia.path) {
                // Destination already exists — merge file-by-file instead of failing
                // (moveItem throws on an existing destination), then drop the old folder.
                if let mediaFiles = try? fm.contentsOfDirectory(at: oldMedia, includingPropertiesForKeys: nil) {
                    for f in mediaFiles {
                        let d = newMedia.appendingPathComponent(f.lastPathComponent)
                        if !fm.fileExists(atPath: d.path) { try? fm.copyItem(at: f, to: d) }
                    }
                }
                try? fm.removeItem(at: oldMedia)
            } else {
                do { try fm.moveItem(at: oldMedia, to: newMedia) }
                catch { log.error("Migration: could not move media for \(stem, privacy: .public): \(error.localizedDescription, privacy: .public)") }
            }
        }
    }

    // MARK: - Save a specific tree to its .ged file

    public func save() {
        for tree in trees {
            saveTree(tree)
        }
    }

    public func saveTree(_ tree: FamilyTree) {
        let fm = FileManager.default
        tree.updatedAt = Date()
        let folder = reconcileFolder(for: tree)
        let ged = gedURL(in: folder)
        // Drop any stale .ged left from a previous name so only the readable one remains.
        // Never touch the preserved original-import.ged safety copy.
        if let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension.lowercased() == "ged"
                && f.lastPathComponent != ged.lastPathComponent
                && f.lastPathComponent != Self.originalImportName {
                try? fm.removeItem(at: f)
            }
        }
        let mediaFolder = folder.appendingPathComponent(Self.mediaName, isDirectory: true)
        let result = GEDCOMSerializer.serialize(tree: tree)
        do {
            try result.gedcom.write(to: ged, atomically: true, encoding: .utf8)
            writePhotos(result.photos, to: mediaFolder)
            folderMap[tree.id] = folder
            // Portraits are now on disk: point each person at the media folder (so reads
            // load lazily) and clear the dirty flag (so an unchanged photo isn't rewritten
            // on the next save). Only changed photos are ever re-serialized after this.
            for person in tree.people {
                person.mediaFolderURL = mediaFolder
                person.photoIsDirty = false
            }
        } catch {
            // Surface the failure: in a data-authoring app a silent write error
            // means undetectable data loss. Views observe `lastSaveError`.
            log.error("Failed to save tree \(tree.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastSaveError = "Не удалось сохранить «\(tree.name)»: \(error.localizedDescription)"
        }
    }

    /// Write only the photos whose bytes changed, so editing one field doesn't
    /// rewrite every portrait on disk. The filename↔person mapping is owned by the
    /// serializer (`Result.photos`), keeping it consistent with the GEDCOM refs.
    private func writePhotos(_ photos: [GEDCOMSerializer.Photo], to mediaFolder: URL) {
        guard !photos.isEmpty else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
        for photo in photos {
            let dest = mediaFolder.appendingPathComponent(photo.filename)
            // Skip if an identical file already exists (cheap size check, then bytes).
            if let attrs = try? fm.attributesOfItem(atPath: dest.path),
               let size = attrs[.size] as? Int, size == photo.data.count,
               let existing = try? Data(contentsOf: dest), existing == photo.data {
                continue
            }
            try? photo.data.write(to: dest)
        }
    }

    public func addTree(_ tree: FamilyTree) {
        trees.append(tree)
        saveTree(tree)
    }

    public func deleteTree(_ tree: FamilyTree) {
        trees.removeAll(where: { $0.id == tree.id })
        // Remove the whole tree folder (.ged + Media/ + Attachments/).
        try? FileManager.default.removeItem(at: folder(for: tree))
        folderMap.removeValue(forKey: tree.id)
    }

    /// Rename a tree's title and subtitle, then persist to its .ged file.
    public func renameTree(_ tree: FamilyTree, name: String, subtitle: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        tree.name = trimmedName
        let trimmedSub = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        tree.subtitle = (trimmedSub?.isEmpty ?? true) ? nil : trimmedSub
        saveTree(tree)
    }

    /// Remove a tree from the library but keep its files: the whole tree folder is
    /// moved into `Archived/`, which `load()` ignores. Returns the moved folder URL
    /// to reveal in Finder.
    @discardableResult
    public func archiveTree(_ tree: FamilyTree) -> URL {
        let fm = FileManager.default
        let archiveFolder = storageFolder.appendingPathComponent(Self.archivedName, isDirectory: true)
        try? fm.createDirectory(at: archiveFolder, withIntermediateDirectories: true)

        let src = folder(for: tree)
        let dest = uniqueURL(archiveFolder.appendingPathComponent(sanitizedFileName(tree.name), isDirectory: true), isDirectory: true)
        try? fm.moveItem(at: src, to: dest)
        folderMap.removeValue(forKey: tree.id)
        trees.removeAll { $0.id == tree.id }
        return dest
    }

    /// Export a faithful copy of a tree (.ged + photos + attachments) into a `<name>/`
    /// bundle inside the chosen directory, so it can be re-imported later. Does NOT
    /// remove the tree — the caller decides whether to follow with `deleteTree`.
    /// Returns the bundle URL.
    @discardableResult
    public func exportTree(_ tree: FamilyTree, toDirectory directory: URL) throws -> URL {
        let fm = FileManager.default
        let name = sanitizedFileName(tree.name)
        let bundle = uniqueURL(directory.appendingPathComponent(name, isDirectory: true), isDirectory: true)
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        let srcFolder = folder(for: tree)

        // .ged — copy the stored file verbatim when available, otherwise serialize fresh.
        let gedDest = bundle.appendingPathComponent("\(name).ged")
        if let gedSrc = gedFile(in: srcFolder), fm.fileExists(atPath: gedSrc.path) {
            try fm.copyItem(at: gedSrc, to: gedDest)
        } else {
            let result = GEDCOMSerializer.serialize(tree: tree)
            try result.gedcom.write(to: gedDest, atomically: true, encoding: .utf8)
            writePhotos(result.photos, to: bundle.appendingPathComponent(Self.mediaName))
        }

        // Photos and attachments — copy the folders verbatim so refs resolve on re-import.
        for sub in [Self.mediaName, Self.attachmentsName] {
            let src = srcFolder.appendingPathComponent(sub, isDirectory: true)
            if fm.fileExists(atPath: src.path) {
                try? fm.copyItem(at: src, to: bundle.appendingPathComponent(sub, isDirectory: true))
            }
        }
        return bundle
    }

    // MARK: - Import external .ged file

    public func importGEDCOM(from url: URL) throws -> FamilyTree {
        let parsed = try GEDCOMParser.parse(from: url)
        let tree = FamilyTree(name: parsed.name, subtitle: parsed.subtitle)
        tree.homePersonId = parsed.homePersonId
        tree.rootUnionId = parsed.rootUnionId
        tree.people = parsed.people
        tree.unions = parsed.unions
        tree.unknownRecords = parsed.unknownRecords

        // Copy the source file's sibling Media/ folder into the new tree folder BEFORE
        // saving. Photo bytes are no longer loaded into memory on parse (they load
        // lazily), so the portraits must be carried over as files here rather than being
        // re-serialized from memory.
        let fm = FileManager.default
        let srcMedia = url.deletingLastPathComponent().appendingPathComponent(Self.mediaName, isDirectory: true)

        addTree(tree) // creates the tree folder and writes tree.ged

        let destMedia = folder(for: tree).appendingPathComponent(Self.mediaName, isDirectory: true)
        if fm.fileExists(atPath: srcMedia.path),
           let files = try? fm.contentsOfDirectory(at: srcMedia, includingPropertiesForKeys: nil) {
            try? fm.createDirectory(at: destMedia, withIntermediateDirectories: true)
            for f in files {
                let d = destMedia.appendingPathComponent(f.lastPathComponent)
                if !fm.fileExists(atPath: d.path) { try? fm.copyItem(at: f, to: d) }
            }
        }
        // Repoint each person's lazy-load folder at the tree's own Media/ (the source
        // URL may be a one-shot, security-scoped pick that won't be readable later).
        for person in tree.people { person.mediaFolderURL = destMedia }

        // Keep the imported file byte-for-byte as `original-import.ged`, never rewritten.
        // Even though the parser now preserves unknown structures (T19), an exact copy of
        // what the user handed us is the ultimate safety net against any interop surprise.
        let originalDest = folder(for: tree).appendingPathComponent("original-import.ged")
        try? fm.copyItem(at: url, to: originalDest)

        // Carry over attached files: unlike photos they aren't held in memory, so copy
        // them from the source bundle's Attachments/ folder. Best-effort (sandbox may
        // restrict sibling access on import); the tree itself imports regardless.
        let srcAttachments = url.deletingLastPathComponent().appendingPathComponent(Self.attachmentsName, isDirectory: true)
        if fm.fileExists(atPath: srcAttachments.path),
           let files = try? fm.contentsOfDirectory(at: srcAttachments, includingPropertiesForKeys: nil) {
            let dest = attachmentsFolderURL(for: tree)
            try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
            for f in files {
                try? fm.copyItem(at: f, to: dest.appendingPathComponent(f.lastPathComponent))
            }
        }
        return tree
    }

    // MARK: - Export .ged to a user-chosen location

    public func exportGEDCOM(tree: FamilyTree, to url: URL) throws {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let mediaFolder = dir.appendingPathComponent(Self.mediaName, isDirectory: true)
        let result = GEDCOMSerializer.serialize(tree: tree)
        // The .ged write is the contract — surface its failure to the caller.
        try result.gedcom.write(to: url, atomically: true, encoding: .utf8)
        // Write any changed-in-memory portraits, then copy the rest of the tree's Media/
        // folder verbatim (unchanged photos aren't held in memory any more).
        writePhotos(result.photos, to: mediaFolder)
        let storedMedia = folder(for: tree).appendingPathComponent(Self.mediaName, isDirectory: true)
        if fm.fileExists(atPath: storedMedia.path),
           let files = try? fm.contentsOfDirectory(at: storedMedia, includingPropertiesForKeys: nil) {
            try? fm.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
            for f in files {
                let d = mediaFolder.appendingPathComponent(f.lastPathComponent)
                if !fm.fileExists(atPath: d.path) { try? fm.copyItem(at: f, to: d) }
            }
        }

        // Carry attachments next to the .ged so its _ATTC references resolve on re-import.
        let attSrc = attachmentsFolderURL(for: tree)
        if fm.fileExists(atPath: attSrc.path),
           let files = try? fm.contentsOfDirectory(at: attSrc, includingPropertiesForKeys: nil) {
            let attDest = dir.appendingPathComponent(Self.attachmentsName, isDirectory: true)
            try? fm.createDirectory(at: attDest, withIntermediateDirectories: true)
            for f in files {
                let d = attDest.appendingPathComponent(f.lastPathComponent)
                if !fm.fileExists(atPath: d.path) { try? fm.copyItem(at: f, to: d) }
            }
        }
    }

    /// Re-point every person's lazy portrait loader at the tree's Media/ folder. Undo/redo
    /// swaps in freshly-decoded Person instances (which carry the photo *filename* but not
    /// the transient folder URL), so call this after a restore to keep portraits loadable.
    public func refreshMediaFolders(for tree: FamilyTree) {
        let mediaFolder = folder(for: tree).appendingPathComponent(Self.mediaName, isDirectory: true)
        for person in tree.people { person.mediaFolderURL = mediaFolder }
    }

    // MARK: - Attachments

    /// The folder that holds a tree's attached files (created on demand).
    public func attachmentsFolderURL(for tree: FamilyTree) -> URL {
        folder(for: tree).appendingPathComponent(Self.attachmentsName, isDirectory: true)
    }

    /// On-disk location of a specific attachment.
    public func attachmentURL(_ attachment: Attachment, in tree: FamilyTree) -> URL {
        attachmentsFolderURL(for: tree).appendingPathComponent(attachment.storedName)
    }

    /// Copy a user-picked file into the tree's Attachments/ folder, link it to the
    /// person, and persist. `sourceURL` may be security-scoped (from a file picker).
    @discardableResult
    public func addAttachment(to person: Person, in tree: FamilyTree, sourceURL: URL) throws -> Attachment {
        let fm = FileManager.default
        let folder = attachmentsFolderURL(for: tree)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let originalName = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension
        let storedName = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
        let dest = folder.appendingPathComponent(storedName)

        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        try fm.copyItem(at: sourceURL, to: dest)

        let attachment = Attachment(storedName: storedName, originalName: originalName)
        person.attachments.append(attachment)
        person.updatedAt = Date()
        saveTree(tree)
        return attachment
    }

    /// Remove an attachment's file from disk, unlink it from the person, and persist.
    public func removeAttachment(_ attachment: Attachment, from person: Person, in tree: FamilyTree) {
        try? FileManager.default.removeItem(at: attachmentURL(attachment, in: tree))
        person.attachments.removeAll { $0.id == attachment.id }
        person.updatedAt = Date()
        saveTree(tree)
    }

    /// Delete every attachment file belonging to a person (used when the person is
    /// removed). Does not persist — the caller saves the tree afterward.
    public func deleteAttachmentFiles(of person: Person, in tree: FamilyTree) {
        for attachment in person.attachments {
            try? FileManager.default.removeItem(at: attachmentURL(attachment, in: tree))
        }
    }

    // MARK: - Helpers

    /// Public access to the tree's .ged file (e.g. for "Reveal in Finder"); falls back
    /// to the folder itself if the file can't be located.
    public func gedFileURL(for tree: FamilyTree) -> URL {
        let folder = folder(for: tree)
        return gedFile(in: folder) ?? folder
    }

    private func folder(for tree: FamilyTree) -> URL {
        if let existing = folderMap[tree.id] { return existing }
        return storageFolder.appendingPathComponent(tree.id.uuidString, isDirectory: true)
    }

    /// The canonical .ged path inside a tree folder: "<folder name>.ged".
    private func gedURL(in folder: URL) -> URL {
        folder.appendingPathComponent("\(folder.lastPathComponent).ged")
    }

    /// The first .ged file inside a folder, if any (its name may differ pre-migration).
    /// The preserved `original-import.ged` is never the tree's working file.
    private func gedFile(in folder: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        return files.first { $0.pathExtension.lowercased() == "ged" && $0.lastPathComponent != Self.originalImportName }
    }

    /// Ensure the tree has a folder named after it (readable & unique), renaming the
    /// existing folder when the name changed. Returns the folder and updates folderMap.
    private func reconcileFolder(for tree: FamilyTree) -> URL {
        let fm = FileManager.default
        let desired = sanitizedFileName(tree.name)
        if let current = folderMap[tree.id], fm.fileExists(atPath: current.path) {
            let target = uniqueFolderURL(named: desired, excluding: current)
            if target.lastPathComponent != current.lastPathComponent {
                do {
                    try fm.moveItem(at: current, to: target)
                    folderMap[tree.id] = target
                    return target
                } catch {
                    log.error("Could not rename \(current.lastPathComponent, privacy: .public) → \(target.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    return current
                }
            }
            return current
        }
        let target = uniqueFolderURL(named: desired, excluding: nil)
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        folderMap[tree.id] = target
        return target
    }

    /// A storage-folder URL named `base`, suffixed " 2", " 3", … to avoid colliding
    /// with any folder other than `excluding` (the tree's own current folder).
    private func uniqueFolderURL(named base: String, excluding current: URL?) -> URL {
        let fm = FileManager.default
        func isFree(_ url: URL) -> Bool {
            if let c = current, url.standardizedFileURL == c.standardizedFileURL { return true }
            return !fm.fileExists(atPath: url.path)
        }
        let first = storageFolder.appendingPathComponent(base, isDirectory: true)
        if isFree(first) { return first }
        var i = 2
        while true {
            let candidate = storageFolder.appendingPathComponent("\(base) \(i)", isDirectory: true)
            if isFree(candidate) { return candidate }
            i += 1
        }
    }

    /// Strip filesystem-illegal characters so a tree name can be used as a file/folder name.
    private func sanitizedFileName(_ raw: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = raw.components(separatedBy: illegal)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Дерево" : cleaned
    }

    /// Append " 2", " 3", … to `url`'s name until it points at a non-existent path.
    /// For directories pass `isDirectory: true` so a dot in the name (e.g. "Family v1.2")
    /// isn't mistaken for a file extension.
    private func uniqueURL(_ url: URL, isDirectory: Bool = false) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let dir = url.deletingLastPathComponent()
        let base = isDirectory ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
        let ext = isDirectory ? "" : url.pathExtension
        var i = 2
        while true {
            let candidateName = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            let candidate = dir.appendingPathComponent(candidateName)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }

    // MARK: - Legacy JSON Migration

    private func migrateFromJSON(_ jsonURL: URL) {
        do {
            let data = try Data(contentsOf: jsonURL)
            let oldTrees = try JSONDecoder().decode([FamilyTree].self, from: data)
            for tree in oldTrees {
                trees.append(tree)
                saveTree(tree)
            }
            // Rename old file as backup
            let backup = jsonURL.appendingPathExtension("bak")
            try? FileManager.default.moveItem(at: jsonURL, to: backup)
            log.notice("Migrated \(oldTrees.count) tree(s) from JSON to GEDCOM")
        } catch {
            log.error("JSON migration failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
