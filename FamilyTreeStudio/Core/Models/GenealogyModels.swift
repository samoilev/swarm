import Foundation

// MARK: - Structured dates

/// A GEDCOM date that keeps the original text as well as a parsed representation.
/// Imported text is never discarded merely because the app cannot interpret it.
public struct GenealogyDate: Codable, Hashable, Sendable {
    public enum Qualifier: String, Codable, CaseIterable, Sendable {
        case exact
        case about
        case before
        case after
        case estimated
        case calculated
        case between
        case fromTo

        public var gedcomPrefix: String {
            switch self {
            case .exact: ""
            case .about: "ABT"
            case .before: "BEF"
            case .after: "AFT"
            case .estimated: "EST"
            case .calculated: "CAL"
            case .between: "BET"
            case .fromTo: "FROM"
            }
        }

        public var displayName: String {
            switch self {
            case .exact: L10n.tr("Точная")
            case .about: L10n.tr("Около")
            case .before: L10n.tr("До")
            case .after: L10n.tr("После")
            case .estimated: L10n.tr("Предположительно")
            case .calculated: L10n.tr("Вычислено")
            case .between: L10n.tr("Между")
            case .fromTo: L10n.tr("С — по")
            }
        }
    }

    public struct PartialDate: Codable, Hashable, Sendable {
        public var year: Int
        public var month: Int?
        public var day: Int?

        public init(year: Int, month: Int? = nil, day: Int? = nil) {
            self.year = year
            self.month = month
            self.day = day
        }

        public var isValid: Bool {
            guard year > 0 else { return false }
            guard let month else { return day == nil }
            guard (1 ... 12).contains(month) else { return false }
            guard let day else { return true }
            var components = DateComponents()
            components.calendar = Calendar(identifier: .gregorian)
            components.timeZone = TimeZone(secondsFromGMT: 0)
            components.year = year
            components.month = month
            components.day = day
            guard let date = components.date,
                  let check = components.calendar?.dateComponents([.year, .month, .day], from: date) else {
                return false
            }
            return check.year == year && check.month == month && check.day == day
        }

        fileprivate var gedcomValue: String {
            let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
            if let month, let day {
                return "\(day) \(months[month - 1]) \(year)"
            }
            if let month { return "\(months[month - 1]) \(year)" }
            return String(year)
        }

        public var displayValue: String {
            if let month, let day { return String(format: "%02d.%02d.%04d", day, month, year) }
            if let month { return String(format: "%02d.%04d", month, year) }
            return String(year)
        }
    }

    /// Exact imported text, excluding the GEDCOM `DATE` tag itself.
    public var rawValue: String
    public var qualifier: Qualifier
    public var start: PartialDate?
    public var end: PartialDate?
    public var phrase: String?

    public init(
        rawValue: String,
        qualifier: Qualifier = .exact,
        start: PartialDate? = nil,
        end: PartialDate? = nil,
        phrase: String? = nil
    ) {
        self.rawValue = rawValue
        self.qualifier = qualifier
        self.start = start
        self.end = end
        self.phrase = phrase
    }

    public init(rawGEDCOM value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        rawValue = trimmed

        let upper = trimmed.uppercased()
        if upper.hasPrefix("BET "), let range = Self.splitRange(String(trimmed.dropFirst(4)), separator: " AND ") {
            qualifier = .between
            start = Self.parsePartial(range.0)
            end = Self.parsePartial(range.1)
            phrase = nil
        } else if upper.hasPrefix("FROM "), let range = Self.splitRange(String(trimmed.dropFirst(5)), separator: " TO ") {
            qualifier = .fromTo
            start = Self.parsePartial(range.0)
            end = Self.parsePartial(range.1)
            phrase = nil
        } else {
            let prefixes: [(String, Qualifier)] = [
                ("ABT ", .about), ("BEF ", .before), ("AFT ", .after),
                ("EST ", .estimated), ("CAL ", .calculated),
            ]
            if let match = prefixes.first(where: { upper.hasPrefix($0.0) }) {
                qualifier = match.1
                let body = String(trimmed.dropFirst(match.0.count))
                start = Self.parsePartial(body)
                end = nil
                phrase = start == nil ? body : nil
            } else {
                qualifier = .exact
                start = Self.parsePartial(trimmed)
                end = nil
                phrase = start == nil && !trimmed.isEmpty ? trimmed : nil
            }
        }
    }

