import Foundation

enum GEDCOMTextDecoder {
    static func decode(_ data: Data) -> String {
        let bytes = [UInt8](data.prefix(512))
        if bytes.starts(with: [0xFF, 0xFE]) || bytes.starts(with: [0xFE, 0xFF]),
           let text = String(data: data, encoding: .utf16) {
            return text
        }

        let pairCount = bytes.count / 2
        if pairCount >= 4 {
            let evenNULs = stride(from: 0, to: pairCount * 2, by: 2).filter { bytes[$0] == 0 }.count
            let oddNULs = stride(from: 1, to: pairCount * 2, by: 2).filter { bytes[$0] == 0 }.count
            let threshold = max(2, pairCount / 4)
            if oddNULs >= threshold, oddNULs > evenNULs * 2,
               let text = String(data: data, encoding: .utf16LittleEndian) {
                return text
            }
            if evenNULs >= threshold, evenNULs > oddNULs * 2,
               let text = String(data: data, encoding: .utf16BigEndian) {
                return text
            }
        }

        if let text = String(data: data, encoding: .utf8) { return text }
        if let text = String(data: data, encoding: .windowsCP1251) { return text }
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Lossless GEDCOM syntax tree

public struct GEDCOMNode: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var level: Int
    public var xref: String?
    public var tag: String
    public var pointer: String?
    public var value: String
    public var rawLine: String
    public var children: [GEDCOMNode]

    public init(
        id: UUID = UUID(),
        level: Int,
        xref: String? = nil,
        tag: String,
        pointer: String? = nil,
        value: String = "",
        rawLine: String,
        children: [GEDCOMNode] = []
    ) {
        self.id = id
        self.level = level
        self.xref = xref
        self.tag = tag
        self.pointer = pointer
        self.value = value
        self.rawLine = rawLine
        self.children = children
    }

    public var renderedLine: String {
        if !rawLine.isEmpty { return rawLine }
        var tokens = [String(level)]
        if let xref { tokens.append("@\(xref)@") }
        tokens.append(tag)
        if let pointer { tokens.append("@\(pointer)@") }
        else if !value.isEmpty { tokens.append(value) }
        return tokens.joined(separator: " ")
    }

    public func flattened() -> [GEDCOMNode] {
        [self] + children.flatMap { $0.flattened() }
    }

    public func renderedLines() -> [String] {
        [renderedLine] + children.flatMap { $0.renderedLines() }
    }
}

public struct GEDCOMDocument: Codable, Hashable, Sendable {
    public var records: [GEDCOMNode]
    public var lineEnding: String

    public init(records: [GEDCOMNode], lineEnding: String = "\n") {
        self.records = records
        self.lineEnding = lineEnding
    }

    public var text: String {
        records.flatMap { $0.renderedLines() }.joined(separator: lineEnding)
    }

    public var allNodes: [GEDCOMNode] {
        records.flatMap { $0.flattened() }
    }

    public static func parse(_ text: String) throws -> GEDCOMDocument {
        let lineEnding = text.contains("\r\n") ? "\r\n" : "\n"
        let rawLines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\r")) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !rawLines.isEmpty else { throw GEDCOMCodecError.emptyDocument }

        var flat: [GEDCOMNode] = []
        flat.reserveCapacity(rawLines.count)
        var previousLevel = 0
        for (index, raw) in rawLines.enumerated() {
            let node = try parseLine(raw, lineNumber: index + 1)
            if index == 0, node.level != 0 {
                throw GEDCOMCodecError.invalidStructure(line: index + 1, reason: L10n.tr("Первая запись должна иметь уровень 0"))
            }
            if index > 0, node.level > previousLevel + 1 {
                throw GEDCOMCodecError.invalidStructure(line: index + 1, reason: L10n.tr("Пропущен уровень вложенности"))
            }
            previousLevel = node.level
            flat.append(node)
        }

        var index = 0
        var records: [GEDCOMNode] = []
        while index < flat.count {
            guard flat[index].level == 0 else {
                throw GEDCOMCodecError.invalidStructure(line: index + 1, reason: L10n.tr("Строка вне записи уровня 0"))
            }
            records.append(buildNode(from: flat, index: &index))
        }
        return GEDCOMDocument(records: records, lineEnding: lineEnding)
    }

    private static func buildNode(from flat: [GEDCOMNode], index: inout Int) -> GEDCOMNode {
        var node = flat[index]
        index += 1
        while index < flat.count, flat[index].level > node.level {
            node.children.append(buildNode(from: flat, index: &index))
        }
        return node
    }

