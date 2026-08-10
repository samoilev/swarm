import Foundation

/// Parses a GEDCOM 5.5.1 file into FamilyTree model objects.
///
/// Lines are tokenized positionally (`level [@xref@] tag [value|@pointer@]`) and
/// walked with a level stack, so nested structures (e.g. the standard
/// `PLAC › MAP › LATI/LONG` coordinate triple) are addressable and record/tag
/// detection is exact rather than substring-based.
public struct GEDCOMParser {

    public struct ParsedTree {
        public var name: String
        public var subtitle: String?
        public var treeId: UUID?
        public var schemaVersion: Int = 1
        public var homePersonId: UUID?
        public var rootUnionId: UUID?
        public var people: [Person]
        public var unions: [Union]
        public var sourceRecords: [SourceRecord] = []
        public var parentLinks: [ParentLink] = []
        public var headUnknownBranches: [[String]] = []
        /// Top-level records the parser doesn't model, kept verbatim for re-export.
        public var unknownRecords: [[String]] = []
    }

    /// Level-1 tags the parser fully models inside an INDI record. Anything else at
    /// level 1 is preserved as an unknown branch. FAMS/FAMC/CHAN/RIN are intentionally
    /// treated as "handled" (regenerated or ignored), so they aren't re-emitted twice.
    private static let modeledIndiTags: Set<String> = [
        "NAME", "SEX", "BIRT", "DEAT", "BURI", "OCCU", "EDUC", "NOTE", "SOUR",
        "OBJE", "_ATTC", "_PATR", "_MARNM", "_FTSID", "FAMS", "FAMC"
    ]
    /// Level-1 tags the parser fully models inside a FAM record.
    private static let modeledFamTags: Set<String> = [
        "HUSB", "WIFE", "CHIL", "MARR", "DIV", "_PART", "_SEPR", "_STAT", "_FTSID"
    ]
    /// Sub-tags of a modeled event (BIRT/DEAT/BURI/MARR) the parser consumes; anything
    /// else under the event is preserved as an event extra.
    private static let modeledEventSubTags: Set<String> = ["DATE", "PLAC", "MAP", "LATI", "LONG", "_COORD", "_PLACID"]
    /// Top-level record tags the parser models (everything else is kept verbatim).
    private static let modeledRecordTags: Set<String> = ["HEAD", "INDI", "FAM", "TRLR"]
    private static let modeledHeadTags: Set<String> = [
        "_TREEID", "_FTSVER", "_NAME", "_SUBTITLE", "_HOME", "_ROOT",
    ]

    public static func parse(from url: URL) throws -> ParsedTree {
        let raw = try Data(contentsOf: url)
        // GEDCOM files in the wild are often Windows-1251 (common for Russian
        // genealogy) or UTF-16, not UTF-8 — fall back instead of failing the import.
        let content = GEDCOMTextDecoder.decode(raw)
        return parse(gedcom: content, mediaFolder: url.deletingLastPathComponent().appendingPathComponent("Media"))
    }

    public static func parse(gedcom: String, mediaFolder: URL? = nil) -> ParsedTree {
        let lines = gedcom.components(separatedBy: .newlines)
        let records = splitRecords(lines: lines)

        var treeName = L10n.tr("Без названия")
        var treeSubtitle: String? = nil
        var treeId: UUID? = nil
        var schemaVersion = 1
        var homeXref: String? = nil
        var rootFamXref: String? = nil

        // Maps: GEDCOM xref → UUID
        var indiUUIDs: [String: UUID] = [:]
        var famUUIDs: [String: UUID] = [:]
        var sourceUUIDs: [String: UUID] = [:]

        // Pre-scan: assign UUIDs to all INDI and FAM records (exact tag match).
        for record in records {
            guard let head = parseLine(record[0]), let xref = head.xref else { continue }
            if head.tag == "INDI" { indiUUIDs[xref] = stableUUID(in: record) ?? UUID() }
            else if head.tag == "FAM" { famUUIDs[xref] = stableUUID(in: record) ?? UUID() }
            else if head.tag == "SOUR" { sourceUUIDs[xref] = stableUUID(in: record) ?? UUID() }
        }

        var people: [Person] = []
        var unions: [Union] = []
        var unknownRecords: [[String]] = []
        var sourceRecords: [SourceRecord] = []
        var headUnknownBranches: [[String]] = []

        for record in records {
            guard let head = parseLine(record[0]) else { continue }

            if head.tag == "HEAD" {
                for raw in record.dropFirst() {
                    guard let line = parseLine(raw), line.level == 1 else { continue }
                    switch line.tag {
                    case "_NAME": treeName = line.value
                    case "_SUBTITLE": treeSubtitle = line.value
                    case "_TREEID": treeId = UUID(uuidString: line.value)
                    case "_FTSVER": schemaVersion = Int(line.value) ?? 1
                    case "_HOME": homeXref = line.pointer
                    case "_ROOT": rootFamXref = line.pointer
                    default: break
                    }
                }
                headUnknownBranches = level1Branches(of: record).filter { branch in
                    guard let line = branch.first.flatMap(parseLine) else { return false }
                    return !modeledHeadTags.contains(line.tag)
                }
            } else if head.tag == "INDI", let xref = head.xref, let uuid = indiUUIDs[xref] {
                people.append(parseIndividual(
                    record: record,
                    uuid: uuid,
                    xref: xref,
                    sourceUUIDs: sourceUUIDs,
                    mediaFolder: mediaFolder
                ))
            } else if head.tag == "FAM", let xref = head.xref, let uuid = famUUIDs[xref] {
                unions.append(parseFamily(
                    record: record,
                    uuid: uuid,
                    xref: xref,
                    indiUUIDs: indiUUIDs,
                    sourceUUIDs: sourceUUIDs
                ))
            } else if head.tag == "SOUR", let xref = head.xref, let uuid = sourceUUIDs[xref] {
                sourceRecords.append(parseSource(record: record, uuid: uuid, xref: xref))
                // Keep the exact source record in the preservation collection until
                // every supported source substructure is modeled by the editor.
                unknownRecords.append(record)
            } else if !modeledRecordTags.contains(head.tag) {
                // An unmodeled top-level record (SOUR, SUBM, REPO, NOTE, …) — keep it
                // verbatim so a foreign file survives import → re-export unscathed.
                unknownRecords.append(record)
            }
        }

        let homePersonId = homeXref.flatMap { indiUUIDs[$0] }
        let rootUnionId = rootFamXref.flatMap { famUUIDs[$0] }
        let parentLinks = parseParentLinks(
            records: records,
            indiUUIDs: indiUUIDs,
            famUUIDs: famUUIDs,
            unions: unions,
            sourceUUIDs: sourceUUIDs
        )

        return ParsedTree(
            name: treeName,
            subtitle: treeSubtitle,
            treeId: treeId,
            schemaVersion: schemaVersion,
            homePersonId: homePersonId,
            rootUnionId: rootUnionId,
            people: people,
            unions: unions,
            sourceRecords: sourceRecords,
            parentLinks: parentLinks,
            headUnknownBranches: headUnknownBranches,
            unknownRecords: unknownRecords
        )
    }