    public init(userInput value: String, qualifier: Qualifier = .exact, endValue: String? = nil) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        self.qualifier = qualifier
        start = Self.parsePartial(trimmed)
        end = endValue.flatMap(Self.parsePartial)
        phrase = start == nil && !trimmed.isEmpty ? trimmed : nil
        rawValue = ""
        rawValue = canonicalGEDCOMValue
    }

    public var isValid: Bool {
        guard phrase == nil, let start, start.isValid else { return false }
        switch qualifier {
        case .between, .fromTo:
            guard let end, end.isValid else { return false }
            return Self.sortKey(start) <= Self.sortKey(end)
        default:
            return end == nil
        }
    }

    /// Canonical GEDCOM output for edited dates. Unparseable imported text is emitted
    /// verbatim so an unrelated edit cannot destroy it.
    public var canonicalGEDCOMValue: String {
        guard let start else { return rawValue }
        switch qualifier {
        case .exact:
            return start.gedcomValue
        case .between:
            guard let end else { return rawValue }
            return "BET \(start.gedcomValue) AND \(end.gedcomValue)"
        case .fromTo:
            guard let end else { return rawValue }
            return "FROM \(start.gedcomValue) TO \(end.gedcomValue)"
        default:
            return "\(qualifier.gedcomPrefix) \(start.gedcomValue)"
        }
    }

    public var displayValue: String {
        guard let start else { return rawValue }
        let prefix = switch qualifier {
        case .exact: ""
        case .about: L10n.tr("ок. ")
        case .before: L10n.tr("до ")
        case .after: L10n.tr("после ")
        case .estimated: L10n.tr("предп. ")
        case .calculated: L10n.tr("выч. ")
        case .between: L10n.tr("между ")
        case .fromTo: L10n.tr("с ")
        }
        if let end {
            let separator = qualifier == .between ? L10n.tr(" и ") : L10n.tr(" по ")
            return prefix + start.displayValue + separator + end.displayValue
        }
        return prefix + start.displayValue
    }

    public var year: Int? { start?.year }

    private static func parsePartial(_ input: String) -> PartialDate? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let numeric = trimmed.split(separator: ".").compactMap { Int($0) }
        if numeric.count == 3, !trimmed.contains(where: { !$0.isNumber && $0 != "." }) {
            return PartialDate(year: numeric[2], month: numeric[1], day: numeric[0])
        }
        if numeric.count == 2, !trimmed.contains(where: { !$0.isNumber && $0 != "." }) {
            return PartialDate(year: numeric[1], month: numeric[0])
        }
        if numeric.count == 1, numeric[0] > 0, trimmed.allSatisfy(\.isNumber) {
            return PartialDate(year: numeric[0])
        }

        let parts = trimmed.uppercased().split(separator: " ").map(String.init)
        let months = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
        if parts.count == 3,
           let day = Int(parts[0]),
           let monthIndex = months.firstIndex(of: parts[1]),
           let year = Int(parts[2]) {
            return PartialDate(year: year, month: monthIndex + 1, day: day)
        }
        if parts.count == 2,
           let monthIndex = months.firstIndex(of: parts[0]),
           let year = Int(parts[1]) {
            return PartialDate(year: year, month: monthIndex + 1)
        }
        return nil
    }

    private static func splitRange(_ value: String, separator: String) -> (String, String)? {
        guard let range = value.uppercased().range(of: separator) else { return nil }
        let offset = value.distance(from: value.startIndex, to: range.lowerBound)
        let startIndex = value.index(value.startIndex, offsetBy: offset)
        let endIndex = value.index(startIndex, offsetBy: separator.count)
        return (String(value[..<startIndex]), String(value[endIndex...]))
    }

    private static func sortKey(_ date: PartialDate) -> Int {
        date.year * 10000 + (date.month ?? 0) * 100 + (date.day ?? 0)
    }
}

// MARK: - Names, places, evidence and events

public struct PlaceReference: Codable, Hashable, Sendable {
    public var datasetID: String?
    public var displayName: String
    public var latitude: Double?
    public var longitude: Double?
    public var isCustom: Bool

    public init(
        datasetID: String? = nil,
        displayName: String,
        latitude: Double? = nil,
        longitude: Double? = nil,
        isCustom: Bool = false
    ) {
        self.datasetID = datasetID
        self.displayName = displayName
        self.latitude = latitude
        self.longitude = longitude
        self.isCustom = isCustom
    }

    public var hasValidCoordinates: Bool {
        guard let latitude, let longitude else { return false }
        return (-90 ... 90).contains(latitude) && (-180 ... 180).contains(longitude)
    }
}

public struct Citation: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var sourceID: UUID
    public var page: String?
    public var detail: String?
    public var transcription: String?
    public var confidence: String?
    public var notes: String?
    public var rawGEDCOMBranches: [[String]]

    public init(
        id: UUID = UUID(),
        sourceID: UUID,
        page: String? = nil,
        detail: String? = nil,
        transcription: String? = nil,
        confidence: String? = nil,
        notes: String? = nil,
        rawGEDCOMBranches: [[String]] = []
    ) {
        self.id = id
        self.sourceID = sourceID
        self.page = page
        self.detail = detail
        self.transcription = transcription
        self.confidence = confidence
        self.notes = notes
        self.rawGEDCOMBranches = rawGEDCOMBranches
    }
}