    private static func parseLine(_ raw: String, lineNumber: Int) throws -> GEDCOMNode {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard let firstSpace = trimmed.firstIndex(of: " "),
              let level = Int(trimmed[..<firstSpace]), level >= 0 else {
            throw GEDCOMCodecError.invalidLine(line: lineNumber, content: raw)
        }
        var rest = String(trimmed[trimmed.index(after: firstSpace)...])
            .trimmingCharacters(in: .whitespaces)
        guard !rest.isEmpty else { throw GEDCOMCodecError.invalidLine(line: lineNumber, content: raw) }

        var xref: String?
        if rest.first == "@", let closing = rest.dropFirst().firstIndex(of: "@") {
            xref = String(rest[rest.index(after: rest.startIndex) ..< closing])
            rest = String(rest[rest.index(after: closing)...]).trimmingCharacters(in: .whitespaces)
        }
        guard !rest.isEmpty else { throw GEDCOMCodecError.invalidLine(line: lineNumber, content: raw) }

        let tag: String
        let tail: String
        if let space = rest.firstIndex(of: " ") {
            tag = String(rest[..<space]).uppercased()
            tail = String(rest[rest.index(after: space)...]).trimmingCharacters(in: .whitespaces)
        } else {
            tag = rest.uppercased()
            tail = ""
        }
        guard tag.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            throw GEDCOMCodecError.invalidLine(line: lineNumber, content: raw)
        }

        let pointer: String?
        let value: String
        if tail.count >= 2, tail.first == "@", tail.last == "@", !tail.dropFirst().dropLast().contains("@") {
            pointer = String(tail.dropFirst().dropLast())
            value = ""
        } else {
            pointer = nil
            value = tail
        }
        return GEDCOMNode(level: level, xref: xref, tag: tag, pointer: pointer, value: value, rawLine: raw)
    }
}

// MARK: - Import reporting and public codec

public struct ImportDiagnostic: Identifiable, Codable, Hashable, Sendable {
    public enum Severity: String, Codable, Sendable {
        case warning
        case error
    }

    public var id: String
    public var severity: Severity
    public var message: String
    public var recordXref: String?

    public init(id: String, severity: Severity, message: String, recordXref: String? = nil) {
        self.id = id
        self.severity = severity
        self.message = message
        self.recordXref = recordXref
    }
}

public struct ImportReport: Codable, Hashable, Sendable {
    public var diagnostics: [ImportDiagnostic]
    public var preservedUnsupportedTags: [String]
    public var unresolvedPointers: [String]
    public var missingMedia: [String]

    public init(
        diagnostics: [ImportDiagnostic] = [],
        preservedUnsupportedTags: [String] = [],
        unresolvedPointers: [String] = [],
        missingMedia: [String] = []
    ) {
        self.diagnostics = diagnostics
        self.preservedUnsupportedTags = preservedUnsupportedTags
        self.unresolvedPointers = unresolvedPointers
        self.missingMedia = missingMedia
    }

    public var blockingErrors: [ImportDiagnostic] {
        diagnostics.filter { $0.severity == .error }
    }

    public var warnings: [ImportDiagnostic] {
        diagnostics.filter { $0.severity == .warning }
    }
}

public struct ImportResult {
    public var tree: FamilyTree
    public var document: GEDCOMDocument
    public var report: ImportReport

    public init(tree: FamilyTree, document: GEDCOMDocument, report: ImportReport) {
        self.tree = tree
        self.document = document
        self.report = report
    }
}

public struct SerializedTree: Equatable {
    public var gedcom: String
    public var photos: [GEDCOMSerializer.Photo]

    public init(gedcom: String, photos: [GEDCOMSerializer.Photo]) {
        self.gedcom = gedcom
        self.photos = photos
    }
}

public enum GEDCOMCodecError: LocalizedError, Equatable {
    case emptyDocument
    case invalidLine(line: Int, content: String)
    case invalidStructure(line: Int, reason: String)
    case missingHeader

    public var errorDescription: String? {
        switch self {
        case .emptyDocument:
            L10n.tr("GEDCOM-файл пуст.")
        case let .invalidLine(line, _):
            L10n.tr("Некорректная строка GEDCOM: \(line).")
        case let .invalidStructure(line, reason):
            L10n.tr("Некорректная структура GEDCOM в строке \(line): \(reason).")
        case .missingHeader:
            L10n.tr("В GEDCOM-файле отсутствует запись HEAD.")
        }
    }
}

