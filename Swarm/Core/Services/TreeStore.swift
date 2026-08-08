import CryptoKit
import Foundation
import Observation
import os

private let log = Logger(subsystem: "com.samoilev.swarm", category: "TreeStore")

/// GEDCOM-based persistence for family trees. Everything is stored strictly
/// locally in ~/Library/Application Support/Swarm/.
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

    /// Set when legacy storage could not be migrated without choosing between two
    /// existing locations. Both locations remain untouched and the user is shown the
    /// folder that needs manual review.
    public var storageMigrationWarning: String?
    public private(set) var storageMigrationWarningURL: URL?

    /// Old-format items discovered by `load()`, each naming the tree and file it refers
    /// to. Pending migration is not a load failure — those trees are readable — so it is
    /// surfaced separately from `lastLoadError`.
    public private(set) var pendingMigrations: [PendingMigration] = []
    public var pendingMigrationCount: Int { pendingMigrations.count }
    /// Production leaves this nil. Integration tests inject failures at transaction
    /// boundaries to prove the previously committed bundle remains usable.
    @ObservationIgnored public var faultInjector: ((PersistenceFaultPoint) throws -> Void)?

    /// Card diagrams, keyed on the tree and the moment it was last written. A diagram is
    /// a walk over the top three generations, which is cheap — but the library rebuilds
    /// every card body on hover, filter and sort, and a grid of large archives should not
    /// re-walk on each of those. Observation is skipped: this is derived from `trees`, and
    /// reading it must not make a view depend on it.
    @ObservationIgnored private var diagramCache: [UUID: (updatedAt: Date, diagram: TreeDiagram)] = [:]

    /// The card diagram for `tree`, recomputed only when the tree has been written since.
    public func diagram(for tree: FamilyTree) -> TreeDiagram {
        if let cached = diagramCache[tree.id], cached.updatedAt == tree.updatedAt {
            return cached.diagram
        }
        let diagram = TreeDiagram(tree: tree)
        diagramCache[tree.id] = (tree.updatedAt, diagram)
        return diagram
    }

    private let storageFolder: URL

    /// The root storage directory (for "Reveal in Finder" when a load fails).
    public var storageFolderURL: URL { storageFolder }

    /// Maps tree UUID → its folder URL.
    private var folderMap: [UUID: URL] = [:]
    private var legacyFileMap: [UUID: URL] = [:]

    private static let gedName = "tree.ged"
    private static let mediaName = "Media"
    private static let attachmentsName = "Attachments"
    private static let archivedName = "Archived"
    private static let recoveryName = "Recovery"
    private static let pendingName = ".Pending"
    private static let metadataName = ".Swarm"
    private static let legacyMetadataName = ".FamilyTreeStudio"
    private static let appFolderName = "Swarm"
    private static let legacyAppFolderName = "FamilyTreeStudio"
    private static let historyName = "History"
    private static let trashName = "Trash"
    private static let manifestName = "manifest.json"
    /// Verbatim copy of an imported file, kept as a safety net and never treated as
    /// the tree's own working .ged (excluded from load/save/reconcile).
    private static let originalImportName = "original-import.ged"

    private struct PendingAttachment {
        let temporaryURL: URL
        let storedName: String
    }

    private struct PendingImport {
        let originalGEDCOM: URL
        let mediaFolder: URL
        let attachmentsFolder: URL
    }

    private var pendingAttachmentAdds: [UUID: [PendingAttachment]] = [:]
    private var pendingAttachmentDeletes: [UUID: Set<String>] = [:]
    private var pendingImports: [UUID: PendingImport] = [:]
    /// Keyed by staged GEDCOM path: what an import preview could not bring across.
    private var pendingImportDiagnostics: [String: [ImportDiagnostic]] = [:]
    private var pendingBundleRestores: [UUID: URL] = [:]
    private var pendingTrashRemovals: [UUID: Set<String>] = [:]

    struct DefaultStoragePreparation {
        let folder: URL
        let warning: String?
        let warningURL: URL?
    }

    /// Default init: stores trees in ~/Library/Application Support/Swarm/.
    /// Tests pass an explicit `storageFolder` (a temp dir) to exercise the migration
    /// and folder-reconcile logic without touching the user's real library.
    public init(storageFolder: URL? = nil) {
        let appFolder: URL
        if let storageFolder {
            appFolder = storageFolder
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let preparation = Self.prepareDefaultStorage(in: appSupport)
            appFolder = preparation.folder
            storageMigrationWarning = preparation.warning
            storageMigrationWarningURL = preparation.warningURL
        }
        do {
            try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        } catch {
            self.storageFolder = appFolder
            lastLoadError = L10n.tr("Не удалось открыть папку хранилища: \(error.localizedDescription)")
            return
        }
        self.storageFolder = appFolder
        load()
    }

    static func prepareDefaultStorage(
        in applicationSupport: URL,
        fileManager fm: FileManager = .default
    ) -> DefaultStoragePreparation {
        let current = applicationSupport.appendingPathComponent(appFolderName, isDirectory: true)
        let legacy = applicationSupport.appendingPathComponent(legacyAppFolderName, isDirectory: true)
        let currentExists = fm.fileExists(atPath: current.path)
        let legacyExists = fm.fileExists(atPath: legacy.path)

        if currentExists, legacyExists {
            let metadataConflict = migrateLegacyMetadataFolders(in: current, fileManager: fm)
            var warning = L10n.tr(
                "Найдены папки данных Swarm и предыдущей версии. Чтобы ничего не перезаписать, Swarm использует новую папку, а старую оставил без изменений."
            )
            if metadataConflict {
                warning += "\n\n" + L10n.tr(
                    "Некоторые старые папки истории также оставлены без изменений, потому что рядом уже есть папки Swarm."
                )
            }
            return DefaultStoragePreparation(folder: current, warning: warning, warningURL: legacy)
        }

        if legacyExists {
            do {
                try fm.moveItem(at: legacy, to: current)
            } catch {
                return DefaultStoragePreparation(
                    folder: legacy,
                    warning: L10n.tr(
                        "Не удалось перенести папку данных в Swarm. Предыдущая папка используется без изменений: \(error.localizedDescription)"
                    ),
                    warningURL: legacy
                )
            }
        }

        let metadataConflict = migrateLegacyMetadataFolders(in: current, fileManager: fm)
        let warning = metadataConflict
            ? L10n.tr(
                "Некоторые старые папки истории оставлены без изменений, потому что рядом уже есть папки Swarm."
            )
            : nil
        return DefaultStoragePreparation(
            folder: current,
            warning: warning,
            warningURL: metadataConflict ? current : nil
        )
    }

    private static func migrateLegacyMetadataFolders(
        in root: URL,
        fileManager fm: FileManager
    ) -> Bool {
        guard fm.fileExists(atPath: root.path),
              let enumerator = fm.enumerator(
                  at: root,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [],
                  errorHandler: nil
              ) else { return false }

        let legacyFolders = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL,
                  url.lastPathComponent == legacyMetadataName,
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            return url
        }

        var hadConflict = false
        for legacyFolder in legacyFolders {
            let destination = legacyFolder
                .deletingLastPathComponent()
                .appendingPathComponent(metadataName, isDirectory: true)
            guard !fm.fileExists(atPath: destination.path) else {
                hadConflict = true
                continue
            }
            do {
                try fm.moveItem(at: legacyFolder, to: destination)
            } catch {
                hadConflict = true
            }
        }
        return hadConflict
    }

    // MARK: - Load all tree folders from storage

    public func load() {
        trees = []
        folderMap = [:]
        legacyFileMap = [:]
        pendingMigrations = []

        let fm = FileManager.default

        // Discovery is read-only. Legacy files are listed and migrated only through
        // the explicit, backup-protected `performPendingMigrations()` operation.
        guard let entries = try? fm.contentsOfDirectory(at: storageFolder, includingPropertiesForKeys: [.isDirectoryKey]) else { return }

        // A tree folder is any directory (other than Archived) containing a .ged file.
        let treeFolders = entries.filter { url in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return false }
            guard ![Self.archivedName, Self.recoveryName, Self.pendingName].contains(url.lastPathComponent),
                  !url.lastPathComponent.hasPrefix(".") else { return false }
            return gedFile(in: url) != nil
        }

        var needsReconcile: [FamilyTree] = []
        var failedFolders: [String] = []
        for folder in treeFolders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard let ged = gedFile(in: folder) else { continue }
            do {
                let imported = try GEDCOMCodec.parse(ged)
                let parsed = imported.tree
                let tree = parsed
                let originalImport = folder.appendingPathComponent(Self.originalImportName)
                if fm.fileExists(atPath: originalImport.path) {
                    tree.acceptedBaselineIssueIDs = Set(
                        TreeValidator.validate(tree).filter { $0.severity == .error }.map(\.id)
                    )
                }
                // Identity: the embedded _TREEID is authoritative; fall back to a UUID
                // folder name (old layout) and finally to the freshly-generated id.
                if let folderID = UUID(uuidString: folder.lastPathComponent),
                   let text = try? String(contentsOf: ged, encoding: .utf8),
                   !text.contains("1 _TREEID ") {
                    tree.id = folderID
                }

                trees.append(tree)
                folderMap[tree.id] = folder

                // Upgrade older layouts (UUID folder / "tree.ged" / no _TREEID) to a
                // readable folder + matching filename with the id embedded — once.
                let folderIsUUID = UUID(uuidString: folder.lastPathComponent) != nil
                let gedIsReadable = ged.lastPathComponent == gedURL(in: folder).lastPathComponent
                if tree.schemaVersion < 2 || folderIsUUID || !gedIsReadable {
                    needsReconcile.append(tree)
                }
            } catch {
                log.error("Failed to load \(folder.lastPathComponent, privacy: .public): \(error.localizedDescription, privacy: .public)")
                failedFolders.append(folder.lastPathComponent)
            }
        }

        // Legacy flat GEDCOM files remain visible but untouched. Saving is blocked
        // until the user runs the explicit migration transaction.
        for ged in entries.filter({ $0.pathExtension.lowercased() == "ged" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do {
                let imported = try GEDCOMCodec.parse(ged)
                let tree = imported.tree
                if let legacyID = UUID(uuidString: ged.deletingPathExtension().lastPathComponent) { tree.id = legacyID }
                pendingMigrations.append(PendingMigration(title: tree.name, source: .legacyFile, url: ged))
                guard !trees.contains(where: { $0.id == tree.id }) else { continue }
                let media = storageFolder.appendingPathComponent("Media_\(ged.deletingPathExtension().lastPathComponent)", isDirectory: true)
                for person in tree.people { person.mediaFolderURL = media }
                trees.append(tree)
                legacyFileMap[tree.id] = ged
            } catch {
                failedFolders.append(ged.lastPathComponent)
            }
        }

        // Surface folders that look like a tree (have Media/ or Attachments/) but lack a
        // .ged — e.g. a save or migration that failed midway — rather than silently
        // dropping them, so the data is at least diagnosable instead of invisible.
        for url in entries where ![Self.archivedName, Self.recoveryName, Self.pendingName].contains(url.lastPathComponent) && !url.lastPathComponent.hasPrefix(".") {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  gedFile(in: url) == nil else { continue }
            let hasMedia = fm.fileExists(atPath: url.appendingPathComponent(Self.mediaName).path)
            let hasAttachments = fm.fileExists(atPath: url.appendingPathComponent(Self.attachmentsName).path)
            if hasMedia || hasAttachments {
                log.warning("Folder \(url.lastPathComponent, privacy: .public) has media/attachments but no .ged — not loaded.")
                failedFolders.append(url.lastPathComponent)
            }
        }

        for tree in needsReconcile {
            pendingMigrations.append(
                PendingMigration(title: tree.name, source: .treeFolder, url: folderMap[tree.id] ?? storageFolder)
            )
        }

        // Legacy JSON is also reported but never mutated during discovery.
        let legacyURL = storageFolder.appendingPathComponent("trees.json")
        if trees.isEmpty && fm.fileExists(atPath: legacyURL.path) {
            pendingMigrations.append(PendingMigration(title: L10n.tr("Все деревья"), source: .legacyJSON, url: legacyURL))
        }

        // Surface any unreadable trees: a folder that silently fails to load looks
        // exactly like data the user lost, so tell them which ones and where to look.
        // Pending migrations are deliberately *not* reported here — those trees opened
        // fine, and calling that an error taught the user to distrust a working app.
        if failedFolders.isEmpty {
            lastLoadError = nil
        } else {
            let list = failedFolders.map { "• \($0)" }.joined(separator: "\n")
            lastLoadError = L10n.tr("Эти файлы не удалось прочитать:\n\(list)\n\n")
                + L10n.tr("Они лежат в папке архивов и не изменены. ")
                + L10n.tr("Откройте «Показать в Finder», чтобы посмотреть или скопировать их.")
        }

        // `contentsOfDirectory` returns whatever order the filesystem hands back, which
        // is neither alphabetical nor stable between launches. The library relies on
        // spatial memory, so ordering has to be a property of the data, not of APFS.
        // Recency first; the library offers name order as the alternative.
        trees.sort { $0.updatedAt > $1.updatedAt }
    }

    /// Run every discovered migration explicitly. Each existing tree is protected by
    /// a permanent pre-v2 bundle backup; flat-layout and JSON sources move into the
    /// Recovery area only after their imported replacement verifies successfully.
    @discardableResult
    public func performPendingMigrations() throws -> [SaveReceipt] {
        let fm = FileManager.default
        var receipts: [SaveReceipt] = []

        // Existing per-tree folders: transactional save performs the folder/file
        // rename and creates the pre-v2 recovery copy first.
        for tree in trees {
            if legacyFileMap[tree.id] != nil { continue }
            let folder = folder(for: tree)
            let needsMigration = tree.schemaVersion < 2 || UUID(uuidString: folder.lastPathComponent) != nil ||
                gedFile(in: folder)?.lastPathComponent != gedURL(in: folder).lastPathComponent
            if needsMigration { try receipts.append(persistTree(tree)) }
        }

        let entries = try fm.contentsOfDirectory(at: storageFolder, includingPropertiesForKeys: nil)
        let legacyRoot = storageFolder
            .appendingPathComponent(Self.recoveryName, isDirectory: true)
            .appendingPathComponent("Legacy", isDirectory: true)
        for ged in entries where ged.pathExtension.lowercased() == "ged" {
            let parsed = try GEDCOMCodec.parse(ged).tree
            let stem = ged.deletingPathExtension().lastPathComponent
            if let legacyID = UUID(uuidString: stem) { parsed.id = legacyID }
            let tree = trees.first(where: { legacyFileMap[$0.id] == ged }) ?? parsed
            legacyFileMap[tree.id] = nil
            if folderMap[tree.id] != nil { tree.id = UUID() }
            let oldMedia = storageFolder.appendingPathComponent("Media_\(stem)", isDirectory: true)
            pendingImports[tree.id] = PendingImport(
                originalGEDCOM: ged,
                mediaFolder: oldMedia,
                attachmentsFolder: storageFolder.appendingPathComponent("Attachments_\(stem)", isDirectory: true)
            )
            try receipts.append(persistTree(tree))
            if !trees.contains(where: { $0 === tree }) { trees.append(tree) }

            let destination = uniqueURL(legacyRoot.appendingPathComponent("\(timestamp())-\(stem)", isDirectory: true), isDirectory: true)
            try fm.createDirectory(at: destination, withIntermediateDirectories: true)
            try fm.moveItem(at: ged, to: destination.appendingPathComponent(ged.lastPathComponent))
            if fm.fileExists(atPath: oldMedia.path) {
                try fm.moveItem(at: oldMedia, to: destination.appendingPathComponent(oldMedia.lastPathComponent))
            }
        }

        let json = storageFolder.appendingPathComponent("trees.json")
        if fm.fileExists(atPath: json.path) {
            let oldTrees = try JSONDecoder().decode([FamilyTree].self, from: Data(contentsOf: json))
            for tree in oldTrees {
                if trees.contains(where: { $0.id == tree.id }) { tree.id = UUID() }
                let receipt = try persistTree(tree)
                receipts.append(receipt)
                trees.append(tree)
            }
            try fm.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
            try fm.moveItem(at: json, to: uniqueURL(legacyRoot.appendingPathComponent("\(timestamp())-trees.json")))
        }

        load()
        return receipts
    }

    public func recoveryItems(for tree: FamilyTree? = nil) -> [RecoveryItem] {
        var result: [RecoveryItem] = []
        let selectedTrees = tree.map { [$0] } ?? trees
        for candidate in selectedTrees {
            let folder = folder(for: candidate)
            let metadata = folder.appendingPathComponent(Self.metadataName, isDirectory: true)
            let history = metadata.appendingPathComponent(Self.historyName, isDirectory: true)
            let trash = metadata.appendingPathComponent(Self.trashName, isDirectory: true)
            result += recoveryItems(in: history, kind: .revision)
            result += recoveryItems(in: trash, kind: .deletedFile)
            let migration = storageFolder.appendingPathComponent(Self.recoveryName, isDirectory: true)
                .appendingPathComponent(candidate.id.uuidString, isDirectory: true)
            result += recoveryItems(in: migration, kind: .migrationBackup)
        }
        let archived = storageFolder.appendingPathComponent(Self.archivedName, isDirectory: true)
        result += recoveryItems(in: archived, kind: .archivedTree)
        return result.sorted { $0.createdAt > $1.createdAt }
    }

    /// Create a verified, indefinitely retained full-bundle snapshot. Merge and other
    /// high-risk workflows call this before mutating the in-memory tree.
    @discardableResult
    public func createVerifiedBackup(for tree: FamilyTree, label: String) throws -> URL {
        let fm = FileManager.default
        let source = folder(for: tree)
        guard fm.fileExists(atPath: source.path) else { throw TreeStoreError.treeFolderMissing }
        let safeLabel = sanitizedFileName(label).replacingOccurrences(of: " ", with: "-")
        let recovery = storageFolder
            .appendingPathComponent(Self.recoveryName, isDirectory: true)
            .appendingPathComponent(tree.id.uuidString, isDirectory: true)
        try fm.createDirectory(at: recovery, withIntermediateDirectories: true)
        let destination = uniqueURL(
            recovery.appendingPathComponent("\(timestamp())-\(safeLabel)", isDirectory: true),
            isDirectory: true
        )
        do {
            try fm.copyItem(at: source, to: destination)
            let backupHashes = try hashes(in: destination, includeRecoveryData: false)
            try verify(hashes: backupHashes, in: destination)
            try writeManifest(generationID: UUID(), hashes: backupHashes, in: destination)
            return destination
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    public func restoreRevision(_ item: RecoveryItem, to tree: FamilyTree) async throws -> SaveReceipt {
        guard item.kind == .revision, FileManager.default.fileExists(atPath: item.url.path) else {
            throw TreeStoreError.recoveryItemMissing
        }
        let before = try JSONEncoder().encode(tree)
        do {
            let imported = try GEDCOMCodec.parse(item.url)
            applySnapshot(imported.tree, to: tree)
            return try persistTree(tree)
        } catch {
            if let snapshot = try? JSONDecoder().decode(FamilyTree.self, from: before) { applySnapshot(snapshot, to: tree) }
            throw error
        }
    }

    @discardableResult
    public func restoreArchivedTree(_ item: RecoveryItem) throws -> FamilyTree {
        guard item.kind == .archivedTree, FileManager.default.fileExists(atPath: item.url.path) else {
            throw TreeStoreError.recoveryItemMissing
        }
        guard let archivedGEDCOM = gedFile(in: item.url) else { throw TreeStoreError.treeFolderMissing }
        let expectedID = try GEDCOMCodec.parse(archivedGEDCOM).tree.id
        let destination = uniqueFolderURL(named: item.url.lastPathComponent, excluding: nil)
        let originalArchiveURL = item.url
        try FileManager.default.moveItem(at: originalArchiveURL, to: destination)
        load()
        if let restored = trees.first(where: { $0.id == expectedID }) { return restored }
        do {
            try FileManager.default.moveItem(at: destination, to: originalArchiveURL)
        } catch {
            lastLoadError = L10n.tr("Архив не удалось подключить; его папка сохранена: \(destination.path)")
        }
        load()
        throw TreeStoreError.treeFolderMissing
    }

    public func restoreFullBackup(_ item: RecoveryItem, to tree: FamilyTree) async throws -> SaveReceipt {
        guard item.kind == .migrationBackup,
              let gedcom = gedFile(in: item.url),
              FileManager.default.fileExists(atPath: gedcom.path) else {
            throw TreeStoreError.recoveryItemMissing
        }
        let beforeData = try JSONEncoder().encode(tree)
        _ = try createVerifiedBackup(for: tree, label: "pre-restore")
        do {
            let imported = try GEDCOMCodec.parse(gedcom)
            applySnapshot(imported.tree, to: tree)
            pendingBundleRestores[tree.id] = item.url
            return try persistTree(tree)
        } catch {
            pendingBundleRestores[tree.id] = nil
            if let before = try? JSONDecoder().decode(FamilyTree.self, from: beforeData) { applySnapshot(before, to: tree) }
            throw error
        }
    }

    public func restoreDeletedFile(
        _ item: RecoveryItem,
        to person: Person,
        in tree: FamilyTree,
        asPortrait: Bool
    ) async throws -> SaveReceipt {
        guard item.kind == .deletedFile, FileManager.default.fileExists(atPath: item.url.path) else {
            throw TreeStoreError.recoveryItemMissing
        }
        let beforeData = try JSONEncoder().encode(tree)
        var preparedForRollback: Attachment?
        do {
            if asPortrait {
                let data = try Data(contentsOf: item.url)
                let ext = item.url.pathExtension.isEmpty ? "jpg" : item.url.pathExtension
                person.photoFilename = "restored-\(UUID().uuidString).\(ext)"
                person.photoData = data
            } else {
                let components = item.displayName.components(separatedBy: "--Original--")
                let stored = components[0].components(separatedBy: "--Attachments--").last ?? item.displayName
                let original = components.count > 1 ? (decodedFilename(components[1]) ?? stored) : stored
                let prepared = try prepareAttachment(in: tree, sourceURL: item.url)
                preparedForRollback = prepared
                var renamed = prepared
                renamed.originalName = original
                person.attachments.append(renamed)
            }
            pendingTrashRemovals[tree.id, default: []].insert(item.url.lastPathComponent)
            return try persistTree(tree)
        } catch {
            if let preparedForRollback { discardPreparedAttachment(preparedForRollback, in: tree) }
            pendingTrashRemovals[tree.id] = nil
            if let before = try? JSONDecoder().decode(FamilyTree.self, from: beforeData) { applySnapshot(before, to: tree) }
            throw error
        }
    }

    private func recoveryItems(in folder: URL, kind: RecoveryItem.Kind) -> [RecoveryItem] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.contentModificationDateKey]
        ) else { return [] }
        return urls.map { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return RecoveryItem(kind: kind, url: url, createdAt: date, displayName: url.lastPathComponent)
        }
    }

    // MARK: - Save a specific tree to its .ged file

    public func save() {
        for tree in trees {
            _ = saveTree(tree)
        }
    }

    /// Source-compatibility bridge for older integrations. App workflows call the
    /// async throwing overload and react to its receipt.
    @discardableResult
    public func saveTree(_ tree: FamilyTree) -> SaveReceipt? {
        if legacyFileMap[tree.id] != nil {
            lastSaveError = L10n.tr("Сначала выполните безопасную миграцию этого дерева в разделе восстановления.")
            return nil
        }
        do {
            let receipt = try persistTree(tree)
            lastSaveError = nil
            return receipt
        } catch {
            log.error("Failed to save tree \(tree.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastSaveError = L10n.tr("Не удалось сохранить «\(tree.name)»: \(error.localizedDescription)")
            return nil
        }
    }

    public func saveTree(_ tree: FamilyTree) async throws -> SaveReceipt {
        do {
            if legacyFileMap[tree.id] != nil { throw TreeStoreError.migrationRequired }
            let receipt = try persistTree(tree)
            lastSaveError = nil
            return receipt
        } catch {
            log.error("Failed to save tree \(tree.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            lastSaveError = L10n.tr("Не удалось сохранить «\(tree.name)»: \(error.localizedDescription)")
            throw error
        }
    }

    private func persistTree(_ tree: FamilyTree) throws -> SaveReceipt {
        let fm = FileManager.default
        let generationID = UUID()
        let previousUpdatedAt = tree.updatedAt
        tree.updatedAt = Date()
        tree.schemaVersion = 2
        tree.reconcileParentLinks()
        tree.migrateLegacySources()

        if let mappedFolder = folderMap[tree.id], !fm.fileExists(atPath: mappedFolder.path) {
            throw TreeStoreError.treeFolderMissing
        }
        let current = folderMap[tree.id]
        let validation = TreeValidator.validate(tree, context: TreeValidationContext(
            acceptedBaselineIssueIDs: tree.acceptedBaselineIssueIDs,
            treeFolderURL: current
        ))
        let blocking = validation.filter(\.isBlocking)
        guard blocking.isEmpty else { throw TreeStoreError.validationFailed(issues: blocking) }
        let target = uniqueFolderURL(named: sanitizedFileName(tree.name), excluding: current)
        let staging = storageFolder.appendingPathComponent(".staging-\(generationID.uuidString)", isDirectory: true)
        var committed = false
        defer {
            if !committed { tree.updatedAt = previousUpdatedAt }
            if fm.fileExists(atPath: staging.path) { try? fm.removeItem(at: staging) }
        }

        if let current {
            try fm.copyItem(at: current, to: staging)
        } else {
            try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        }
        for directory in [
            staging.appendingPathComponent(Self.mediaName, isDirectory: true),
            staging.appendingPathComponent(Self.attachmentsName, isDirectory: true),
            staging.appendingPathComponent(Self.metadataName, isDirectory: true)
                .appendingPathComponent(Self.historyName, isDirectory: true),
            staging.appendingPathComponent(Self.metadataName, isDirectory: true)
                .appendingPathComponent(Self.trashName, isDirectory: true),
        ] {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        if let restore = pendingBundleRestores[tree.id] {
            try copyDirectoryContents(from: restore, to: staging)
        }

        let recoveryURL = try createPreMigrationBackupIfNeeded(tree: tree, currentFolder: current)
        if let current, let previousGEDCOM = gedFile(in: current) {
            try addHistoryRevision(previousGEDCOM, toStaging: staging)
        }
        try applyPendingImport(for: tree, to: staging)

        // Remove only working GEDCOM files from the staged copy. The verbatim import
        // copy is a protected safety artifact.
        if let files = try? fm.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension.lowercased() == "ged" && file.lastPathComponent != Self.originalImportName {
                try fm.removeItem(at: file)
            }
        }

        try restoreReferencedFilesFromTrash(tree: tree, in: staging)
        let serialized = try GEDCOMCodec.serialize(tree: tree, document: tree.gedcomDocument)
        let stagedGEDCOM = staging.appendingPathComponent("\(target.lastPathComponent).ged")
        try inject(.gedcomWrite)
        try serialized.gedcom.write(to: stagedGEDCOM, atomically: true, encoding: .utf8)
        let stagedMedia = staging.appendingPathComponent(Self.mediaName, isDirectory: true)
        try writePhotos(serialized.photos, to: stagedMedia)
        try applyPendingAttachments(for: tree, to: staging)
        let previousAttachmentNames: [String: String] = if let current, let previousGEDCOM = gedFile(in: current),
                                                           let previous = try? GEDCOMCodec.parse(previousGEDCOM) {
            Dictionary(uniqueKeysWithValues: previous.tree.people.flatMap(\.attachments).map { ($0.storedName, $0.originalName) })
        } else { [:] }
        try moveUnreferencedFilesToTrash(
            tree: tree,
            serializedPhotos: serialized.photos,
            originalAttachmentNames: previousAttachmentNames,
            in: staging
        )
        if let removals = pendingTrashRemovals[tree.id] {
            let trash = staging.appendingPathComponent(Self.metadataName, isDirectory: true)
                .appendingPathComponent(Self.trashName, isDirectory: true)
            for name in removals {
                let file = trash.appendingPathComponent(name)
                if fm.fileExists(atPath: file.path) { try fm.removeItem(at: file) }
            }
        }
        try pruneRecoveryData(in: staging)

        let activeHashes = try hashes(in: staging, includeRecoveryData: false)
        try writeManifest(generationID: generationID, hashes: activeHashes, in: staging)
        try verify(hashes: activeHashes, in: staging)

        var warnings: [String] = []
        try commitStaging(staging, replacing: current, at: target, warnings: &warnings)
        committed = true
        folderMap[tree.id] = target
        tree.acceptedBaselineIssueIDs.formIntersection(Set(validation.map(\.id)))

        let mediaFolder = target.appendingPathComponent(Self.mediaName, isDirectory: true)
        let newPhotoNames = Dictionary(uniqueKeysWithValues: serialized.photos.map { ($0.personID, $0.filename) })
        for person in tree.people {
            if person.photoFilename == nil, let filename = newPhotoNames[person.id] { person.photoFilename = filename }
            person.mediaFolderURL = mediaFolder
            person.photoIsDirty = false
        }
        pendingAttachmentDeletes[tree.id] = nil
        if let additions = pendingAttachmentAdds.removeValue(forKey: tree.id) {
            for addition in additions { try? fm.removeItem(at: addition.temporaryURL) }
        }
        pendingImports[tree.id] = nil
        pendingBundleRestores[tree.id] = nil
        pendingTrashRemovals[tree.id] = nil
        cleanupPendingFolderIfEmpty()

        return SaveReceipt(
            finalURL: target,
            generationID: generationID,
            fileCount: activeHashes.count,
            hashes: activeHashes,
            warnings: warnings,
            recoverySnapshotURL: recoveryURL
        )
    }

    /// Write only changed photos. Every failure is propagated to the transaction so
    /// the live tree remains untouched and dirty flags remain set.
    private func writePhotos(_ photos: [GEDCOMSerializer.Photo], to mediaFolder: URL) throws {
        guard !photos.isEmpty else { return }
        try inject(.portraitWrite)
        let fm = FileManager.default
        try fm.createDirectory(at: mediaFolder, withIntermediateDirectories: true)
        for photo in photos {
            let dest = mediaFolder.appendingPathComponent(photo.filename)
            // Skip if an identical file already exists (cheap size check, then bytes).
            if let attrs = try? fm.attributesOfItem(atPath: dest.path),
               let size = attrs[.size] as? Int, size == photo.data.count,
               let existing = try? Data(contentsOf: dest), existing == photo.data {
                continue
            }
            try photo.data.write(to: dest, options: .atomic)
        }
    }

    private struct BundleManifest: Codable {
        let generationID: UUID
        let createdAt: Date
        let hashes: [String: String]
    }

    private func createPreMigrationBackupIfNeeded(tree: FamilyTree, currentFolder: URL?) throws -> URL? {
        let fm = FileManager.default
        guard let currentFolder, let currentGEDCOM = gedFile(in: currentFolder),
              let content = try? String(contentsOf: currentGEDCOM, encoding: .utf8),
              !content.contains("1 _FTSVER 2") else { return nil }

        let treeRecovery = storageFolder
            .appendingPathComponent(Self.recoveryName, isDirectory: true)
            .appendingPathComponent(tree.id.uuidString, isDirectory: true)
        try fm.createDirectory(at: treeRecovery, withIntermediateDirectories: true)
        let existing = try fm.contentsOfDirectory(at: treeRecovery, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasSuffix("-pre-v2") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let first = existing.first { return first }

        let destination = treeRecovery.appendingPathComponent("\(timestamp())-pre-v2", isDirectory: true)
        do {
            try fm.copyItem(at: currentFolder, to: destination)
            let backupHashes = try hashes(in: destination, includeRecoveryData: false)
            try verify(hashes: backupHashes, in: destination)
            try writeManifest(generationID: UUID(), hashes: backupHashes, in: destination)
            return destination
        } catch {
            try? fm.removeItem(at: destination)
            throw error
        }
    }

    private func addHistoryRevision(_ sourceGEDCOM: URL, toStaging staging: URL) throws {
        let fm = FileManager.default
        let history = staging
            .appendingPathComponent(Self.metadataName, isDirectory: true)
            .appendingPathComponent(Self.historyName, isDirectory: true)
        try fm.createDirectory(at: history, withIntermediateDirectories: true)
        let destination = uniqueURL(history.appendingPathComponent("\(timestamp()).ged"))
        let sourceHash = try sha256(sourceGEDCOM)
        let latest = try fm.contentsOfDirectory(at: history, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "ged" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
            .first
        if let latest, try sha256(latest) == sourceHash { return }
        try fm.copyItem(at: sourceGEDCOM, to: destination)
    }

    private func applyPendingImport(for tree: FamilyTree, to staging: URL) throws {
        guard let pending = pendingImports[tree.id] else { return }
        let fm = FileManager.default
        let originalDestination = staging.appendingPathComponent(Self.originalImportName)
        try inject(.originalImportCopy)
        if fm.fileExists(atPath: originalDestination.path) { try fm.removeItem(at: originalDestination) }
        try fm.copyItem(at: pending.originalGEDCOM, to: originalDestination)
        guard try sha256(pending.originalGEDCOM) == sha256(originalDestination) else {
            throw TreeStoreError.verificationFailed(path: Self.originalImportName)
        }
        if fm.fileExists(atPath: pending.mediaFolder.path) {
            try copyDirectoryContents(
                from: pending.mediaFolder,
                to: staging.appendingPathComponent(Self.mediaName, isDirectory: true)
            )
        }
        if fm.fileExists(atPath: pending.attachmentsFolder.path) {
            try copyDirectoryContents(
                from: pending.attachmentsFolder,
                to: staging.appendingPathComponent(Self.attachmentsName, isDirectory: true)
            )
        }
    }

    private func applyPendingAttachments(for tree: FamilyTree, to staging: URL) throws {
        guard let additions = pendingAttachmentAdds[tree.id], !additions.isEmpty else { return }
        let folder = staging.appendingPathComponent(Self.attachmentsName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for addition in additions {
            let destination = folder.appendingPathComponent(addition.storedName)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: addition.temporaryURL, to: destination)
            guard try sha256(addition.temporaryURL) == sha256(destination) else {
                throw TreeStoreError.verificationFailed(path: "Attachments/\(addition.storedName)")
            }
        }
    }

    private func restoreReferencedFilesFromTrash(tree: FamilyTree, in staging: URL) throws {
        let attachmentNames = Set(tree.people.flatMap(\.attachments).map(\.storedName))
        let photoNames = Set(tree.people.compactMap(\.photoFilename))
        try restore(names: attachmentNames, category: Self.attachmentsName, in: staging)
        try restore(names: photoNames, category: Self.mediaName, in: staging)
    }

    private func restore(names: Set<String>, category: String, in staging: URL) throws {
        guard !names.isEmpty else { return }
        let fm = FileManager.default
        let activeFolder = staging.appendingPathComponent(category, isDirectory: true)
        let trash = staging
            .appendingPathComponent(Self.metadataName, isDirectory: true)
            .appendingPathComponent(Self.trashName, isDirectory: true)
        guard fm.fileExists(atPath: trash.path) else { return }
        let trashFiles = try fm.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil)
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for name in names {
            let active = activeFolder.appendingPathComponent(name)
            guard !fm.fileExists(atPath: active.path),
                  let recovery = trashFiles.first(where: { $0.lastPathComponent.contains("--\(category)--\(name)") }) else { continue }
            try fm.createDirectory(at: activeFolder, withIntermediateDirectories: true)
            try fm.moveItem(at: recovery, to: active)
        }
    }

    private func moveUnreferencedFilesToTrash(
        tree: FamilyTree,
        serializedPhotos: [GEDCOMSerializer.Photo],
        originalAttachmentNames: [String: String],
        in staging: URL
    ) throws {
        let attachmentNames = Set(tree.people.flatMap(\.attachments).map(\.storedName))
        let photoNames = Set(tree.people.compactMap(\.photoFilename))
            .union(serializedPhotos.map(\.filename))
        try moveUnreferenced(
            in: Self.attachmentsName,
            expected: attachmentNames,
            originalNames: originalAttachmentNames,
            staging: staging
        )
        try moveUnreferenced(in: Self.mediaName, expected: photoNames, originalNames: [:], staging: staging)
    }

    private func moveUnreferenced(
        in category: String,
        expected: Set<String>,
        originalNames: [String: String],
        staging: URL
    ) throws {
        let fm = FileManager.default
        let active = staging.appendingPathComponent(category, isDirectory: true)
        guard fm.fileExists(atPath: active.path) else { return }
        let trash = staging
            .appendingPathComponent(Self.metadataName, isDirectory: true)
            .appendingPathComponent(Self.trashName, isDirectory: true)
        let files = try fm.contentsOfDirectory(at: active, includingPropertiesForKeys: [.isRegularFileKey])
        for file in files where !expected.contains(file.lastPathComponent) && !file.lastPathComponent.hasPrefix(".") {
            try fm.createDirectory(at: trash, withIntermediateDirectories: true)
            var base = "\(timestamp())--\(category)--\(file.lastPathComponent)"
            if let original = originalNames[file.lastPathComponent] {
                base += "--Original--\(encodedFilename(original))"
            }
            let destination = uniqueURL(trash.appendingPathComponent(base))
            try fm.moveItem(at: file, to: destination)
        }
    }

    private func pruneRecoveryData(in staging: URL) throws {
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
                let date = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantFuture
                if date < cutoff { try fm.removeItem(at: file) }
            }
        }
    }

    private func writeManifest(generationID: UUID, hashes: [String: String], in folder: URL) throws {
        let metadata = folder.appendingPathComponent(Self.metadataName, isDirectory: true)
        try FileManager.default.createDirectory(at: metadata, withIntermediateDirectories: true)
        let manifest = BundleManifest(generationID: generationID, createdAt: Date(), hashes: hashes)
        let data = try JSONEncoder.pretty.encode(manifest)
        try data.write(to: metadata.appendingPathComponent(Self.manifestName), options: .atomic)
    }

    private func hashes(in folder: URL, includeRecoveryData: Bool) throws -> [String: String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsPackageDescendants]
        ) else { throw TreeStoreError.treeFolderMissing }

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
            result[relative] = try sha256(file)
        }
        return result
    }

    private func verify(hashes expected: [String: String], in folder: URL) throws {
        let actual = try hashes(in: folder, includeRecoveryData: false)
        for (path, digest) in expected where actual[path] != digest {
            throw TreeStoreError.verificationFailed(path: path)
        }
        guard Set(actual.keys) == Set(expected.keys) else {
            let path = Set(actual.keys).symmetricDifference(Set(expected.keys)).sorted().first ?? folder.path
            throw TreeStoreError.verificationFailed(path: path)
        }
    }

    private func commitStaging(
        _ staging: URL,
        replacing current: URL?,
        at target: URL,
        warnings: inout [String]
    ) throws {
        let fm = FileManager.default
        try inject(.directorySwap)
        guard let current, fm.fileExists(atPath: current.path) else {
            try fm.moveItem(at: staging, to: target)
            return
        }

        let rollback = storageFolder.appendingPathComponent(".rollback-\(UUID().uuidString)", isDirectory: true)
        try fm.moveItem(at: current, to: rollback)
        do {
            try fm.moveItem(at: staging, to: target)
        } catch {
            try? fm.moveItem(at: rollback, to: current)
            throw TreeStoreError.commitFailed(reason: error.localizedDescription)
        }
        do {
            try fm.removeItem(at: rollback)
        } catch {
            warnings.append(L10n.tr("Старая резервная папка не удалена: \(rollback.lastPathComponent)"))
        }
    }

    private func copyDirectoryContents(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for item in try fm.contentsOfDirectory(at: source, includingPropertiesForKeys: [.isDirectoryKey]) {
            let target = destination.appendingPathComponent(item.lastPathComponent)
            let isDirectory = try item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            if isDirectory {
                try copyDirectoryContents(from: item, to: target)
            } else {
                if fm.fileExists(atPath: target.path) { try fm.removeItem(at: target) }
                try fm.copyItem(at: item, to: target)
            }
        }
    }

    private func sha256(_ url: URL) throws -> String {
        let digest = try SHA256.hash(data: Data(contentsOf: url))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: Date())
    }

    private func encodedFilename(_ value: String) -> String {
        Data(value.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
    }

    private func decodedFilename(_ value: String) -> String? {
        var base64 = value.replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "-", with: "+")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func inject(_ point: PersistenceFaultPoint) throws {
        try faultInjector?(point)
    }

    private func cleanupPendingFolderIfEmpty() {
        let folder = storageFolder.appendingPathComponent(Self.pendingName, isDirectory: true)
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
              items.isEmpty else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    public func addTree(_ tree: FamilyTree) {
        guard saveTree(tree) != nil else { return }
        if !trees.contains(where: { $0.id == tree.id }) { trees.append(tree) }
    }

    public func addTreeVerified(_ tree: FamilyTree) async throws -> SaveReceipt {
        let receipt = try await saveTree(tree)
        if !trees.contains(where: { $0.id == tree.id }) { trees.append(tree) }
        return receipt
    }

    @discardableResult
    public func deleteTree(_ tree: FamilyTree) -> Bool {
        let source = folder(for: tree)
        do {
            var trashed: NSURL?
            try FileManager.default.trashItem(at: source, resultingItemURL: &trashed)
            trees.removeAll(where: { $0.id == tree.id })
            folderMap.removeValue(forKey: tree.id)
            return true
        } catch {
            lastSaveError = L10n.tr("Не удалось переместить «\(tree.name)» в Корзину: \(error.localizedDescription)")
            return false
        }
    }

    /// Rename a tree's title and subtitle, then persist to its .ged file.
    public func renameTree(_ tree: FamilyTree, name: String, subtitle: String?) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        tree.name = trimmedName
        let trimmedSub = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        tree.subtitle = (trimmedSub?.isEmpty ?? true) ? nil : trimmedSub
        _ = saveTree(tree)
    }

    public func renameTreeVerified(_ tree: FamilyTree, name: String, subtitle: String?) async throws -> SaveReceipt {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { throw TreeStoreError.commitFailed(reason: L10n.tr("Название не может быть пустым.")) }
        let previousName = tree.name
        let previousSubtitle = tree.subtitle
        tree.name = trimmedName
        let trimmedSub = subtitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        tree.subtitle = (trimmedSub?.isEmpty ?? true) ? nil : trimmedSub
        do {
            return try await saveTree(tree)
        } catch {
            tree.name = previousName
            tree.subtitle = previousSubtitle
            throw error
        }
    }

    /// Remove a tree from the library but keep its files: the whole tree folder is
    /// moved into `Archived/`, which `load()` ignores. Returns the moved folder URL
    /// to reveal in Finder.
    @discardableResult
    public func archiveTree(_ tree: FamilyTree) -> URL {
        let fm = FileManager.default
        let archiveFolder = storageFolder.appendingPathComponent(Self.archivedName, isDirectory: true)
        let src = folder(for: tree)
        let dest = uniqueURL(archiveFolder.appendingPathComponent(sanitizedFileName(tree.name), isDirectory: true), isDirectory: true)
        do {
            try fm.createDirectory(at: archiveFolder, withIntermediateDirectories: true)
            try fm.moveItem(at: src, to: dest)
            folderMap.removeValue(forKey: tree.id)
            trees.removeAll { $0.id == tree.id }
        } catch {
            lastSaveError = L10n.tr("Не удалось архивировать «\(tree.name)»: \(error.localizedDescription)")
            return src
        }
        return dest
    }

    /// Export a faithful copy of a tree (.ged + photos + attachments) into a `<name>/`
    /// bundle inside the chosen directory, so it can be re-imported later. Does not
    /// remove the tree — the caller decides whether to follow with `deleteTree`.
    /// Returns the bundle URL.
    @discardableResult
    public func exportTree(_ tree: FamilyTree, toDirectory directory: URL) throws -> URL {
        try exportTreeVerified(tree, toDirectory: directory).finalURL
    }

    public func exportTree(_ tree: FamilyTree, to directory: URL) async throws -> ExportReceipt {
        try exportTreeVerified(tree, toDirectory: directory)
    }

    private func exportTreeVerified(_ tree: FamilyTree, toDirectory directory: URL) throws -> ExportReceipt {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder(for: tree).path) else { throw TreeStoreError.treeFolderMissing }
        let name = sanitizedFileName(tree.name)
        let bundle = uniqueURL(directory.appendingPathComponent(name, isDirectory: true), isDirectory: true)
        let generationID = UUID()
        let staging = directory.appendingPathComponent(".export-\(generationID.uuidString)", isDirectory: true)
        defer { if fm.fileExists(atPath: staging.path) { try? fm.removeItem(at: staging) } }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        let srcFolder = folder(for: tree)

        // The committed GEDCOM and active file folders are copied without private
        // revision history or deleted-file Trash.
        let gedDest = staging.appendingPathComponent("\(bundle.lastPathComponent).ged")
        if let gedSrc = gedFile(in: srcFolder), fm.fileExists(atPath: gedSrc.path) {
            try inject(.exportCopy)
            try fm.copyItem(at: gedSrc, to: gedDest)
        } else {
            let result = try GEDCOMCodec.serialize(tree: tree, document: tree.gedcomDocument)
            try result.gedcom.write(to: gedDest, atomically: true, encoding: .utf8)
            try writePhotos(result.photos, to: staging.appendingPathComponent(Self.mediaName))
        }

        for sub in [Self.mediaName, Self.attachmentsName] {
            let src = srcFolder.appendingPathComponent(sub, isDirectory: true)
            if fm.fileExists(atPath: src.path) {
                let destination = staging.appendingPathComponent(sub, isDirectory: true)
                if fm.fileExists(atPath: destination.path) { try copyDirectoryContents(from: src, to: destination) }
                else { try fm.copyItem(at: src, to: destination) }
            }
        }
        let original = srcFolder.appendingPathComponent(Self.originalImportName)
        if fm.fileExists(atPath: original.path) {
            try fm.copyItem(at: original, to: staging.appendingPathComponent(Self.originalImportName))
        }
        let exportHashes = try hashes(in: staging, includeRecoveryData: false)
        try writeManifest(generationID: generationID, hashes: exportHashes, in: staging)
        try verify(hashes: exportHashes, in: staging)
        try fm.moveItem(at: staging, to: bundle)
        return SaveReceipt(
            finalURL: bundle,
            generationID: generationID,
            fileCount: exportHashes.count,
            hashes: exportHashes
        )
    }

    // MARK: - Import external .ged file

    /// Resolve what the user picked into the GEDCOM to read. An exported archive is a
    /// *folder* — its .ged sits beside Media/ and Attachments/ — and picking that folder
    /// is what grants access to the siblings, because the file picker grants access to
    /// the selected item alone. Files are returned unchanged.
    public func resolveImportSource(_ selection: URL) throws -> URL {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: selection.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return selection
        }
        let candidates = try fm.contentsOfDirectory(at: selection, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension.lowercased() == "ged" && $0.lastPathComponent != Self.originalImportName }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if candidates.count == 1 { return candidates[0] }
        // An exported bundle names its GEDCOM after the folder, which settles the case
        // where the user kept several .ged files side by side.
        if let named = candidates.first(where: { $0.deletingPathExtension().lastPathComponent == selection.lastPathComponent }) {
            return named
        }
        if candidates.isEmpty { throw TreeStoreError.noGEDCOMInFolder(folder: selection.lastPathComponent) }
        throw TreeStoreError.ambiguousGEDCOMInFolder(folder: selection.lastPathComponent)
    }

    /// Copy an external GEDCOM and its sibling media folders into private temporary
    /// storage before previewing it. The original is never edited in place.
    ///
    /// Only the GEDCOM itself is required. A sibling folder that cannot be read — the
    /// file picker grants access to the selected item, not to its neighbours — is
    /// reported through `stagedImportDiagnostics(for:)` and leaves the import standing,
    /// because a tree without its photos is worth far more than no tree at all.
    public func prepareImportPreview(from source: URL) throws -> URL {
        let fm = FileManager.default
        let root = storageFolder.appendingPathComponent(Self.pendingName, isDirectory: true)
            .appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        do {
            let destination = root.appendingPathComponent(source.lastPathComponent)
            try fm.copyItem(at: source, to: destination)
            guard try sha256(source) == sha256(destination) else {
                throw TreeStoreError.verificationFailed(path: source.lastPathComponent)
            }
            let base = source.deletingLastPathComponent()
            var diagnostics: [ImportDiagnostic] = []
            for name in [Self.mediaName, Self.attachmentsName] {
                let sibling = base.appendingPathComponent(name, isDirectory: true)
                guard fm.fileExists(atPath: sibling.path) else { continue }
                do {
                    try fm.copyItem(at: sibling, to: root.appendingPathComponent(name, isDirectory: true))
                } catch {
                    diagnostics.append(ImportDiagnostic(
                        id: "import.sibling-unreadable.\(name)",
                        severity: .warning,
                        message: L10n.tr(
                            "Папку «\(name)» рядом с файлом прочитать не удалось, дерево импортируется без неё. Выберите папку архива целиком, чтобы macOS дала доступ к вложенным файлам: \(error.localizedDescription)"
                        )
                    ))
                }
            }
            pendingImportDiagnostics[destination.standardizedFileURL.path] = diagnostics
            return destination
        } catch {
            try? fm.removeItem(at: root)
            throw error
        }
    }

    /// What could not be staged alongside a previewed GEDCOM. Empty when everything the
    /// archive carried came across.
    public func stagedImportDiagnostics(for gedcom: URL) -> [ImportDiagnostic] {
        pendingImportDiagnostics[gedcom.standardizedFileURL.path] ?? []
    }

    public func discardImportPreview(at gedcom: URL) {
        let pendingRoot = storageFolder.appendingPathComponent(Self.pendingName, isDirectory: true).standardizedFileURL
        let folder = gedcom.deletingLastPathComponent().standardizedFileURL
        guard folder.path.hasPrefix(pendingRoot.path + "/") else { return }
        pendingImportDiagnostics[gedcom.standardizedFileURL.path] = nil
        try? FileManager.default.removeItem(at: folder)
        cleanupPendingFolderIfEmpty()
    }

    public func importGEDCOM(from url: URL) throws -> FamilyTree {
        try importGEDCOMVerified(from: url).tree
    }

    public func importGEDCOM(from url: URL) async throws -> ImportResult {
        try importGEDCOMVerified(from: url)
    }

    private func importGEDCOMVerified(from url: URL) throws -> ImportResult {
        var result = try GEDCOMCodec.parse(url)
        guard result.report.blockingErrors.isEmpty else { throw TreeStoreError.invalidImport(report: result.report) }
        // Anything the staging step could not bring across belongs in the tree's own
        // permanent import report, not only in the preview the user already dismissed.
        result.report.diagnostics.append(contentsOf: stagedImportDiagnostics(for: url))
        let tree = result.tree
        if trees.contains(where: { $0.id == tree.id }) {
            tree.id = UUID()
            result.report.diagnostics.append(ImportDiagnostic(
                id: "import.duplicate-tree-id",
                severity: .warning,
                message: L10n.tr("Идентификатор уже существовал в библиотеке; импортированной копии назначен новый.")
            ))
        }
        let importedIssues = TreeValidator.validate(tree)
        tree.acceptedBaselineIssueIDs = Set(importedIssues.filter { $0.severity == .error }.map(\.id))
        for issue in importedIssues where issue.severity == .error {
            result.report.diagnostics.append(ImportDiagnostic(
                id: "import.validation.\(issue.id)",
                severity: .warning,
                message: L10n.tr("Импортированная проблема сохранена для проверки: \(issue.message)")
            ))
        }
        tree.importReport = result.report
        let base = url.deletingLastPathComponent()
        pendingImports[tree.id] = PendingImport(
            originalGEDCOM: url,
            mediaFolder: base.appendingPathComponent(Self.mediaName, isDirectory: true),
            attachmentsFolder: base.appendingPathComponent(Self.attachmentsName, isDirectory: true)
        )
        do {
            _ = try persistTree(tree)
            if !trees.contains(where: { $0.id == tree.id }) { trees.append(tree) }
            return result
        } catch {
            pendingImports[tree.id] = nil
            throw error
        }
    }

    /// Re-point every person's lazy portrait loader at the tree's Media/ folder. Undo/redo
    /// swaps in freshly-decoded Person instances (which carry the photo *filename* but not
    /// the transient folder URL), so call this after a restore to keep portraits loadable.
    public func refreshMediaFolders(for tree: FamilyTree) {
        let mediaFolder = legacyFileMap[tree.id].map {
            storageFolder.appendingPathComponent("Media_\($0.deletingPathExtension().lastPathComponent)", isDirectory: true)
        } ?? folder(for: tree).appendingPathComponent(Self.mediaName, isDirectory: true)
        for person in tree.people { person.mediaFolderURL = mediaFolder }
    }

    private func applySnapshot(_ snapshot: FamilyTree, to tree: FamilyTree) {
        tree.applyContent(of: snapshot)
        refreshMediaFolders(for: tree)
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

    /// Copy a security-scoped file into the private pending area without touching the
    /// live tree bundle. Editors append the returned metadata to their draft and the
    /// next successful save commits the bytes.
    public func prepareAttachment(in tree: FamilyTree, sourceURL: URL) throws -> Attachment {
        let fm = FileManager.default
        let pendingFolder = storageFolder.appendingPathComponent(Self.pendingName, isDirectory: true)
        try fm.createDirectory(at: pendingFolder, withIntermediateDirectories: true)
        let originalName = sourceURL.lastPathComponent
        let ext = sourceURL.pathExtension
        let storedName = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
        let temporary = pendingFolder.appendingPathComponent(storedName)
        let scoped = sourceURL.startAccessingSecurityScopedResource()
        defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
        try fm.copyItem(at: sourceURL, to: temporary)
        pendingAttachmentAdds[tree.id, default: []].append(PendingAttachment(temporaryURL: temporary, storedName: storedName))
        return Attachment(storedName: storedName, originalName: originalName)
    }

    /// Async UI path: copy large bytes away from the main actor, then register the
    /// completed private staging file in one short state mutation.
    @MainActor
    public func prepareAttachmentAsync(in tree: FamilyTree, sourceURL: URL) async throws -> Attachment {
        try Task.checkCancellation()
        let pendingFolder = storageFolder.appendingPathComponent(Self.pendingName, isDirectory: true)
        let treeID = tree.id
        let copy = Task.detached(priority: .userInitiated) {
            let fm = FileManager.default
            try fm.createDirectory(at: pendingFolder, withIntermediateDirectories: true)
            let originalName = sourceURL.lastPathComponent
            let ext = sourceURL.pathExtension
            let storedName = ext.isEmpty ? UUID().uuidString : "\(UUID().uuidString).\(ext)"
            let temporary = pendingFolder.appendingPathComponent(storedName)
            let scoped = sourceURL.startAccessingSecurityScopedResource()
            defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
            do {
                try Task.checkCancellation()
                try fm.copyItem(at: sourceURL, to: temporary)
                try Task.checkCancellation()
                return (temporary, storedName, originalName)
            } catch {
                try? fm.removeItem(at: temporary)
                throw error
            }
        }
        let prepared = try await withTaskCancellationHandler {
            try await copy.value
        } onCancel: {
            copy.cancel()
        }
        do {
            try Task.checkCancellation()
        } catch {
            try? FileManager.default.removeItem(at: prepared.0)
            throw error
        }
        pendingAttachmentAdds[treeID, default: []].append(PendingAttachment(
            temporaryURL: prepared.0,
            storedName: prepared.1
        ))
        return Attachment(storedName: prepared.1, originalName: prepared.2)
    }

    public func discardPreparedAttachment(_ attachment: Attachment, in tree: FamilyTree) {
        guard let pending = pendingAttachmentAdds[tree.id]?.first(where: { $0.storedName == attachment.storedName }) else { return }
        pendingAttachmentAdds[tree.id]?.removeAll { $0.storedName == attachment.storedName }
        try? FileManager.default.removeItem(at: pending.temporaryURL)
        cleanupPendingFolderIfEmpty()
    }

    public func previewURL(for attachment: Attachment, in tree: FamilyTree) -> URL {
        if let pending = pendingAttachmentAdds[tree.id]?.first(where: { $0.storedName == attachment.storedName }) {
            return pending.temporaryURL
        }
        return attachmentURL(attachment, in: tree)
    }

    /// Remove an attachment's file from disk, unlink it from the person, and persist.
    public func removeAttachment(_ attachment: Attachment, from person: Person, in tree: FamilyTree) {
        let originalIndex = person.attachments.firstIndex(where: { $0.id == attachment.id })
        person.attachments.removeAll { $0.id == attachment.id }
        pendingAttachmentDeletes[tree.id, default: []].insert(attachment.storedName)
        person.updatedAt = Date()
        if saveTree(tree) == nil {
            if let originalIndex { person.attachments.insert(attachment, at: min(originalIndex, person.attachments.count)) }
            pendingAttachmentDeletes[tree.id]?.remove(attachment.storedName)
        }
    }

    /// Delete every attachment file belonging to a person (used when the person is
    /// removed). Does not persist — the caller saves the tree afterward.
    public func deleteAttachmentFiles(of person: Person, in tree: FamilyTree) {
        pendingAttachmentDeletes[tree.id, default: []].formUnion(person.attachments.map(\.storedName))
    }

    // MARK: - Helpers

    /// Public access to the tree's .ged file (e.g. for "Reveal in Finder"); falls back
    /// to the folder itself if the file can't be located.
    public func gedFileURL(for tree: FamilyTree) -> URL {
        if let legacy = legacyFileMap[tree.id] { return legacy }
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
        return cleaned.isEmpty ? L10n.tr("Дерево") : cleaned
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

}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
