import Foundation

/// Import and export. Everything that only moves, zips or hashes files runs off the main
/// actor: `TreeStore` is main-actor isolated and its methods never suspend, so doing it
/// inline froze the window for as long as a large archive took. What touches the live
/// tree — serializing it, registering the result — stays on the main actor.
public extension TreeStore {

    // MARK: - Export

    /// Everything an export needs once the tree has been read: plain values only, so the
    /// file work can leave the main actor.
    internal struct ExportJob: Sendable {
        let sourceFolder: URL
        let directory: URL
        let name: String
        let packaging: TreeExportPackaging
        /// The committed .ged to copy, or nil when `serialized` replaces it.
        let committedGEDCOM: URL?
        let serialized: SerializedTree?
        /// Per folder, the only files that may travel; nil copies the folder whole.
        let keptFiles: [String: Set<String>]?
        let includesOriginalImport: Bool
    }

    /// Export a faithful copy of a tree (.ged + photos + attachments) into a `<name>/`
    /// bundle inside the chosen directory, so it can be re-imported later. Does not
    /// remove the tree — the caller decides whether to follow with `deleteTree`.
    ///
    /// `hidingLivingPeople` exports `tree.redactingLivingPeople()` instead, and carries
    /// only the files the redacted tree still references.
    /// `version: nil` exports the tree in whatever specification it is already stored
    /// in. GEDZIP overrides that: it is defined only by GEDCOM 7.0, so a `.gdz` always
    /// carries 7.0 whatever the caller asked for.
    func exportTree(
        _ tree: FamilyTree,
        to directory: URL,
        hidingLivingPeople: Bool = false,
        version: GEDCOMVersion? = nil,
        packaging: TreeExportPackaging = .gedzip
    ) async throws -> SaveReceipt {
        let version = packaging == .gedzip ? .v70 : (version ?? tree.sourceVersion)
        let sourceFolder = folder(for: tree)
        guard FileManager.default.fileExists(atPath: sourceFolder.path) else { throw TreeStoreError.treeFolderMissing }

        // A privacy export is re-serialized from the redacted tree even when a committed
        // .ged is sitting right there: copying that file is a byte-for-byte copy of the
        // data the export exists to remove. `document: nil` for the same reason — the
        // imported syntax tree carries foreign records through untouched.
        // Exporting into another specification rules out the copy for the same reason:
        // the committed file is written in the version the tree is stored in.
        let exported = hidingLivingPeople ? tree.redactingLivingPeople() : tree
        let reserializes = hidingLivingPeople || version != tree.sourceVersion
        var committedGEDCOM: URL?
        var serialized: SerializedTree?
        if let gedSource = gedFile(in: sourceFolder), !reserializes {
            try inject(.exportCopy)
            committedGEDCOM = gedSource
        } else {
            // ponytail: serialization reads the live tree, so it stays on the main
            // actor — about a second for 20,000 people. Off it needs a snapshot.
            serialized = try GEDCOMCodec.serialize(
                tree: exported,
                document: hidingLivingPeople ? nil : tree.gedcomDocument,
                options: .init(version: version)
            )
        }

        // In a privacy export only the files the redacted tree still names travel; a
        // living person's portrait and attachments are their personal data as much as
        // their birth date is.
        let keptFiles: [String: Set<String>]? = hidingLivingPeople ? [
            Self.mediaName: Set(exported.people.compactMap(\.photoFilename)),
            Self.attachmentsName: Set(exported.people.flatMap(\.attachments).map(\.storedName)),
        ] : nil
        let job = ExportJob(
            sourceFolder: sourceFolder,
            directory: directory,
            name: FileNaming.sanitizedFileName(tree.name),
            packaging: packaging,
            committedGEDCOM: committedGEDCOM,
            serialized: serialized,
            keptFiles: keptFiles,
            // The untouched import is the pre-redaction file itself.
            includesOriginalImport: !hidingLivingPeople
        )
        let faults = faultInjector
        return try await Task.detached(priority: .userInitiated) {
            try self.writeExport(job, faults: faults)
        }.value
    }