    private static func stableUUID(in record: [String]) -> UUID? {
        for branch in level1Branches(of: record) {
            guard let first = branch.first.flatMap(parseLine), first.tag == "_FTSID" else { continue }
            if let id = UUID(uuidString: first.value) { return id }
        }
        return nil
    }

    // MARK: - Unknown-content preservation

    /// Split a record's body (everything after the `0 …` header) into level-1 branches:
    /// each branch is a level-1 line plus all of its deeper descendants, as raw strings.
    private static func level1Branches(of record: [String]) -> [[String]] {
        var branches: [[String]] = []
        var current: [String] = []
        for raw in record.dropFirst() {
            guard let line = parseLine(raw) else { continue }
            if line.level == 1 {
                if !current.isEmpty { branches.append(current) }
                current = [raw]
            } else if !current.isEmpty {
                current.append(raw)
            }
        }
        if !current.isEmpty { branches.append(current) }
        return branches
    }

    /// `eventExtras` key holding unmodeled sub-lines of an event's PLAC, kept apart from
    /// the event's own extras so export can put them back inside the place.
    static func placeExtrasKey(_ eventTag: String) -> String { "\(eventTag)/PLAC" }

    /// Collect the parts of an INDI/FAM record the modeled parse ignored, so they can be
    /// re-emitted on export. Returns whole unmodeled level-1 branches, plus unmodeled
    /// sub-lines of modeled events keyed by event tag (and by `placeExtrasKey` for the
    /// detail that hangs off the event's place).
    private static func collectUnknowns(record: [String], modeledTags: Set<String>) -> (branches: [[String]], eventExtras: [String: [String]]) {
        var branches: [[String]] = []
        var eventExtras: [String: [String]] = [:]
        for branch in level1Branches(of: record) {
            guard let head = parseLine(branch[0]) else { continue }
            if !modeledTags.contains(head.tag) {
                branches.append(branch) // whole unmodeled branch, verbatim
            } else if head.pointer != nil, ["NOTE", "OBJE"].contains(head.tag) {
                // Pointer forms are distinct records, not inline values. Until the
                // corresponding NOTE/OBJE record editor exists, keep the entire link.
                branches.append(branch)
            } else if ["BIRT", "DEAT", "BURI", "MARR"].contains(head.tag) {
                // A modeled event: keep any sub-line we don't consume (NOTE, SOUR, TYPE,
                // AGNC, custom tags) so event-level detail isn't lost. Which level-2
                // branch a deeper line belongs to has to be tracked: detail under a
                // modeled PLAC (a foreign place id, a note about the coordinates) is
                // kept against that place, so export re-emits it inside PLAC. Left in
                // the flat event list it would trail some other branch, and dropping
                // that branch — an already-replaced SOUR — took it down as well.
                var placeIsOpen = false
                var parentIsModeled = false
                for raw in branch.dropFirst() {
                    guard let line = parseLine(raw) else { continue }
                    if line.level == 2 {
                        parentIsModeled = modeledEventSubTags.contains(line.tag)
                        placeIsOpen = line.tag == "PLAC"
                        if !parentIsModeled { eventExtras[head.tag, default: []].append(raw) }
                        continue
                    }
                    guard !modeledEventSubTags.contains(line.tag) else { continue }
                    let key = parentIsModeled && placeIsOpen ? placeExtrasKey(head.tag) : head.tag
                    eventExtras[key, default: []].append(raw)
                }
            }
        }
        return (branches, eventExtras)
    }

