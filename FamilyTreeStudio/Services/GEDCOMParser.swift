import Foundation

/// Parses a GEDCOM 5.5.1 file into FamilyTree model objects.
struct GEDCOMParser {
    
    struct ParsedTree {
        var name: String
        var subtitle: String?
        var homePersonId: UUID?
        var rootUnionId: UUID?
        var people: [Person]
        var unions: [Union]
    }
    
    static func parse(from url: URL) throws -> ParsedTree {
        let raw = try Data(contentsOf: url)
        // GEDCOM files in the wild are often Windows-1251 (common for Russian
        // genealogy) or UTF-16, not UTF-8 — fall back instead of failing the import.
        let content = String(data: raw, encoding: .utf8)
            ?? String(data: raw, encoding: .windowsCP1251)
            ?? String(data: raw, encoding: .utf16)
            ?? String(decoding: raw, as: UTF8.self)
        return parse(gedcom: content, mediaFolder: url.deletingLastPathComponent().appendingPathComponent("Media"))
    }
    
    static func parse(gedcom: String, mediaFolder: URL? = nil) -> ParsedTree {
        let lines = gedcom.components(separatedBy: .newlines)
        let records = splitRecords(lines: lines)
        
        var treeName = "Без названия"
        var treeSubtitle: String? = nil
        var homeXref: String? = nil
        var rootFamXref: String? = nil
        
        // Maps: GEDCOM xref → UUID
        var indiUUIDs: [String: UUID] = [:]
        var famUUIDs: [String: UUID] = [:]
        
        // Pre-scan: assign UUIDs to all INDI and FAM records
        for record in records {
            let firstLine = record[0]
            if let xref = extractXref(firstLine) {
                if firstLine.contains("INDI") {
                    indiUUIDs[xref] = UUID()
                } else if firstLine.contains("FAM") {
                    famUUIDs[xref] = UUID()
                }
            }
        }
        
        var people: [Person] = []
        var unions: [Union] = []
        
        // Parse HEAD for metadata
        for record in records {
            guard record[0].hasPrefix("0 HEAD") else { continue }
            for line in record {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("1 _NAME ") {
                    treeName = String(trimmed.dropFirst(8))
                } else if trimmed.hasPrefix("1 _SUBTITLE ") {
                    treeSubtitle = String(trimmed.dropFirst(12))
                } else if trimmed.hasPrefix("1 _HOME @") {
                    homeXref = extractPointer(trimmed)
                } else if trimmed.hasPrefix("1 _ROOT @") {
                    rootFamXref = extractPointer(trimmed)
                }
            }
            break
        }
        
        // Parse INDI records
        for record in records {
            let firstLine = record[0]
            guard let xref = extractXref(firstLine), firstLine.contains("INDI") else { continue }
            guard let uuid = indiUUIDs[xref] else { continue }
            
            let person = parseIndividual(record: record, uuid: uuid, mediaFolder: mediaFolder)
            people.append(person)
        }
        
        // Parse FAM records
        for record in records {
            let firstLine = record[0]
            guard let xref = extractXref(firstLine), firstLine.contains("FAM") else { continue }
            guard let uuid = famUUIDs[xref] else { continue }
            
            let union = parseFamily(record: record, uuid: uuid, indiUUIDs: indiUUIDs)
            unions.append(union)
        }
        
        // Resolve home person and root union
        let homePersonId = homeXref.flatMap { indiUUIDs[$0] }
        let rootUnionId = rootFamXref.flatMap { famUUIDs[$0] }
        
        return ParsedTree(
            name: treeName,
            subtitle: treeSubtitle,
            homePersonId: homePersonId,
            rootUnionId: rootUnionId,
            people: people,
            unions: unions
        )
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
        var burialPlace: String? = nil
        var burialLat: Double? = nil
        var burialLon: Double? = nil
        var occupation: String? = nil
        var education: String? = nil
        var notes: String? = nil
        var sources: [String] = []
        var photoData: Data? = nil
        
        var context = "" // tracks current level-1 tag
        
        for line in record.dropFirst() {
            let level = extractLevel(line)
            let tag = extractTag(line, level: level)
            let value = extractValue(line, level: level, tag: tag)
            
            if level == 1 {
                context = tag
                switch tag {
                case "NAME":
                    let parsed = parseName(value)
                    givenNames = parsed.given
                    surname = parsed.surname
                case "SEX":
                    sex = Person.Sex(rawValue: value) ?? .unknown
                case "BIRT": break
                case "DEAT":
                    isLiving = false
                case "BURI": break
                case "OCCU":
                    occupation = value.isEmpty ? nil : value
                case "EDUC":
                    education = value.isEmpty ? nil : value
                case "NOTE":
                    notes = value.isEmpty ? nil : value
                case "SOUR":
                    if !value.isEmpty { sources.append(value) }
                case "_PATR":
                    patronymic = value.isEmpty ? nil : value
                case "_MARNM":
                    // Married name given → current surname is married, birth surname is in NAME
                    let parsed = parseName(value)
                    maidenName = surname.isEmpty ? nil : surname
                    surname = parsed.surname.isEmpty ? parsed.given : parsed.surname
                case "OBJE": break
                default: break
                }
            } else if level == 2 {
                switch (context, tag) {
                case ("BIRT", "DATE"):
                    birthDate = FamilyDate.normalize(value)
                case ("BIRT", "PLAC"):
                    birthPlace = value
                case ("DEAT", "DATE"):
                    deathDate = FamilyDate.normalize(value)
                case ("DEAT", "PLAC"):
                    deathPlace = value
                case ("BURI", "PLAC"):
                    burialPlace = value
                case ("BURI", "_COORD"):
                    let nums = value.split(separator: " ").compactMap { Double($0) }
                    if nums.count == 2 { burialLat = nums[0]; burialLon = nums[1] }
                case ("NAME", "_MARNM"), ("NAME", "2 _MARNM"):
                    let parsed = parseName(value)
                    maidenName = surname
                    surname = parsed.surname.isEmpty ? parsed.given : parsed.surname
                case ("OBJE", "FILE"):
                    if let mediaFolder = mediaFolder {
                        let photoURL = mediaFolder.appendingPathComponent(value)
                        photoData = try? Data(contentsOf: photoURL)
                    }
                case ("NOTE", "CONT"), ("NOTE", "CONC"):
                    let sep = tag == "CONT" ? "\n" : ""
                    notes = (notes ?? "") + sep + value
                default: break
                }
            }
        }
        
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
        person.burialLat = burialLat
        person.burialLon = burialLon
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
        var context = ""
        
        for line in record.dropFirst() {
            let level = extractLevel(line)
            let tag = extractTag(line, level: level)
            let value = extractValue(line, level: level, tag: tag)
            
            if level == 1 {
                context = tag
                switch tag {
                case "HUSB":
                    if let xref = extractPointer(line) { partner1Id = indiUUIDs[xref] }
                case "WIFE":
                    if let xref = extractPointer(line) { partner2Id = indiUUIDs[xref] }
                case "CHIL":
                    if let xref = extractPointer(line), let cid = indiUUIDs[xref] { childrenIds.append(cid) }
                case "MARR": break
                case "DIV":
                    status = "divorced"
                case "_STAT":
                    status = value.isEmpty ? nil : value
                default: break
                }
            } else if level == 2 {
                switch (context, tag) {
                case ("MARR", "DATE"):
                    marriageDate = FamilyDate.normalize(value)
                case ("MARR", "PLAC"):
                    marriagePlace = value
                default: break
                }
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
    
    private static func extractXref(_ line: String) -> String? {
        // "0 @I1@ INDI" → "I1"
        guard let at1 = line.firstIndex(of: "@") else { return nil }
        let after = line[line.index(after: at1)...]
        guard let at2 = after.firstIndex(of: "@") else { return nil }
        return String(after[..<at2])
    }
    
    private static func extractPointer(_ line: String) -> String? {
        // "1 HUSB @I1@" → "I1"
        guard let at1 = line.firstIndex(of: "@") else { return nil }
        let after = line[line.index(after: at1)...]
        guard let at2 = after.firstIndex(of: "@") else { return nil }
        return String(after[..<at2])
    }
    
    private static func extractLevel(_ line: String) -> Int {
        guard let first = line.first, let level = Int(String(first)) else { return 0 }
        return level
    }
    
    private static func extractTag(_ line: String, level: Int) -> String {
        // "2 DATE 1 JAN 1990" → "DATE"
        let prefix = "\(level) "
        guard line.hasPrefix(prefix) else { return "" }
        let rest = String(line.dropFirst(prefix.count))
        // Skip xref if present
        if rest.hasPrefix("@") {
            if let end = rest.dropFirst().firstIndex(of: "@") {
                let afterXref = rest[rest.index(after: end)...].trimmingCharacters(in: .whitespaces)
                return String(afterXref.prefix(while: { !$0.isWhitespace }))
            }
        }
        return String(rest.prefix(while: { !$0.isWhitespace }))
    }
    
    private static func extractValue(_ line: String, level: Int, tag: String) -> String {
        let prefix = "\(level) "
        guard line.hasPrefix(prefix) else { return "" }
        let rest = String(line.dropFirst(prefix.count))
        // Find value after tag
        if let range = rest.range(of: tag) {
            let afterTag = rest[range.upperBound...].trimmingCharacters(in: .whitespaces)
            return afterTag
        }
        return ""
    }
    
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