    /// The file half of an export. Copies without private revision history or Trash.
    internal nonisolated func writeExport(_ job: ExportJob, faults: (@Sendable (PersistenceFaultPoint) throws -> Void)?) throws -> SaveReceipt {
        let fm = FileManager.default
        let bundle = FileNaming.uniqueURL(job.directory.appendingPathComponent(job.name, isDirectory: true), isDirectory: true)
        let generationID = UUID()
        let staging = job.directory.appendingPathComponent(".export-\(generationID.uuidString)", isDirectory: true)
        defer { if fm.fileExists(atPath: staging.path) { try? fm.removeItem(at: staging) } }
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)

        let gedDestination = staging.appendingPathComponent(
            job.packaging == .gedzip ? GEDZIPArchive.gedcomEntryName : "\(bundle.lastPathComponent).ged"
        )
        if let committed = job.committedGEDCOM {
            try fm.copyItem(at: committed, to: gedDestination)
        } else if let serialized = job.serialized {
            try serialized.gedcom.write(to: gedDestination, atomically: true, encoding: .utf8)
            try Self.writePhotoFiles(serialized.photos, to: staging.appendingPathComponent(Self.mediaName))
        }
        for sub in [Self.mediaName, Self.attachmentsName] {
            let source = job.sourceFolder.appendingPathComponent(sub, isDirectory: true)
            if fm.fileExists(atPath: source.path) {
                let destination = staging.appendingPathComponent(sub, isDirectory: true)
                try copyDirectoryContents(from: source, to: destination, keepingOnly: job.keptFiles?[sub])
            }
        }
        let original = job.sourceFolder.appendingPathComponent(Self.originalImportName)
        if job.includesOriginalImport, fm.fileExists(atPath: original.path) {
            try fm.copyItem(at: original, to: staging.appendingPathComponent(Self.originalImportName))
        }