    private struct ParsedCitations {
        var person: [Citation] = []
        var events: [GenealogyEvent.Kind: [Citation]] = [:]
        var eventNotes: [GenealogyEvent.Kind: String] = [:]
    }

    private static func parseCitations(record: [String], sourceUUIDs: [String: UUID]) -> ParsedCitations {
        var result = ParsedCitations()
        for branch in level1Branches(of: record) {
            guard let head = branch.first.flatMap(parseLine) else { continue }
            if head.tag == "SOUR", let pointer = head.pointer, let sourceID = sourceUUIDs[pointer] {
                result.person.append(parseCitation(branch: branch, sourceID: sourceID))
                continue
            }
            guard let eventKind = eventKind(forGEDCOMTag: head.tag) else { continue }
            for child in branches(in: branch, atLevel: 2) {
                guard let childHead = child.first.flatMap(parseLine) else { continue }
                if childHead.tag == "SOUR", let pointer = childHead.pointer, let sourceID = sourceUUIDs[pointer] {
                    result.events[eventKind, default: []].append(parseCitation(branch: child, sourceID: sourceID))
                } else if childHead.tag == "NOTE", childHead.pointer == nil {
                    result.eventNotes[eventKind] = joinedText(branch: child)
                }
            }
        }
        return result
    }

    private static func unmodeledEventBranches(
        record: [String],
        kinds: Set<GenealogyEvent.Kind>
    ) -> [GenealogyEvent.Kind: [[String]]] {
        var result: [GenealogyEvent.Kind: [[String]]] = [:]
        for branch in level1Branches(of: record) {
            guard let head = branch.first.flatMap(parseLine),
                  let kind = eventKind(forGEDCOMTag: head.tag), kinds.contains(kind) else { continue }
            for child in branches(in: branch, atLevel: 2) {
                guard let line = child.first.flatMap(parseLine),
                      !modeledEventSubTags.contains(line.tag),
                      line.tag != "NOTE", line.tag != "SOUR" else { continue }
                result[kind, default: []].append(child)
            }
        }
        return result
    }

    private static func parseCitation(branch: [String], sourceID: UUID) -> Citation {
        var page: String?
        var detail: String?
        var transcription: String?
        var confidence: String?
        var notes: String?
        for raw in branch.dropFirst() {
            guard let line = parseLine(raw) else { continue }
            switch line.tag {
            case "PAGE": page = line.value.isEmpty ? nil : line.value
            case "EVEN": detail = line.value.isEmpty ? nil : line.value
            case "TEXT": transcription = line.value.isEmpty ? nil : line.value
            case "QUAY": confidence = line.value.isEmpty ? nil : line.value
            case "NOTE": notes = line.value.isEmpty ? nil : line.value
            case "CONT":
                if notes != nil { notes = (notes ?? "") + "\n" + line.value }
                else if transcription != nil { transcription = (transcription ?? "") + "\n" + line.value }
            case "CONC":
                if notes != nil { notes = (notes ?? "") + line.value }
                else if transcription != nil { transcription = (transcription ?? "") + line.value }
            default: break
            }
        }
        return Citation(
            sourceID: sourceID,
            page: page,
            detail: detail,
            transcription: transcription,
            confidence: confidence,
            notes: notes,
            rawGEDCOMBranches: [branch]
        )
    }

    private static func parseNames(record: [String], sourceUUIDs: [String: UUID]) -> [PersonName] {
        var result: [PersonName] = []
        var standalonePatronymic: String?
        for branch in level1Branches(of: record) {
            guard let head = branch.first.flatMap(parseLine) else { continue }
            if head.tag == "_PATR" {
                standalonePatronymic = head.value.isEmpty ? nil : head.value
                continue
            }
            guard head.tag == "NAME" else { continue }
            let flat = parseName(head.value)
            var name = PersonName(
                kind: result.isEmpty ? .birth : .alsoKnownAs,
                isPrimary: result.isEmpty,
                givenNames: flat.given,
                surname: flat.surname
            )
            var rawExtras: [[String]] = []
            for child in branches(in: branch, atLevel: 2) {
                guard let line = child.first.flatMap(parseLine) else { continue }
                switch line.tag {
                case "TYPE":
                    switch line.value.lowercased() {
                    case "birth", "maiden": name.kind = .birth
                    case "married": name.kind = .married
                    case "aka": name.kind = .alsoKnownAs
                    case "religious": name.kind = .religious
                    case "immigration": name.kind = .immigration
                    default: name.kind = .other
                    }
                case "GIVN": name.givenNames = line.value
                case "SURN": name.surname = line.value
                case "NPFX": name.prefix = line.value.isEmpty ? nil : line.value
                case "NSFX": name.suffix = line.value.isEmpty ? nil : line.value
                case "NICK": name.nickname = line.value.isEmpty ? nil : line.value
                case "_PATR": name.patronymic = line.value.isEmpty ? nil : line.value
                case "_MARNM":
                    let married = parseName(line.value)
                    name.maidenName = name.surname
                    name.surname = married.surname.isEmpty ? married.given : married.surname
                case "SOUR":
                    if let pointer = line.pointer, let sourceID = sourceUUIDs[pointer] {
                        name.citations.append(parseCitation(branch: child, sourceID: sourceID))
                    }
                default: rawExtras.append(child)
                }
            }
            name.rawGEDCOMBranches = rawExtras
            result.append(name)
        }
        if !result.isEmpty, result[0].patronymic == nil { result[0].patronymic = standalonePatronymic }
        return result
    }

