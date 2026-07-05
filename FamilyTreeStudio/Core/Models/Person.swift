import Foundation
import Observation

@Observable
public final class Person: Identifiable, Codable, Hashable {
    public var id: UUID
    public var givenNames: String
    public var patronymic: String?
    public var surname: String
    public var maidenName: String?
    public var sex: Sex

    public var birthDate: String?
    public var birthPlace: String?

    public var deathDate: String?
    public var deathPlace: String?
    public var isLiving: Bool

    public var burialPlace: String?

    public var occupation: String?
    public var education: String?
    public var notes: String?
    public var sources: [String]

    /// The portrait's filename inside the tree's `Media/` folder. The bytes are loaded
    /// lazily (see `photoData`) so opening a library doesn't pull every photo into RAM.
    public var photoFilename: String?
    /// The `Media/` folder to lazily load the portrait from. Transient — set by the
    /// parser/store, never persisted; restored after an undo via `TreeStore`.
    @ObservationIgnored public var mediaFolderURL: URL? = nil
    /// True once the portrait bytes changed this session and must be rewritten on save.
    @ObservationIgnored public var photoIsDirty = false
    /// Lazy portrait backing: `.none` = not loaded yet; `.some(x)` = loaded (x may be nil).
    @ObservationIgnored private var loadedPhoto: Data?? = nil

    /// The portrait bytes. Reading loads them from `Media/` on first access (and caches
    /// the result); writing marks the photo dirty so the next save rewrites it. Views use
    /// this exactly as before — the on-disk backing is invisible to them.
    public var photoData: Data? {
        get {
            if let loaded = loadedPhoto { return loaded }
            var bytes: Data?
            if let name = photoFilename, let folder = mediaFolderURL {
                bytes = try? Data(contentsOf: folder.appendingPathComponent(name))
            }
            loadedPhoto = .some(bytes)
            return bytes
        }
        set {
            loadedPhoto = .some(newValue)
            photoIsDirty = true
        }
    }

    /// Whether a portrait exists without forcing a disk load (a filename on disk, or
    /// freshly-set bytes in memory). Used by the serializer to emit the OBJE reference.
    public var hasPhoto: Bool {
        if photoFilename != nil { return true }
        if case .some(.some) = loadedPhoto { return true }
        return false
    }

    /// Files attached to this person. The bytes live on disk in the tree's
    /// `Attachments/` folder; these entries only hold the linking metadata.
    public var attachments: [Attachment] = []

    // Cached coordinates for map pins
    public var birthLat: Double?
    public var birthLon: Double?
    public var deathLat: Double?
    public var deathLon: Double?
    // Precise grave/burial coordinates (entered manually, not geocoded)
    public var burialLat: Double?
    public var burialLon: Double?

    // MARK: - GEDCOM interop preservation

    // These keep the parts of an imported record that the app doesn't model, so a
    // parse→edit→save cycle no longer destroys foreign data (see GEDCOMParser/Serializer).

    /// The original `@I..@` xref from an imported file. Reused on export so any
    /// cross-references inside preserved unknown structures still resolve. Nil for
    /// app-created people (they get a fresh xref).
    public var gedcomXref: String?
    /// Whole level-1 branches (a tag the app doesn't model plus its descendants),
    /// kept as raw GEDCOM lines and re-emitted verbatim at the end of the INDI record.
    public var unknownBranches: [[String]] = []
    /// Unmodeled sub-lines of a modeled event (e.g. `2 NOTE`/`2 SOUR` under BIRT),
    /// keyed by event tag ("BIRT"/"DEAT"/"BURI"), re-emitted inside that event.
    public var eventExtras: [String: [String]] = [:]

    public var createdAt: Date
    public var updatedAt: Date

    public enum Sex: String, Codable, CaseIterable {
        case male = "M"
        case female = "F"
        case unknown = "U"

        public var displayName: String {
            switch self {
            case .male: "Муж"
            case .female: "Жен"
            case .unknown: "Не указан"
            }
        }

        public var russianName: String {
            displayName
        }
    }