        if job.packaging == .gedzip {
            return try packageAsGEDZIP(
                staging: staging,
                directory: job.directory,
                name: job.name,
                generationID: generationID,
                faults: faults
            )
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

    /// Zip a staged export into one `.gdz`, keeping Swarm's own bookkeeping in a sidecar
    /// so the archive stays spec-clean.
    ///
    /// Verification is stronger here than for a folder: the written archive is extracted
    /// again and re-hashed, so the receipt attests that the file reads back — not merely
    /// that the staging folder was correct before it was zipped. Both files are built
    /// under hidden names and the archive takes its final name last, so a failure never
    /// leaves a `.gdz` that looks like a finished export.
    private nonisolated func packageAsGEDZIP(
        staging: URL,
        directory: URL,
        name: String,
        generationID: UUID,
        faults: (@Sendable (PersistenceFaultPoint) throws -> Void)?
    ) throws -> SaveReceipt {
        let fm = FileManager.default
        let (archive, sidecar) = FileNaming.uniqueGEDZIPPair(in: directory, name: name)
        let tempArchive = directory.appendingPathComponent(".export-\(generationID.uuidString).gdz")
        let tempSidecar = directory.appendingPathComponent(".sidecar-\(generationID.uuidString)", isDirectory: true)
        let readback = directory.appendingPathComponent(".verify-\(generationID.uuidString)", isDirectory: true)
        defer { for temp in [tempArchive, tempSidecar, readback] { try? fm.removeItem(at: temp) } }
        // The verbatim import leaves before hashing, so the manifest describes exactly
        // what ends up inside the archive.
        try GEDZIPArchive.moveAside([staging.appendingPathComponent(Self.originalImportName)], to: tempSidecar)
        let exportHashes = try hashes(in: staging, includeRecoveryData: false)
        try GEDZIPArchive.write(contentsOf: staging, to: tempArchive)

        try faults?(.gedzipReadback)
        try GEDZIPArchive.extract(tempArchive, to: readback)
        try verify(hashes: exportHashes, in: readback)

        try fm.createDirectory(at: tempSidecar, withIntermediateDirectories: true)
        let manifest = BundleManifest(generationID: generationID, createdAt: Date(), hashes: exportHashes)
        try JSONEncoder.pretty.encode(manifest).write(
            to: tempSidecar.appendingPathComponent(Self.manifestName),
            options: .atomic
        )
        try faults?(.gedzipFinalize)
        try fm.moveItem(at: tempSidecar, to: sidecar)
        do {
            try fm.moveItem(at: tempArchive, to: archive)
        } catch {
            try? fm.removeItem(at: sidecar)
            throw error
        }
        return SaveReceipt(
            finalURL: archive,
            generationID: generationID,
            fileCount: exportHashes.count,
            hashes: exportHashes
        )
    }

    // MARK: - Staging an import

    private var pendingFolderURL: URL {
        storageFolderURL.appendingPathComponent(Self.pendingName, isDirectory: true)
    }

    /// Turn what the user picked — a .ged, an exported folder or a .gdz — into a private
    /// staged copy ready to preview, import or merge. Discard it with
    /// `discardImportPreview(at:)`.
    func stageImport(from selection: URL) throws -> URL {
        try register(stageFiles(from: selection, pending: pendingFolderURL))
    }

    /// `stageImport` with the copying, unzipping and hashing off the main actor. The
    /// caller keeps any security-scoped access open until this returns.
    func stageImportAsync(from selection: URL) async throws -> URL {
        let pending = pendingFolderURL
        let staged = try await Task.detached(priority: .userInitiated) {
            try self.stageFiles(from: selection, pending: pending)
        }.value
        return register(staged)
    }

    private func register(_ staged: (gedcom: URL, diagnostics: [ImportDiagnostic])) -> URL {
        pendingImportDiagnostics[staged.gedcom.standardizedFileURL.path] = staged.diagnostics
        return staged.gedcom
    }

    /// A GEDZIP is the folder case wearing a different coat: it is unpacked into the
    /// private area, staged by the folder rules, and the unpacked copy removed on every
    /// path — staging has already copied everything the import needs out of it.
    private nonisolated func stageFiles(from selection: URL, pending: URL) throws -> (gedcom: URL, diagnostics: [ImportDiagnostic]) {
        guard GEDZIPArchive.isArchive(selection) else {
            return try copyIntoPending(resolveImportSource(selection), pending: pending)
        }
        let fm = FileManager.default
        let unpacked = pending.appendingPathComponent("Unpacked-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? fm.removeItem(at: unpacked)
            Self.removeIfEmpty(pending)
        }
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        try GEDZIPArchive.extract(selection, to: unpacked)
        let gedcom = unpacked.appendingPathComponent(GEDZIPArchive.gedcomEntryName)
        do {
            // The spec names the archive's GEDCOM; any other lone .ged is accepted too.
            let source = fm.fileExists(atPath: gedcom.path) ? gedcom : try resolveImportSource(unpacked)
            return try copyIntoPending(source, pending: pending)
        } catch TreeStoreError.noGEDCOMInFolder, TreeStoreError.ambiguousGEDCOMInFolder {
            throw TreeStoreError.invalidGEDZIP(archive: selection.lastPathComponent)
        }
    }

    /// Resolve what the user picked into the GEDCOM to read. An exported archive is a
    /// *folder* — its .ged sits beside Media/ and Attachments/ — and picking that folder
    /// is what grants access to the siblings, because the file picker grants access to
    /// the selected item alone. Files are returned unchanged.
    nonisolated func resolveImportSource(_ selection: URL) throws -> URL {
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
    func prepareImportPreview(from source: URL) throws -> URL {
        try register(copyIntoPending(source, pending: pendingFolderURL))
    }

    /// Only the GEDCOM itself is required. A sibling folder that cannot be read — the
    /// file picker grants access to the selected item, not to its neighbours — is
    /// reported as a diagnostic and leaves the import standing, because a tree without
    /// its photos is worth far more than no tree at all.
    ///
    /// The staged photos and attachments are hashed here, off the main actor, into a
    /// manifest beside them. The import's first save copies them as clones and takes
    /// their hashes from it instead of reading every byte again on the main actor.
    private nonisolated func copyIntoPending(_ source: URL, pending: URL) throws -> (gedcom: URL, diagnostics: [ImportDiagnostic]) {
        let fm = FileManager.default
        let root = pending.appendingPathComponent("Import-\(UUID().uuidString)", isDirectory: true)
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
                            "Нет доступа к папке «\(name)» рядом с файлом. Дерево будет импортировано без файлов из неё. Чтобы добавить их, выберите всю папку архива. Подробнее: \(error.localizedDescription)"
                        )
                    ))
                }
            }
            try writeManifest(generationID: UUID(), hashes: hashes(in: root, includeRecoveryData: false), in: root)
            return (destination, diagnostics)
        } catch {
            try? fm.removeItem(at: root)
            throw error
        }
    }

    private nonisolated static func removeIfEmpty(_ folder: URL) {
        guard let items = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil),
              items.isEmpty else { return }
        try? FileManager.default.removeItem(at: folder)
    }

    /// What could not be staged alongside a previewed GEDCOM. Empty when everything the
    /// archive carried came across.
    func stagedImportDiagnostics(for gedcom: URL) -> [ImportDiagnostic] {
        pendingImportDiagnostics[gedcom.standardizedFileURL.path] ?? []
    }

    func discardImportPreview(at gedcom: URL) {
        let pendingRoot = pendingFolderURL.standardizedFileURL
        let folder = gedcom.deletingLastPathComponent().standardizedFileURL
        guard folder.path.hasPrefix(pendingRoot.path + "/") else { return }
        pendingImportDiagnostics[gedcom.standardizedFileURL.path] = nil
        try? FileManager.default.removeItem(at: folder)
        cleanupPendingFolderIfEmpty()
    }

    // MARK: - Committing an import

    func importGEDCOM(from url: URL) async throws -> ImportResult {
        try importGEDCOM(GEDCOMCodec.parse(url), stagedAt: url)
    }

    /// Commit a staged import from the result its preview already parsed. Parsing the
    /// file a second time was most of what the Import button cost on a large tree.
    func importGEDCOM(_ preview: ImportResult, stagedAt url: URL) throws -> ImportResult {
        var result = preview
        guard result.report.blockingErrors.isEmpty else { throw TreeStoreError.invalidImport(report: result.report) }
        // Anything the staging step could not bring across belongs in the tree's own
        // permanent import report, not only in the preview the user already dismissed.
        // The preview may already carry them.
        for diagnostic in stagedImportDiagnostics(for: url) where !result.report.diagnostics.contains(where: { $0.id == diagnostic.id }) {
            result.report.diagnostics.append(diagnostic)
        }
        let tree = result.tree
        if trees.contains(where: { $0.id == tree.id }) {
            tree.id = UUID()
            result.report.diagnostics.append(ImportDiagnostic(
                id: "import.duplicate-tree-id",
                severity: .warning,
                message: L10n.tr("Дерево с таким идентификатором уже есть в библиотеке. Импортированной копии присвоен новый идентификатор.")
            ))
        }
        let importedIssues = TreeValidator.validate(tree)
        tree.acceptedBaselineIssueIDs = Set(importedIssues.filter { $0.severity == .error }.map(\.id))
        for issue in importedIssues where issue.severity == .error {
            result.report.diagnostics.append(ImportDiagnostic(
                id: "import.validation.\(issue.id)",
                severity: .warning,
                message: L10n.tr("В импортированных данных есть ошибка. Она сохранена для проверки: \(issue.message)")
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
}
