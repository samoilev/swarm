import Foundation

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
final class TreeStore {
    var trees: [FamilyTree] = []

    private let storageFolder: URL

    /// Maps tree UUID → its folder URL.
    private var folderMap: [UUID: URL] = [:]

    private static let gedName = "tree.ged"
    private static let mediaName = "Media"
    private static let attachmentsName = "Attachments"
    private static let archivedName = "Archived"

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = appSupport.appendingPathComponent("FamilyTreeStudio", isDirectory: true)
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        storageFolder = appFolder
        load()
    }
    
    // MARK: - Load all tree folders from storage

    func load() {
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
                print("Failed to load \(folder.lastPathComponent): \(error)")
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
                print("Warning: folder \(url.lastPathComponent) has media/attachments but no .ged — not loaded.")
            }
        }

        // One-time: rename UUID/"tree.ged" layouts to readable names and embed _TREEID.
        for tree in needsReconcile { saveTree(tree) }

        // Migration: if old JSON exists and no trees were loaded, import it
        let legacyURL = storageFolder.appendingPathComponent("trees.json")
        if trees.isEmpty && fm.fileExists(atPath: legacyURL.path) {
            migrateFromJSON(legacyURL)
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
                print("Migration: could not move \(ged.lastPathComponent), keeping legacy layout: \(error)")
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
                catch { print("Migration: could not move media for \(stem): \(error)") }
            }
        }
    }
    
    // MARK: - Save a specific tree to its .ged file
    
    func save() {
        for tree in trees {
            saveTree(tree)
        }
    }
    
    func saveTree(_ tree: FamilyTree) {
        let fm = FileManager.default
        tree.updatedAt = Date()
        let folder = reconcileFolder(for: tree)
        let ged = gedURL(in: folder)
        // Drop any stale .ged left from a previous name so only the readable one remains.
        if let files = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            for f in files where f.pathExtension.lowercased() == "ged" && f.lastPathComponent != ged.lastPathComponent {
                try? fm.removeItem(at: f)
            }
        }
        let mediaFolder = folder.appendingPathComponent(Self.mediaName, isDirectory: true)
        let content = GEDCOMSerializer.serialize(tree: tree, mediaFolder: mediaFolder)
        do {
            try content.write(to: ged, atomically: true, encoding: .utf8)
            folderMap[tree.id] = folder
        } catch {
            print("Failed to save tree \(tree.name): \(error)")
        }
    }
    
    func addTree(_ tree: FamilyTree) {
        trees.append(tree)
        saveTree(tree)
    }
    
    func deleteTree(_ tree: FamilyTree) {
        trees.removeAll(where: { $0.id == tree.id })
        // Remove the whole tree folder (.ged + Media/ + Attachments/).
        try? FileManager.default.removeItem(at: folder(for: tree))
        folderMap.removeValue(forKey: tree.id)
    }

    /// Rename a tree's title and subtitle, then persist to its .ged file.
    func renameTree(_ tree: FamilyTree, name: String, subtitle: String?) {
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
    func archiveTree(_ tree: FamilyTree) -> URL {
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
    func exportTree(_ tree: FamilyTree, toDirectory directory: URL) throws -> URL {
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
            let content = GEDCOMSerializer.serialize(tree: tree, mediaFolder: bundle.appendingPathComponent(Self.mediaName))
            try content.write(to: gedDest, atomically: true, encoding: .utf8)
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
    
    func importGEDCOM(from url: URL) throws -> FamilyTree {
        let parsed = try GEDCOMParser.parse(from: url)
        let tree = FamilyTree(name: parsed.name, subtitle: parsed.subtitle)
        tree.homePersonId = parsed.homePersonId
        tree.rootUnionId = parsed.rootUnionId
        tree.people = parsed.people
        tree.unions = parsed.unions
        addTree(tree) // creates the tree folder and writes tree.ged + Media/

        // Carry over attached files: unlike photos they aren't held in memory, so copy
        // them from the source bundle's Attachments/ folder. Best-effort (sandbox may
        // restrict sibling access on import); the tree itself imports regardless.
        let srcAttachments = url.deletingLastPathComponent().appendingPathComponent(Self.attachmentsName, isDirectory: true)
        let fm = FileManager.default
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
    
    func exportGEDCOM(tree: FamilyTree, to url: URL) {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        let mediaFolder = dir.appendingPathComponent(Self.mediaName, isDirectory: true)
        let content = GEDCOMSerializer.serialize(tree: tree, mediaFolder: mediaFolder)
        try? content.write(to: url, atomically: true, encoding: .utf8)

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
    
    // MARK: - Attachments

    /// The folder that holds a tree's attached files (created on demand).
    func attachmentsFolderURL(for tree: FamilyTree) -> URL {
        folder(for: tree).appendingPathComponent(Self.attachmentsName, isDirectory: true)
    }

    /// On-disk location of a specific attachment.
    func attachmentURL(_ attachment: Attachment, in tree: FamilyTree) -> URL {
        attachmentsFolderURL(for: tree).appendingPathComponent(attachment.storedName)
    }

    /// Copy a user-picked file into the tree's Attachments/ folder, link it to the
    /// person, and persist. `sourceURL` may be security-scoped (from a file picker).
    @discardableResult
    func addAttachment(to person: Person, in tree: FamilyTree, sourceURL: URL) throws -> Attachment {
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
    func removeAttachment(_ attachment: Attachment, from person: Person, in tree: FamilyTree) {
        try? FileManager.default.removeItem(at: attachmentURL(attachment, in: tree))
        person.attachments.removeAll { $0.id == attachment.id }
        person.updatedAt = Date()
        saveTree(tree)
    }

    /// Delete every attachment file belonging to a person (used when the person is
    /// removed). Does not persist — the caller saves the tree afterward.
    func deleteAttachmentFiles(of person: Person, in tree: FamilyTree) {
        for attachment in person.attachments {
            try? FileManager.default.removeItem(at: attachmentURL(attachment, in: tree))
        }
    }

    // MARK: - Helpers

    /// Public access to the tree's .ged file (e.g. for "Reveal in Finder"); falls back
    /// to the folder itself if the file can't be located.
    func gedFileURL(for tree: FamilyTree) -> URL {
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
    private func gedFile(in folder: URL) -> URL? {
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        return files.first { $0.pathExtension.lowercased() == "ged" }
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
                    print("Could not rename \(current.lastPathComponent) → \(target.lastPathComponent): \(error)")
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
            print("Migrated \(oldTrees.count) tree(s) from JSON to GEDCOM")
        } catch {
            print("JSON migration failed: \(error)")
        }
    }
}