    private static func parseAttachments(record: [String], sourceUUIDs: [String: UUID]) -> [Attachment] {
        var result: [Attachment] = []
        for branch in level1Branches(of: record) {
            guard branch.first.flatMap(parseLine)?.tag == "_ATTC" else { continue }
            var file: String?
            var title: String?
            var notes: String?
            var citations: [Citation] = []
            for child in branches(in: branch, atLevel: 2) {
                guard let line = child.first.flatMap(parseLine) else { continue }
                switch line.tag {
                case "FILE": file = (line.value as NSString).lastPathComponent
                case "TITL": title = joinedText(branch: child)
                case "NOTE": notes = joinedText(branch: child)
                case "SOUR":
                    if let pointer = line.pointer, let sourceID = sourceUUIDs[pointer] {
                        citations.append(parseCitation(branch: child, sourceID: sourceID))
                    }
                default: break
                }
            }
            if let file { result.append(Attachment(storedName: file, originalName: title ?? file, notes: notes, citations: citations)) }
        }
        return result
    }

    private static func parseSource(record: [String], uuid: UUID, xref: String) -> SourceRecord {
        var title = L10n.tr("Источник без названия")
        var author: String?
        var publication: String?
        var repository: String?
        var callNumber: String?
        var notes: String?
        var rawBranches: [[String]] = []
        for branch in level1Branches(of: record) {
            guard let head = branch.first.flatMap(parseLine) else { continue }
            switch head.tag {
            case "TITL": title = head.value.isEmpty ? title : joinedText(branch: branch)
            case "AUTH": author = joinedText(branch: branch)
            case "PUBL": publication = joinedText(branch: branch)
            case "REPO": repository = head.pointer.map { "@\($0)@" } ?? head.value
            case "CALN": callNumber = head.value
            case "NOTE": notes = joinedText(branch: branch)
            case "_FTSID", "CHAN", "RIN":
                if head.tag != "_FTSID" { rawBranches.append(branch) }
            default: rawBranches.append(branch)
            }
        }
        return SourceRecord(
            id: uuid,
            gedcomXref: xref,
            title: title,
            author: author,
            publication: publication,
            repository: repository,
            callNumber: callNumber,
            notes: notes,
            rawGEDCOMBranches: rawBranches
        )
    }

    private static func parseParentLinks(
        records: [[String]],
        indiUUIDs: [String: UUID],
        famUUIDs: [String: UUID],
        unions: [Union],
        sourceUUIDs: [String: UUID]
    ) -> [ParentLink] {
        struct Evidence {
            var id: UUID?
            var kind: ParentageKind
            var citations: [Citation]
            var notes: String?
        }
        let unionsByID = Dictionary(uniqueKeysWithValues: unions.map { ($0.id, $0) })
        var explicitKinds: [String: ParentageKind] = [:]
        var evidence: [String: Evidence] = [:]
        for record in records {
            guard let head = record.first.flatMap(parseLine), head.tag == "INDI",
                  let indiXref = head.xref, let childID = indiUUIDs[indiXref] else { continue }
            for branch in level1Branches(of: record) {
                guard let famLine = branch.first.flatMap(parseLine), famLine.tag == "FAMC",
                      let famXref = famLine.pointer else { continue }
                var kind = ParentageKind.biological
                for raw in branch.dropFirst() {
                    guard let line = parseLine(raw), line.tag == "PEDI" || line.tag == "_PEDI" else { continue }
                    kind = ParentageKind(gedcomValue: line.value)
                }
                explicitKinds["\(indiXref)|\(famXref)"] = kind
                for linkBranch in branches(in: branch, atLevel: 2) {
                    guard let linkLine = linkBranch.first.flatMap(parseLine), linkLine.tag == "_PLINK",
                          let parentXref = linkLine.pointer, let parentID = indiUUIDs[parentXref] else { continue }
                    var parsed = Evidence(id: nil, kind: kind, citations: [], notes: nil)
                    for child in branches(in: linkBranch, atLevel: 3) {
                        guard let childLine = child.first.flatMap(parseLine) else { continue }
                        switch childLine.tag {
                        case "_FTSID": parsed.id = UUID(uuidString: childLine.value)
                        case "PEDI", "_PEDI": parsed.kind = ParentageKind(gedcomValue: childLine.value)
                        case "NOTE": parsed.notes = joinedText(branch: child)
                        case "SOUR":
                            if let pointer = childLine.pointer, let sourceID = sourceUUIDs[pointer] {
                                parsed.citations.append(parseCitation(branch: child, sourceID: sourceID))
                            }
                        default: break
                        }
                    }
                    evidence["\(childID)|\(famXref)|\(parentID)"] = parsed
                }
            }
        }

        var result: [ParentLink] = []
        for (famXref, unionID) in famUUIDs {
            guard let union = unionsByID[unionID] else { continue }
            for childID in union.childrenIds {
                let childXref = indiUUIDs.first(where: { $0.value == childID })?.key
                let kind = childXref.flatMap { explicitKinds["\($0)|\(famXref)"] } ?? .biological
                for parentID in union.partnerIds {
                    let parsed = evidence["\(childID)|\(famXref)|\(parentID)"]
                    result.append(ParentLink(
                        id: parsed?.id ?? UUID(),
                        parentID: parentID,
                        childID: childID,
                        unionID: unionID,
                        kind: parsed?.kind ?? kind,
                        citations: parsed?.citations ?? [],
                        notes: parsed?.notes
                    ))
                }
            }
        }
        return result
    }

