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
        public var homePersonId: UUID?
        public var rootUnionId: UUID?
        public var people: [Person]
        public var unions: [Union]
    }

    public static func parse(from url: URL) throws -> ParsedTree {
        let raw = try Data(contentsOf: url)
        // GEDCOM files in the wild are often Windows-1251 (common for Russian
        // genealogy) or UTF-16, not UTF-8 — fall back instead of failing the import.
        let content = String(data: raw, encoding: .utf8)
            ?? String(data: raw, encoding: .windowsCP1251)
            ?? String(data: raw, encoding: .utf16)
            ?? String(decoding: raw, as: UTF8.self)
        return parse(gedcom: content, mediaFolder: url.deletingLastPathComponent().appendingPathComponent("Media"))
    }

    public static func parse(gedcom: String, mediaFolder: URL? = nil) -> ParsedTree {
        let lines = gedcom.components(separatedBy: .newlines)
        let records = splitRecords(lines: lines)

        var treeName = "Без названия"
        var treeSubtitle: String? = nil
        var treeId: UUID? = nil
        var homeXref: String? = nil
        var rootFamXref: String? = nil

        // Maps: GEDCOM xref → UUID
        var indiUUIDs: [String: UUID] = [:]
        var famUUIDs: [String: UUID] = [:]

        // Pre-scan: assign UUIDs to all INDI and FAM records (exact tag match).
        for record in records {
            guard let head = parseLine(record[0]), let xref = head.xref else { continue }
            if head.tag == "INDI" { indiUUIDs[xref] = UUID() }
            else if head.tag == "FAM" { famUUIDs[xref] = UUID() }
        }

        var people: [Person] = []
        var unions: [Union] = []

        for record in records {
            guard let head = parseLine(record[0]) else { continue }

            if head.tag == "HEAD" {
                for raw in record.dropFirst() {
                    guard let line = parseLine(raw), line.level == 1 else { continue }
                    switch line.tag {
                    case "_NAME": treeName = line.value
                    case "_SUBTITLE": treeSubtitle = line.value
                    case "_TREEID": treeId = UUID(uuidString: line.value)
                    case "_HOME": homeXref = line.pointer
                    case "_ROOT": rootFamXref = line.pointer
                    default: break
                    }
                }
            } else if head.tag == "INDI", let xref = head.xref, let uuid = indiUUIDs[xref] {
                people.append(parseIndividual(record: record, uuid: uuid, mediaFolder: mediaFolder))
            } else if head.tag == "FAM", let xref = head.xref, let uuid = famUUIDs[xref] {
                unions.append(parseFamily(record: record, uuid: uuid, indiUUIDs: indiUUIDs))
            }
        }

        let homePersonId = homeXref.flatMap { indiUUIDs[$0] }
        let rootUnionId = rootFamXref.flatMap { famUUIDs[$0] }

        return ParsedTree(
            name: treeName,
            subtitle: treeSubtitle,
            treeId: treeId,
            homePersonId: homePersonId,
            rootUnionId: rootUnionId,
            people: people,
            unions: unions
        )
    }

    // MARK: - Line tokenizer

    /// One parsed GEDCOM line. `xref` is the optional `@X@` *record id* before the tag
    /// (e.g. `0 @I1@ INDI`); `pointer` is an `@X@` *pointer value* after the tag
    /// (e.g. `1 HUSB @I1@`). `value` is the free-text remainder otherwise.
    private struct GEDCOMLine {
        let level: Int
        let xref: String?
        let tag: String
        let pointer: String?
        let value: String
    }

    private static func parseLine(_ raw: String) -> GEDCOMLine? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let sp1 = trimmed.firstIndex(of: " ") else {
            // A bare level with no tag is malformed — ignore.
            return nil
        }
        guard let level = Int(trimmed[..<sp1]) else { return nil }
        var rest = String(trimmed[trimmed.index(after: sp1)...]).trimmingCharacters(in: .whitespaces)

        // Optional record xref immediately after the level: "@X@ TAG ...".
        var xref: String? = nil
        if rest.hasPrefix("@"), let close = rest.dropFirst().firstIndex(of: "@") {
            xref = String(rest[rest.index(after: rest.startIndex) ..< close])
            rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces)
        }

        // Tag is the next whitespace-delimited token.
        let tag: String
        let afterTag: String
        if let sp2 = rest.firstIndex(of: " ") {
            tag = String(rest[..<sp2])
            afterTag = String(rest[rest.index(after: sp2)...]).trimmingCharacters(in: .whitespaces)
        } else {
            tag = rest
            afterTag = ""
        }

        // A value that is exactly "@X@" is a pointer, not free text.
        var pointer: String? = nil
        var value = afterTag
        if afterTag.hasPrefix("@"), afterTag.hasSuffix("@"), afterTag.count >= 2 {
            let inner = afterTag.dropFirst().dropLast()
            if !inner.contains("@") { pointer = String(inner); value = "" }
        }

        return GEDCOMLine(level: level, xref: xref, tag: tag, pointer: pointer, value: value)
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

    private static func parseIndividual(record: [String], uuid: UUID, mediaFolder: URL?) -> Person {
        var givenNames = ""
        var surname = ""
        var patronymic: String? = nil
        var maidenName: String? = nil
        var sex: Person.Sex = .unknown
        var birthDate: String? = nil
        var birthPlace: String? = nil
        var deathDate: String? = nil
        var deathPlace: String? = nil
        var isLiving = true
        var birthLat: Double? = nil
        var birthLon: Double? = nil
        var deathLat: Double? = nil
        var deathLon: Double? = nil
        var burialPlace: String? = nil
        var burialLat: Double? = nil
        var burialLon: Double? = nil
        var occupation: String? = nil
        var education: String? = nil
        var notes: String? = nil
        var sources: [String] = []
        var photoData: Data? = nil
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
                case ("BIRT", "DATE"): birthDate = FamilyDate.normalize(value)
                case ("BIRT", "PLAC"): birthPlace = value
                case ("BIRT", "_COORD"):
                    let nums = value.split(separator: " ").compactMap { Double($0) }
                    if nums.count == 2 { birthLat = nums[0]; birthLon = nums[1] }
                case ("DEAT", "DATE"): deathDate = FamilyDate.normalize(value)
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
                case ("OBJE", "FILE"):
                    if let mediaFolder {
                        let photoURL = mediaFolder.appendingPathComponent(value)
                        photoData = try? Data(contentsOf: photoURL)
                    }
                case ("_ATTC", "FILE"): pendingAttachFile = value
                case ("_ATTC", "TITL"): pendingAttachTitle = value
                case ("NOTE", "CONT"), ("NOTE", "CONC"):
                    let sep = tag == "CONT" ? "\n" : ""
                    notes = (notes ?? "") + sep + value
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
            sources: sources,
            photoData: photoData
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
        return person
    }

    // MARK: - Parse Family

    private static func parseFamily(record: [String], uuid: UUID, indiUUIDs: [String: UUID]) -> Union {
        var partner1Id: UUID? = nil
        var partner2Id: UUID? = nil
        var marriageDate: String? = nil
        var marriagePlace: String? = nil
        var status: String? = nil
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
                case "MARR": break
                case "DIV": status = "divorced"
                case "_STAT": status = line.value.isEmpty ? nil : line.value
                default: break
                }
            case 2:
                let ctx1 = tagAtLevel[1] ?? ""
                switch (ctx1, tag) {
                case ("MARR", "DATE"): marriageDate = FamilyDate.normalize(line.value)
                case ("MARR", "PLAC"): marriagePlace = line.value
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
            status: status,
            childrenIds: childrenIds
        )
        union.id = uuid
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