public enum GEDCOMCodec {
    private static let supportedTags: Set<String> = [
        "HEAD", "TRLR", "INDI", "FAM", "SOUR", "SUBM", "REPO", "NOTE", "OBJE",
        "NAME", "GIVN", "SURN", "NPFX", "NSFX", "NICK", "TYPE", "SEX", "BIRT",
        "DEAT", "BURI", "OCCU", "EDUC", "RESI", "IMMI", "MARR", "DIV", "HUSB",
        "WIFE", "CHIL", "FAMS", "FAMC", "PEDI", "DATE", "PLAC", "MAP", "LATI",
        "LONG", "FILE", "FORM", "TITL", "AUTH", "PUBL", "REPO", "CALN", "PAGE",
        "DATA", "TEXT", "QUAY", "CONT", "CONC", "CHAN", "RIN", "GEDC", "CHAR",
        "VERS", "CORP", "ADDR", "PHON", "EMAIL", "FAX", "WWW",
    ]

    public static func parse(_ url: URL) throws -> ImportResult {
        let text = try GEDCOMTextDecoder.decode(Data(contentsOf: url))
        let document = try GEDCOMDocument.parse(text)
        return try project(document: document, text: text, baseURL: url.deletingLastPathComponent())
    }

    /// Preview keeps parse/structure failures inside the import sheet so its blocking
    /// state is visible and testable. The verified import path still throws and can
    /// never commit this placeholder result.
    public static func preview(_ url: URL) throws -> ImportResult {
        do {
            return try parse(url)
        } catch let error as GEDCOMCodecError {
            let tree = FamilyTree(name: url.deletingPathExtension().lastPathComponent)
            let document = GEDCOMDocument(records: [])
            let report = ImportReport(diagnostics: [ImportDiagnostic(
                id: "gedcom.blocking-structure",
                severity: .error,
                message: error.localizedDescription
            )])
            tree.importReport = report
            return ImportResult(tree: tree, document: document, report: report)
        }
    }

    public static func parse(_ text: String, baseURL: URL? = nil) throws -> ImportResult {
        let document = try GEDCOMDocument.parse(text)
        return try project(document: document, text: text, baseURL: baseURL)
    }

    public static func serialize(tree: FamilyTree, document: GEDCOMDocument? = nil) throws -> SerializedTree {
        let result = GEDCOMSerializer.serialize(tree: tree)
        guard let document else { return SerializedTree(gedcom: result.gedcom, photos: result.photos) }
        let canonical = try GEDCOMDocument.parse(result.gedcom)
        let patched = patchOwnedRecords(in: document, with: canonical)
        return SerializedTree(gedcom: patched.text, photos: result.photos)
    }

    /// Replace records owned by the app while retaining the imported top-level order
    /// and every untouched foreign record verbatim. New app records are inserted just
    /// before TRLR. Unknown subtrees inside owned records are already carried by the
    /// model's preservation branches and therefore remain part of the replacement.
    private static func patchOwnedRecords(in original: GEDCOMDocument, with canonical: GEDCOMDocument) -> GEDCOMDocument {
        let ownedTags: Set = ["HEAD", "INDI", "FAM", "SOUR", "TRLR"]
        let canonicalByKey = Dictionary(uniqueKeysWithValues: canonical.records.map { (recordKey($0), $0) })
        var emitted = Set<String>()
        var records: [GEDCOMNode] = []

        func appendNewOwnedRecords() {
            for record in canonical.records where ownedTags.contains(record.tag) && record.tag != "HEAD" && record.tag != "TRLR" {
                let key = recordKey(record)
                if emitted.insert(key).inserted { records.append(record) }
            }
        }

        for record in original.records {
            let key = recordKey(record)
            guard ownedTags.contains(record.tag) else {
                records.append(record)
                continue
            }
            if record.tag == "TRLR" {
                appendNewOwnedRecords()
                if let replacement = canonicalByKey[key] { records.append(replacement); emitted.insert(key) }
            } else if let replacement = canonicalByKey[key] {
                records.append(replacement)
                emitted.insert(key)
            }
            // An original app-owned record absent from the canonical document was
            // intentionally deleted and is therefore omitted.
        }
        if !records.contains(where: { $0.tag == "TRLR" }) {
            appendNewOwnedRecords()
            if let trailer = canonical.records.first(where: { $0.tag == "TRLR" }) { records.append(trailer) }
        }
        return GEDCOMDocument(records: records, lineEnding: original.lineEnding)
    }