public struct SourceRecord: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var gedcomXref: String?
    public var title: String
    public var author: String?
    public var publication: String?
    public var repository: String?
    public var callNumber: String?
    public var notes: String?
    public var rawGEDCOMBranches: [[String]]

    public init(
        id: UUID = UUID(),
        gedcomXref: String? = nil,
        title: String,
        author: String? = nil,
        publication: String? = nil,
        repository: String? = nil,
        callNumber: String? = nil,
        notes: String? = nil,
        rawGEDCOMBranches: [[String]] = []
    ) {
        self.id = id
        self.gedcomXref = gedcomXref
        self.title = title
        self.author = author
        self.publication = publication
        self.repository = repository
        self.callNumber = callNumber
        self.notes = notes
        self.rawGEDCOMBranches = rawGEDCOMBranches
    }
}

public struct PersonName: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case birth
        case married
        case alsoKnownAs
        case religious
        case immigration
        case other
    }

    public var id: UUID
    public var kind: Kind
    public var isPrimary: Bool
    public var givenNames: String
    public var patronymic: String?
    public var surname: String
    public var maidenName: String?
    public var prefix: String?
    public var suffix: String?
    public var nickname: String?
    public var citations: [Citation]
    public var rawGEDCOMBranches: [[String]]

    public init(
        id: UUID = UUID(),
        kind: Kind = .birth,
        isPrimary: Bool = true,
        givenNames: String = "",
        patronymic: String? = nil,
        surname: String = "",
        maidenName: String? = nil,
        prefix: String? = nil,
        suffix: String? = nil,
        nickname: String? = nil,
        citations: [Citation] = [],
        rawGEDCOMBranches: [[String]] = []
    ) {
        self.id = id
        self.kind = kind
        self.isPrimary = isPrimary
        self.givenNames = givenNames
        self.patronymic = patronymic
        self.surname = surname
        self.maidenName = maidenName
        self.prefix = prefix
        self.suffix = suffix
        self.nickname = nickname
        self.citations = citations
        self.rawGEDCOMBranches = rawGEDCOMBranches
    }
}

public struct GenealogyEvent: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Sendable {
        case birth
        case death
        case burial
        case occupation
        case education
        case marriage
        case partnership
        case separation
        case divorce
        case residence
        case immigration
        case military
        case custom

        public var gedcomTag: String {
            switch self {
            case .birth: "BIRT"
            case .death: "DEAT"
            case .burial: "BURI"
            case .occupation: "OCCU"
            case .education: "EDUC"
            case .marriage: "MARR"
            case .divorce: "DIV"
            case .residence: "RESI"
            case .immigration: "IMMI"
            case .military: "_MILT"
            case .partnership: "_PART"
            case .separation: "_SEPR"
            case .custom: "EVEN"
            }
        }
    }

    public var id: UUID
    public var kind: Kind
    public var typeName: String?
    public var value: String?
    public var date: GenealogyDate?
    public var place: PlaceReference?
    public var notes: String?
    public var citations: [Citation]
    public var mediaIDs: [String]
    public var rawGEDCOMBranches: [[String]]

    public init(
        id: UUID = UUID(),
        kind: Kind,
        typeName: String? = nil,
        value: String? = nil,
        date: GenealogyDate? = nil,
        place: PlaceReference? = nil,
        notes: String? = nil,
        citations: [Citation] = [],
        mediaIDs: [String] = [],
        rawGEDCOMBranches: [[String]] = []
    ) {
        self.id = id
        self.kind = kind
        self.typeName = typeName
        self.value = value
        self.date = date
        self.place = place
        self.notes = notes
        self.citations = citations
        self.mediaIDs = mediaIDs
        self.rawGEDCOMBranches = rawGEDCOMBranches
    }
}

public enum ParentageKind: String, Codable, CaseIterable, Sendable {
    case biological
    case adoptive
    case foster
    case step
    case uncertain

    public var displayName: String {
        switch self {
        case .biological: L10n.tr("Биологическая")
        case .adoptive: L10n.tr("Приёмная")
        case .foster: L10n.tr("Опекунская")
        case .step: L10n.tr("Сводная")
        case .uncertain: L10n.tr("Предполагаемая")
        }
    }

    public var gedcomValue: String {
        switch self {
        case .biological: "birth"
        case .adoptive: "adopted"
        case .foster: "foster"
        case .step: "step"
        case .uncertain: "uncertain"
        }
    }

    public init(gedcomValue: String) {
        switch gedcomValue.lowercased() {
        case "birth", "biological": self = .biological
        case "adopted", "adoptive": self = .adoptive
        case "foster": self = .foster
        case "step": self = .step
        default: self = .uncertain
        }
    }
}

public struct ParentLink: Identifiable, Codable, Hashable, Sendable {
    public var id: UUID
    public var parentID: UUID
    public var childID: UUID
    public var unionID: UUID?
    public var kind: ParentageKind
    public var citations: [Citation]
    public var notes: String?

    public init(
        id: UUID = UUID(),
        parentID: UUID,
        childID: UUID,
        unionID: UUID? = nil,
        kind: ParentageKind = .biological,
        citations: [Citation] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.parentID = parentID
        self.childID = childID
        self.unionID = unionID
        self.kind = kind
        self.citations = citations
        self.notes = notes
    }
}