    public init(
        givenNames: String = "",
        patronymic: String? = nil,
        surname: String = "",
        maidenName: String? = nil,
        sex: Sex = .unknown,
        birthDate: String? = nil,
        birthPlace: String? = nil,
        deathDate: String? = nil,
        deathPlace: String? = nil,
        isLiving: Bool = true,
        burialPlace: String? = nil,
        occupation: String? = nil,
        education: String? = nil,
        notes: String? = nil,
        sources: [String] = [],
        photoData: Data? = nil
    ) {
        self.id = UUID()
        self.givenNames = givenNames
        self.patronymic = patronymic
        self.surname = surname
        self.maidenName = maidenName
        self.sex = sex
        self.birthDate = birthDate
        self.birthPlace = birthPlace
        self.deathDate = deathDate
        self.deathPlace = deathPlace
        self.isLiving = isLiving
        self.burialPlace = burialPlace
        self.occupation = occupation
        self.education = education
        self.notes = notes
        self.sources = sources
        // Only touch photo state when bytes are actually supplied, so a plain new
        // person isn't flagged dirty (which would force an unnecessary photo rewrite).
        if let photoData { loadedPhoto = .some(photoData); photoIsDirty = true }
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    public var fullName: String {
        [givenNames.isEmpty ? nil : givenNames, patronymic, surname.isEmpty ? nil : surname]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    /// Имя в формате «Фамилия Имя Отчество» — для списков и сортировки по алфавиту.
    public var listName: String {
        [surname.isEmpty ? nil : surname, givenNames.isEmpty ? nil : givenNames, patronymic]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    public var displaySurname: String {
        surname.isEmpty ? (maidenName ?? "") : surname
    }

    public var lifespan: String {
        let birthComp = FamilyDate.parse(birthDate)
        let deathComp = FamilyDate.parse(deathDate)
        let birthStr = birthComp.year.map(String.init) ?? ""
        let deathStr = deathComp.year.map(String.init) ?? ""

        if birthStr.isEmpty && deathStr.isEmpty { return "" }

        if !isLiving && deathDate != nil {
            let base = "\(birthStr.isEmpty ? "?" : birthStr)–\(deathStr.isEmpty ? "?" : deathStr)"
            if let result = FamilyDate.calculateAge(birth: birthDate, death: deathDate) {
                let approx = result.approximate ? "~" : ""
                return "\(base) (\(approx)\(result.years))"
            }
            return base
        }
        if !birthStr.isEmpty {
            if let result = FamilyDate.calculateAge(birth: birthDate, death: nil) {
                let approx = result.approximate ? "~" : ""
                return "р. \(birthStr) (\(approx)\(result.years))"
            }
            return "р. \(birthStr)"
        }
        return ""
    }

    // MARK: - Hashable

    public static func == (lhs: Person, rhs: Person) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, givenNames, patronymic, surname, maidenName, sex
        case birthDate, birthPlace, deathDate, deathPlace, isLiving
        case burialPlace, occupation, education, notes, sources, photoData, photoFilename, attachments
        case birthLat, birthLon, deathLat, deathLon, burialLat, burialLon
        case gedcomXref, unknownBranches, eventExtras
        case createdAt, updatedAt
    }

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        givenNames = try c.decode(String.self, forKey: .givenNames)
        patronymic = try c.decodeIfPresent(String.self, forKey: .patronymic)
        surname = try c.decode(String.self, forKey: .surname)
        maidenName = try c.decodeIfPresent(String.self, forKey: .maidenName)
        sex = try c.decode(Sex.self, forKey: .sex)
        birthDate = try c.decodeIfPresent(String.self, forKey: .birthDate)
        birthPlace = try c.decodeIfPresent(String.self, forKey: .birthPlace)
        deathDate = try c.decodeIfPresent(String.self, forKey: .deathDate)
        deathPlace = try c.decodeIfPresent(String.self, forKey: .deathPlace)
        isLiving = try c.decode(Bool.self, forKey: .isLiving)
        burialPlace = try c.decodeIfPresent(String.self, forKey: .burialPlace)
        occupation = try c.decodeIfPresent(String.self, forKey: .occupation)
        education = try c.decodeIfPresent(String.self, forKey: .education)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        sources = try c.decode([String].self, forKey: .sources)
        photoFilename = try c.decodeIfPresent(String.self, forKey: .photoFilename)
        // Legacy JSON stored the bytes inline; if present, take them (marked dirty so
        // the next save writes them into Media/ and the GEDCOM). New snapshots carry
        // only the filename, keeping undo/snapshots free of megabytes of photo data.
        if let legacy = try c.decodeIfPresent(Data.self, forKey: .photoData) {
            loadedPhoto = .some(legacy); photoIsDirty = true
        }
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        birthLat = try c.decodeIfPresent(Double.self, forKey: .birthLat)
        birthLon = try c.decodeIfPresent(Double.self, forKey: .birthLon)
        deathLat = try c.decodeIfPresent(Double.self, forKey: .deathLat)
        deathLon = try c.decodeIfPresent(Double.self, forKey: .deathLon)
        burialLat = try c.decodeIfPresent(Double.self, forKey: .burialLat)
        burialLon = try c.decodeIfPresent(Double.self, forKey: .burialLon)
        gedcomXref = try c.decodeIfPresent(String.self, forKey: .gedcomXref)
        unknownBranches = try c.decodeIfPresent([[String]].self, forKey: .unknownBranches) ?? []
        eventExtras = try c.decodeIfPresent([String: [String]].self, forKey: .eventExtras) ?? [:]
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(givenNames, forKey: .givenNames)
        try c.encodeIfPresent(patronymic, forKey: .patronymic)
        try c.encode(surname, forKey: .surname)
        try c.encodeIfPresent(maidenName, forKey: .maidenName)
        try c.encode(sex, forKey: .sex)
        try c.encodeIfPresent(birthDate, forKey: .birthDate)
        try c.encodeIfPresent(birthPlace, forKey: .birthPlace)
        try c.encodeIfPresent(deathDate, forKey: .deathDate)
        try c.encodeIfPresent(deathPlace, forKey: .deathPlace)
        try c.encode(isLiving, forKey: .isLiving)
        try c.encodeIfPresent(burialPlace, forKey: .burialPlace)
        try c.encodeIfPresent(occupation, forKey: .occupation)
        try c.encodeIfPresent(education, forKey: .education)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(sources, forKey: .sources)
        // Persist only the portrait's filename, never the bytes — this keeps undo
        // snapshots (which use Codable) free of megabytes of image data.
        try c.encodeIfPresent(photoFilename, forKey: .photoFilename)
        if !attachments.isEmpty { try c.encode(attachments, forKey: .attachments) }
        try c.encodeIfPresent(birthLat, forKey: .birthLat)
        try c.encodeIfPresent(birthLon, forKey: .birthLon)
        try c.encodeIfPresent(deathLat, forKey: .deathLat)
        try c.encodeIfPresent(deathLon, forKey: .deathLon)
        try c.encodeIfPresent(burialLat, forKey: .burialLat)
        try c.encodeIfPresent(burialLon, forKey: .burialLon)
        try c.encodeIfPresent(gedcomXref, forKey: .gedcomXref)
        if !unknownBranches.isEmpty { try c.encode(unknownBranches, forKey: .unknownBranches) }
        if !eventExtras.isEmpty { try c.encode(eventExtras, forKey: .eventExtras) }
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