    private static func recordKey(_ record: GEDCOMNode) -> String {
        switch record.tag {
        case "INDI", "FAM", "SOUR": "\(record.tag):\(record.xref ?? "")"
        default: record.tag
        }
    }

    private static func project(document: GEDCOMDocument, text: String, baseURL: URL?) throws -> ImportResult {
        guard document.records.contains(where: { $0.tag == "HEAD" }) else {
            throw GEDCOMCodecError.missingHeader
        }
        let parsed = GEDCOMParser.parse(gedcom: text, mediaFolder: baseURL?.appendingPathComponent("Media"))
        let tree = FamilyTree(name: parsed.name, subtitle: parsed.subtitle)
        tree.id = parsed.treeId ?? tree.id
        tree.schemaVersion = parsed.schemaVersion
        tree.homePersonId = parsed.homePersonId
        tree.rootUnionId = parsed.rootUnionId
        tree.people = parsed.people
        tree.unions = parsed.unions
        tree.unknownRecords = parsed.unknownRecords
        tree.headUnknownBranches = parsed.headUnknownBranches
        tree.sourceRecords = parsed.sourceRecords
        tree.parentLinks = parsed.parentLinks
        tree.gedcomDocument = document

        var diagnostics: [ImportDiagnostic] = []
        if !document.records.contains(where: { $0.tag == "TRLR" }) {
            diagnostics.append(ImportDiagnostic(
                id: "gedcom.missing-trailer",
                severity: .warning,
                message: L10n.tr("В файле отсутствует завершающая запись TRLR; данные сохранены.")
            ))
        }

        let nodes = document.allNodes
        let xrefs = Set(nodes.compactMap(\.xref))
        let unresolved = Set(nodes.compactMap(\.pointer).filter { !xrefs.contains($0) }).sorted()
        // The id identifies *this* diagnostic, not its kind: a shared id makes every
        // occurrence after the first vanish from any list drawn by identity.
        for pointer in unresolved {
            diagnostics.append(ImportDiagnostic(
                id: "gedcom.unresolved-pointer.\(pointer)",
                severity: .warning,
                message: L10n.tr("Не найдена запись @\(pointer)@."),
                recordXref: pointer
            ))
        }

        for record in document.records where record.tag == "INDI" {
            let livingMarker = record.children.first { $0.tag == "_LIVING" }
            let markedLiving = livingMarker.map {
                ["1", "Y", "YES", "TRUE"].contains($0.value.uppercased())
            } ?? false
            if markedLiving, record.children.contains(where: { $0.tag == "DEAT" }) {
                diagnostics.append(ImportDiagnostic(
                    id: "gedcom.living-death-conflict.\(record.xref ?? record.id.uuidString)",
                    severity: .warning,
                    message: L10n.tr("Запись одновременно помечена как живая и содержит сведения о смерти; исходные данные сохранены для проверки."),
                    recordXref: record.xref
                ))
            }
        }

        var missingMedia: [String] = []
        if let baseURL {
            for node in nodes where node.tag == "FILE" && !node.value.isEmpty {
                let relative = node.value.replacingOccurrences(of: "\\", with: "/")
                let candidates = [
                    baseURL.appendingPathComponent(relative),
                    baseURL.appendingPathComponent("Media").appendingPathComponent((relative as NSString).lastPathComponent),
                    baseURL.appendingPathComponent("Attachments").appendingPathComponent((relative as NSString).lastPathComponent),
                ]
                if !candidates.contains(where: { FileManager.default.fileExists(atPath: $0.path) }) {
                    missingMedia.append(relative)
                }
            }
        }
        missingMedia = Array(Set(missingMedia)).sorted()
        for file in missingMedia {
            diagnostics.append(ImportDiagnostic(
                id: "gedcom.missing-media.\(file)",
                severity: .warning,
                message: L10n.tr("Связанный файл не найден: \(file).")
            ))
        }

        let unsupported = Set(nodes.map(\.tag).filter { !$0.hasPrefix("_") && !supportedTags.contains($0) }).sorted()
        let report = ImportReport(
            diagnostics: diagnostics,
            preservedUnsupportedTags: unsupported,
            unresolvedPointers: unresolved,
            missingMedia: missingMedia
        )
        tree.importReport = report
        tree.acceptedBaselineIssueIDs = Set(TreeValidator.validate(tree).map(\.id))
        return ImportResult(tree: tree, document: document, report: report)
    }

}
