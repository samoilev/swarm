import Foundation

public enum PersistenceFaultPoint: String, CaseIterable, Sendable {
    case gedcomWrite
    case portraitWrite
    case exportCopy
    case directorySwap
    case originalImportCopy
    case historyPrune
}

public struct SaveReceipt: Codable, Hashable, Sendable {
    public var finalURL: URL
    public var generationID: UUID
    public var fileCount: Int
    public var hashes: [String: String]
    public var warnings: [String]
    public var recoverySnapshotURL: URL?

    public init(
        finalURL: URL,
        generationID: UUID = UUID(),
        fileCount: Int,
        hashes: [String: String],
        warnings: [String] = [],
        recoverySnapshotURL: URL? = nil
    ) {
        self.finalURL = finalURL
        self.generationID = generationID
        self.fileCount = fileCount
        self.hashes = hashes
        self.warnings = warnings
        self.recoverySnapshotURL = recoverySnapshotURL
    }
}

/// Trash filenames embed the file's original (user-facing) name. It is base64'd with a
/// URL-safe alphabet so it survives as one path component whatever it contained.
enum Base64Filename {
    static func encode(_ value: String) -> String {
        Data(value.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
    }

    static func decode(_ value: String) -> String? {
        var base64 = value.replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "-", with: "+")
        while base64.count % 4 != 0 { base64 += "=" }
        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public struct RecoveryItem: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        case revision
        case deletedFile
        case migrationBackup
        case archivedTree
    }

    public var id: String { url.path }
    public var kind: Kind
    public var url: URL
    public var createdAt: Date
    public var displayName: String

    public init(kind: Kind, url: URL, createdAt: Date, displayName: String) {
        self.kind = kind
        self.url = url
        self.createdAt = createdAt
        self.displayName = displayName
    }

    /// True when a deleted file was a portrait rather than an attachment.
    public var isPortrait: Bool { displayName.contains("--Media--") }

    /// The name to show a person. `displayName` is a filesystem key — a timestamp for a
    /// revision, `<timestamp>--<category>--<stored>[--Original--<base64>]` for a deleted
    /// file — and none of that means anything to the reader.
    public var displayTitle: String {
        switch kind {
        case .deletedFile:
            let parts = displayName.components(separatedBy: "--Original--")
            if parts.count > 1, let decoded = Base64Filename.decode(parts[1]) { return decoded }
            return parts[0].components(separatedBy: "--").last ?? displayName
        case .revision:
            return L10n.tr("Сохранение")
        case .migrationBackup:
            if displayName.hasSuffix("pre-v2") { return L10n.tr("Перед обновлением формата") }
            if displayName.hasSuffix("pre-merge") { return L10n.tr("Перед объединением") }
            if displayName.hasSuffix("pre-restore") { return L10n.tr("Перед восстановлением") }
            return L10n.tr("Резервная копия")
        case .archivedTree:
            return displayName
        }
    }
}

/// One old-format item found on disk that `performPendingMigrations()` will convert.
/// Carries what it is and where it lives so the user is told which of their files this
/// is about, not just how many there are.
public struct PendingMigration: Identifiable, Hashable, Sendable {
    public enum Source: String, Sendable {
        /// A v2 folder that still needs a layout/name upgrade.
        case treeFolder
        /// A flat `<uuid>.ged` beside the storage folder (pre-folder layout).
        case legacyFile
        /// The original `trees.json` database.
        case legacyJSON

        public var label: String {
            switch self {
            case .treeFolder: L10n.tr("Обновление формата папки дерева")
            case .legacyFile: L10n.tr("Файл GEDCOM в старом формате")
            case .legacyJSON: L10n.tr("Старая база данных trees.json")
            }
        }
    }

    public var id: String { url.path }
    public var title: String
    public var source: Source
    public var url: URL

    public init(title: String, source: Source, url: URL) {
        self.title = title
        self.source = source
        self.url = url
    }
}

public enum TreeStoreError: LocalizedError {
    case treeFolderMissing
    case verificationFailed(path: String)
    case commitFailed(reason: String)
    case invalidImport(report: ImportReport)
    case validationFailed(issues: [TreeIssue])
    case recoveryItemMissing
    case migrationRequired
    case noGEDCOMInFolder(folder: String)
    case ambiguousGEDCOMInFolder(folder: String)

    public var errorDescription: String? {
        switch self {
        case .treeFolderMissing:
            L10n.tr("Папка дерева не найдена.")
        case let .verificationFailed(path):
            L10n.tr("В сохранённом файле обнаружена ошибка: \(path).")
        case let .commitFailed(reason):
            L10n.tr("Не удалось сохранить: \(reason).")
        case .invalidImport:
            L10n.tr("Из-за ошибок в GEDCOM этот файл нельзя импортировать.")
        case let .validationFailed(issues):
            L10n.tr("Сохранение заблокировано: \(issues.first?.message ?? L10n.tr("обнаружена ошибка данных")).")
        case .recoveryItemMissing:
            L10n.tr("Этот файл или копия больше не доступны для восстановления.")
        case .migrationRequired:
            L10n.tr("Чтобы сохранять изменения, откройте «Восстановление» и обновите формат дерева.")
        case let .noGEDCOMInFolder(folder):
            L10n.tr("В папке «\(folder)» нет файла GEDCOM.")
        case let .ambiguousGEDCOMInFolder(folder):
            L10n.tr("В папке «\(folder)» несколько файлов GEDCOM. Выберите тот, который хотите открыть.")
        }
    }
}

/// What a history revision holds, so one save can be told apart from the next in the
/// version list. Counts only — a revision carries no other metadata on disk.
public struct RevisionSummary: Sendable, Hashable {
    public var people: Int
    public var families: Int

    public init(people: Int, families: Int) {
        self.people = people
        self.families = families
    }

    /// Count the records in a revision file. A revision is always GEDCOM written by this
    /// app's own serializer, so counting level-0 `INDI`/`FAM` lines is exact and costs a
    /// single scan instead of building a whole `FamilyTree`.
    ///
    /// ponytail: line scan rather than `GEDCOMCodec.parse` — parsing 50 trees to show 50
    /// numbers is the expensive path. Switch to a parse only if a row needs more than
    /// counts. Returns nil when the file is gone or is not UTF-8.
    public static func read(at url: URL) -> RevisionSummary? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var people = 0
        var families = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", omittingEmptySubsequences: true)
            guard fields.count >= 3, fields[0] == "0" else { continue }
            // `0 @I1@ INDI` — the tag is the third field; a level-0 line with a tag in
            // second place (`0 HEAD`, `0 TRLR`) is not a record and falls through.
            switch fields[2] {
            case "INDI": people += 1
            case "FAM": families += 1
            default: continue
            }
        }
        return RevisionSummary(people: people, families: families)
    }
}