    private static func branches(in rawBranch: [String], atLevel level: Int) -> [[String]] {
        var result: [[String]] = []
        var current: [String] = []
        for raw in rawBranch.dropFirst() {
            guard let line = parseLine(raw) else { continue }
            if line.level == level {
                if !current.isEmpty { result.append(current) }
                current = [raw]
            } else if line.level > level, !current.isEmpty {
                current.append(raw)
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func joinedText(branch: [String]) -> String {
        guard let head = branch.first.flatMap(parseLine) else { return "" }
        var value = head.value
        for raw in branch.dropFirst() {
            guard let line = parseLine(raw) else { continue }
            if line.tag == "CONT" { value += "\n" + line.value }
            else if line.tag == "CONC" { value += line.value }
        }
        return value
    }

    private static func eventKind(forGEDCOMTag tag: String) -> GenealogyEvent.Kind? {
        switch tag {
        case "BIRT": .birth
        case "DEAT": .death
        case "BURI": .burial
        case "OCCU": .occupation
        case "EDUC": .education
        case "MARR": .marriage
        case "_PART": .partnership
        case "_SEPR": .separation
        case "DIV": .divorce
        case "RESI": .residence
        case "IMMI": .immigration
        default: nil
        }
    }

    // MARK: - Line tokenizer

    /// Tokenize one line, tolerating anything that isn't a GEDCOM line by skipping it.
    /// Shares `GEDCOMNode`'s tokenizer so the tree parser and the document parser can
    /// never disagree about where a tag ends and its value begins.
    private static func parseLine(_ raw: String) -> GEDCOMNode? {
        GEDCOMNode(rawLine: raw)
    }

    /// Parse a GEDCOM `LATI`/`LONG` value ("N55.75", "E37.61", "S12.3", "W4.1", or a
    /// plain signed decimal) into a signed degree value. Nil if unparseable.
    private static func parseLatLong(_ s: String) -> Double? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard let first = t.first else { return nil }
        if "NSEW".contains(first) {
            guard let mag = Double(t.dropFirst()) else { return nil }
            return (first == "S" || first == "W") ? -mag : mag
        }
        return Double(t)
    }

    // MARK: - Record splitting

    private static func splitRecords(lines: [String]) -> [[String]] {
        var records: [[String]] = []
        var current: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if trimmed.hasPrefix("0 ") {
                if !current.isEmpty { records.append(current) }
                current = [trimmed]
            } else {
                current.append(trimmed)
            }
        }
        if !current.isEmpty { records.append(current) }
        return records
    }

    // MARK: - Parse Individual

    private static func parseIndividual(
        record: [String],
        uuid: UUID,
        xref: String,
        sourceUUIDs: [String: UUID],
        mediaFolder: URL?
    ) -> Person {
        var givenNames = ""
        var surname = ""
        var patronymic: String? = nil
        var maidenName: String? = nil
        var sex: Person.Sex = .unknown
        var birthDate: String? = nil
        var birthGEDCOMDate: GenealogyDate? = nil
        var birthPlace: String? = nil
        var deathDate: String? = nil
        var deathGEDCOMDate: GenealogyDate? = nil
        var deathPlace: String? = nil
        var isLiving = true
        var birthLat: Double? = nil
        var birthLon: Double? = nil
        var birthDatasetID: String? = nil
        var deathLat: Double? = nil
        var deathLon: Double? = nil
        var deathDatasetID: String? = nil
        var burialPlace: String? = nil
        var burialLat: Double? = nil
        var burialLon: Double? = nil
        var burialDatasetID: String? = nil
        var occupation: String? = nil
        var education: String? = nil
        var notes: String? = nil
        var sources: [String] = []
        var photoFilename: String? = nil
        var attachments: [Attachment] = []
        var pendingAttachFile: String? = nil
        var pendingAttachTitle: String? = nil

        func flushAttachment() {
            guard let file = pendingAttachFile else { return }
            let stored = (file as NSString).lastPathComponent
            attachments.append(Attachment(storedName: stored, originalName: pendingAttachTitle ?? stored))
            pendingAttachFile = nil
            pendingAttachTitle = nil
        }

        // tagAtLevel[L] = the tag most recently seen at level L within this record.
        // It gives each line its parent context (e.g. a level-4 LATI knows it sits
        // under PLAC › MAP under some BIRT/DEAT/BURI event).
        var tagAtLevel: [Int: String] = [:]

        for raw in record.dropFirst() {
            guard let line = parseLine(raw) else { continue }
            let level = line.level
            let tag = line.tag
            let value = line.value
            tagAtLevel[level] = tag
            for deeper in tagAtLevel.keys where deeper > level {
                tagAtLevel[deeper] = nil
            }

            switch level {
            case 1:
                // Any new top-level tag closes the attachment record being read.
                flushAttachment()
                switch tag {
                case "NAME":
                    let parsed = parseName(value)
                    givenNames = parsed.given
                    surname = parsed.surname
                case "SEX":
                    sex = Person.Sex(rawValue: value) ?? .unknown
                case "BIRT": break
                case "DEAT": isLiving = false
                case "BURI": break
                case "OCCU": occupation = value.isEmpty ? nil : value
                case "EDUC": education = value.isEmpty ? nil : value
                case "NOTE": notes = value.isEmpty ? nil : value
                case "SOUR": if !value.isEmpty { sources.append(value) }
                case "_PATR": patronymic = value.isEmpty ? nil : value
                case "_MARNM":
                    // Married name at level 1 → current surname is the married name,
                    // the birth surname (from NAME) becomes the maiden name.
                    let parsed = parseName(value)
                    maidenName = surname.isEmpty ? nil : surname
                    surname = parsed.surname.isEmpty ? parsed.given : parsed.surname
                case "OBJE": break
                default: break
                }

            case 2:
                let ctx1 = tagAtLevel[1] ?? ""
                switch (ctx1, tag) {
                case ("BIRT", "DATE"):
                    birthGEDCOMDate = GenealogyDate(rawGEDCOM: value)
                    birthDate = FamilyDate.normalize(value)
                case ("BIRT", "PLAC"): birthPlace = value
                case ("BIRT", "_COORD"):
                    let nums = value.split(separator: " ").compactMap { Double($0) }
                    if nums.count == 2 { birthLat = nums[0]; birthLon = nums[1] }
                case ("DEAT", "DATE"):
                    deathGEDCOMDate = GenealogyDate(rawGEDCOM: value)
                    deathDate = FamilyDate.normalize(value)
                case ("DEAT", "PLAC"): deathPlace = value
                case ("DEAT", "_COORD"):
                    let nums = value.split(separator: " ").compactMap { Double($0) }
                    if nums.count == 2 { deathLat = nums[0]; deathLon = nums[1] }
                case ("BURI", "PLAC"): burialPlace = value
                case ("BURI", "_COORD"):
                    let nums = value.split(separator: " ").compactMap { Double($0) }
                    if nums.count == 2 { burialLat = nums[0]; burialLon = nums[1] }
                case ("NAME", "_MARNM"):
                    let parsed = parseName(value)
                    maidenName = surname
                    surname = parsed.surname.isEmpty ? parsed.given : parsed.surname
                case ("NAME", "_PATR"):
                    patronymic = value.isEmpty ? nil : value
                case ("OBJE", "FILE"):
                    // Record the filename only; the bytes are loaded lazily on demand
                    // (Person.photoData) so importing a library doesn't pull every
                    // portrait into memory at once.
                    photoFilename = (value as NSString).lastPathComponent
                case ("_ATTC", "FILE"): pendingAttachFile = value
                case ("_ATTC", "TITL"): pendingAttachTitle = value
                case ("NOTE", "CONT"), ("NOTE", "CONC"):
                    let sep = tag == "CONT" ? "\n" : ""
                    notes = (notes ?? "") + sep + value
                // Long OCCU/EDUC values we emit are split with CONC — re-join them.
                case ("OCCU", "CONC"): occupation = (occupation ?? "") + value
                case ("OCCU", "CONT"): occupation = (occupation ?? "") + "\n" + value
                case ("EDUC", "CONC"): education = (education ?? "") + value
                case ("EDUC", "CONT"): education = (education ?? "") + "\n" + value
                default: break
                }

            case 3:
                guard tagAtLevel[2] == "PLAC", tag == "_PLACID" else { break }
                switch tagAtLevel[1] ?? "" {
                case "BIRT": birthDatasetID = value.isEmpty ? nil : value
                case "DEAT": deathDatasetID = value.isEmpty ? nil : value
                case "BURI": burialDatasetID = value.isEmpty ? nil : value
                default: break
                }

            case 4:
                // Standard coordinates: <EVENT> › PLAC › MAP › LATI/LONG.
                let ctx1 = tagAtLevel[1] ?? ""
                let ctx2 = tagAtLevel[2] ?? ""
                let ctx3 = tagAtLevel[3] ?? ""
                guard ctx2 == "PLAC", ctx3 == "MAP" else { break }
                if tag == "LATI", let v = parseLatLong(value) {
                    switch ctx1 {
                    case "BIRT": birthLat = v
                    case "DEAT": deathLat = v
                    case "BURI": burialLat = v
                    default: break
                    }
                } else if tag == "LONG", let v = parseLatLong(value) {
                    switch ctx1 {
                    case "BIRT": birthLon = v
                    case "DEAT": deathLon = v
                    case "BURI": burialLon = v
                    default: break
                    }
                }

            default: break
            }
        }
        flushAttachment() // capture a trailing attachment record

        let person = Person(
            givenNames: givenNames,
            patronymic: patronymic,
            surname: surname,
            maidenName: maidenName,
            sex: sex,
            birthDate: birthDate,
            birthPlace: birthPlace,
            deathDate: deathDate,
            deathPlace: deathPlace,
            isLiving: isLiving,
            burialPlace: burialPlace,
            occupation: occupation,
            education: education,
            notes: notes,
            sources: sources
        )
        // Override the auto-generated UUID
        person.id = uuid
        person.birthLat = birthLat
        person.birthLon = birthLon
        person.deathLat = deathLat
        person.deathLon = deathLon
        person.burialLat = burialLat
        person.burialLon = burialLon
        person.attachments = attachments
        // Portrait: keep the filename + folder so the bytes load lazily on first use.
        person.photoFilename = photoFilename
        person.mediaFolderURL = mediaFolder
        person.gedcomXref = xref
        if let birthGEDCOMDate { person.setStructuredDate(birthGEDCOMDate, for: .birth) }
        if let deathGEDCOMDate { person.setStructuredDate(deathGEDCOMDate, for: .death) }
        if let birthDatasetID, var place = person.event(ofKind: .birth)?.place {
            place.datasetID = birthDatasetID; place.isCustom = false
            person.setStructuredPlace(place, for: .birth)
        }
        if let deathDatasetID, var place = person.event(ofKind: .death)?.place {
            place.datasetID = deathDatasetID; place.isCustom = false
            person.setStructuredPlace(place, for: .death)
        }
        if let burialDatasetID, var place = person.event(ofKind: .burial)?.place {
            place.datasetID = burialDatasetID; place.isCustom = false
            person.setStructuredPlace(place, for: .burial)
        }
        let parsedNames = parseNames(record: record, sourceUUIDs: sourceUUIDs)
        if !parsedNames.isEmpty { person.names = parsedNames }
        let structuredAttachments = parseAttachments(record: record, sourceUUIDs: sourceUUIDs)
        if !structuredAttachments.isEmpty { person.attachments = structuredAttachments }
        let parsedCitations = parseCitations(record: record, sourceUUIDs: sourceUUIDs)
        let rawEventBranches = unmodeledEventBranches(record: record, kinds: [.occupation, .education])
        person.citations = parsedCitations.person
        let detailedEventKinds = Set(parsedCitations.events.keys)
            .union(parsedCitations.eventNotes.keys)
            .union(rawEventBranches.keys)
        for kind in detailedEventKinds {
            var event = person.event(ofKind: kind) ?? GenealogyEvent(kind: kind)
            event.citations = parsedCitations.events[kind] ?? []
            if let note = parsedCitations.eventNotes[kind] { event.notes = note }
            event.rawGEDCOMBranches = rawEventBranches[kind] ?? []
            person.replaceEvent(event)
        }
        let unknowns = collectUnknowns(record: record, modeledTags: modeledIndiTags)
        person.unknownBranches = unknowns.branches
        person.eventExtras = unknowns.eventExtras
        return person
    }

    // MARK: - Parse Family

    private static func parseFamily(
        record: [String],
        uuid: UUID,
        xref: String,
        indiUUIDs: [String: UUID],
        sourceUUIDs: [String: UUID]
    ) -> Union {
        var partner1Id: UUID? = nil
        var partner2Id: UUID? = nil
        var marriageDate: String? = nil
        var marriageGEDCOMDate: GenealogyDate? = nil
        var marriagePlace: String? = nil
        var marriageDatasetID: String? = nil
        var divorceDate: GenealogyDate? = nil
        var divorcePlace: String? = nil
        var divorceDatasetID: String? = nil
        var partnershipDate: GenealogyDate? = nil
        var partnershipPlace: String? = nil
        var partnershipDatasetID: String? = nil
        var separationDate: GenealogyDate? = nil
        var separationPlace: String? = nil
        var separationDatasetID: String? = nil
        var status: String? = nil
        var hasMarriage = false
        var hasDivorce = false
        var hasPartnership = false
        var hasSeparation = false
        var childrenIds: [UUID] = []
        var tagAtLevel: [Int: String] = [:]

        for raw in record.dropFirst() {
            guard let line = parseLine(raw) else { continue }
            let level = line.level
            let tag = line.tag
            tagAtLevel[level] = tag
            for deeper in tagAtLevel.keys where deeper > level {
                tagAtLevel[deeper] = nil
            }

            switch level {
            case 1:
                switch tag {
                case "HUSB": if let p = line.pointer { partner1Id = indiUUIDs[p] }
                case "WIFE": if let p = line.pointer { partner2Id = indiUUIDs[p] }
                case "CHIL": if let p = line.pointer, let cid = indiUUIDs[p] { childrenIds.append(cid) }
                case "MARR": hasMarriage = true
                case "DIV": hasDivorce = true
                case "_PART": hasPartnership = true
                case "_SEPR": hasSeparation = true
                case "_STAT": status = line.value.isEmpty ? nil : line.value
                default: break
                }
            case 2:
                let ctx1 = tagAtLevel[1] ?? ""
                switch (ctx1, tag) {
                case ("MARR", "DATE"):
                    marriageGEDCOMDate = GenealogyDate(rawGEDCOM: line.value)
                    marriageDate = FamilyDate.normalize(line.value)
                case ("MARR", "PLAC"): marriagePlace = line.value
                case ("DIV", "DATE"): divorceDate = GenealogyDate(rawGEDCOM: line.value)
                case ("DIV", "PLAC"): divorcePlace = line.value
                case ("_PART", "DATE"): partnershipDate = GenealogyDate(rawGEDCOM: line.value)
                case ("_PART", "PLAC"): partnershipPlace = line.value
                case ("_SEPR", "DATE"): separationDate = GenealogyDate(rawGEDCOM: line.value)
                case ("_SEPR", "PLAC"): separationPlace = line.value
                default: break
                }
            case 3:
                guard tagAtLevel[2] == "PLAC", tag == "_PLACID" else { break }
                switch tagAtLevel[1] ?? "" {
                case "MARR": marriageDatasetID = line.value.isEmpty ? nil : line.value
                case "DIV": divorceDatasetID = line.value.isEmpty ? nil : line.value
                case "_PART": partnershipDatasetID = line.value.isEmpty ? nil : line.value
                case "_SEPR": separationDatasetID = line.value.isEmpty ? nil : line.value
                default: break
                }
            default: break
            }
        }

        let union = Union(
            partner1Id: partner1Id,
            partner2Id: partner2Id,
            marriageDate: marriageDate,
            marriagePlace: marriagePlace,
            status: status ?? (hasSeparation ? "separated" : (hasDivorce ? "divorced" : nil)),
            childrenIds: childrenIds
        )
        union.id = uuid
        union.gedcomXref = xref
        if hasMarriage || marriageGEDCOMDate != nil || marriagePlace != nil {
            union.setStructuredEvent(GenealogyEvent(
                kind: .marriage,
                date: marriageGEDCOMDate,
                place: marriagePlace.map { PlaceReference(datasetID: marriageDatasetID, displayName: $0, isCustom: marriageDatasetID == nil) }
            ))
        }
        if hasDivorce || divorceDate != nil || divorcePlace != nil {
            union.setStructuredEvent(GenealogyEvent(
                kind: .divorce,
                date: divorceDate,
                place: divorcePlace.map { PlaceReference(datasetID: divorceDatasetID, displayName: $0, isCustom: divorceDatasetID == nil) }
            ))
        }
        if hasPartnership || partnershipDate != nil || partnershipPlace != nil {
            union.setStructuredEvent(GenealogyEvent(
                kind: .partnership,
                date: partnershipDate,
                place: partnershipPlace.map { PlaceReference(datasetID: partnershipDatasetID, displayName: $0, isCustom: partnershipDatasetID == nil) }
            ))
        }
        if hasSeparation || separationDate != nil || separationPlace != nil {
            union.setStructuredEvent(GenealogyEvent(
                kind: .separation,
                date: separationDate,
                place: separationPlace.map { PlaceReference(datasetID: separationDatasetID, displayName: $0, isCustom: separationDatasetID == nil) }
            ))
        }
        let parsedCitations = parseCitations(record: record, sourceUUIDs: sourceUUIDs)
        let rawEventBranches = unmodeledEventBranches(record: record, kinds: [.divorce, .partnership, .separation])
        union.citations = parsedCitations.person
        let detailedEventKinds = Set(parsedCitations.events.keys)
            .union(parsedCitations.eventNotes.keys)
            .union(rawEventBranches.keys)
            .filter { [.marriage, .divorce, .partnership, .separation].contains($0) }
        for kind in detailedEventKinds {
            var event = union.event(ofKind: kind) ?? GenealogyEvent(kind: kind)
            event.citations = parsedCitations.events[kind] ?? []
            if let note = parsedCitations.eventNotes[kind] { event.notes = note }
            event.rawGEDCOMBranches = rawEventBranches[kind] ?? []
            union.setStructuredEvent(event)
        }
        let unknowns = collectUnknowns(record: record, modeledTags: modeledFamTags)
        union.unknownBranches = unknowns.branches
        union.marriageExtras = unknowns.eventExtras["MARR"] ?? []
        return union
    }

    // MARK: - Helpers

    private static func parseName(_ nameStr: String) -> (given: String, surname: String) {
        // "John /Smith/" → ("John", "Smith")
        // "Иван Петрович /Сидоров/" → ("Иван Петрович", "Сидоров")
        var given = ""
        var surname = ""

        if let slashRange = nameStr.range(of: "/") {
            given = String(nameStr[..<slashRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let afterSlash = nameStr[slashRange.upperBound...]
            if let endSlash = afterSlash.firstIndex(of: "/") {
                surname = String(afterSlash[..<endSlash])
            } else {
                surname = String(afterSlash).trimmingCharacters(in: .whitespaces)
            }
        } else {
            given = nameStr.trimmingCharacters(in: .whitespaces)
        }

        return (given, surname)
    }
}
