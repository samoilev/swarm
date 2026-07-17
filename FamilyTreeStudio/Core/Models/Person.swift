import Foundation
import Observation

@Observable
public final class Person: Identifiable, Codable, Hashable {
    public var id: UUID
    public var givenNames: String { didSet { synchronizePrimaryNameFromLegacy() } }
    public var patronymic: String? { didSet { synchronizePrimaryNameFromLegacy() } }
    public var surname: String { didSet { synchronizePrimaryNameFromLegacy() } }
    public var maidenName: String? { didSet { synchronizePrimaryNameFromLegacy() } }
    public var sex: Sex

    public var birthDate: String? { didSet { synchronizeDateFromLegacy(.birth, value: birthDate) } }
    public var birthPlace: String? { didSet { synchronizePlaceFromLegacy(.birth, value: birthPlace, lat: birthLat, lon: birthLon) } }

    public var deathDate: String? { didSet { synchronizeDateFromLegacy(.death, value: deathDate) } }
    public var deathPlace: String? { didSet { synchronizePlaceFromLegacy(.death, value: deathPlace, lat: deathLat, lon: deathLon) } }
    public var isLiving: Bool

    public var burialPlace: String? { didSet { synchronizePlaceFromLegacy(.burial, value: burialPlace, lat: burialLat, lon: burialLon) } }

    public var occupation: String? { didSet { synchronizeValueFromLegacy(.occupation, value: occupation) } }
    public var education: String? { didSet { synchronizeValueFromLegacy(.education, value: education) } }
    public var notes: String?
    public internal(set) var sources: [String]

    /// Canonical structured genealogy records. The legacy scalar properties above are
    /// compatibility accessors during the staged UI migration and update these arrays
    /// through their observers.
    public var names: [PersonName]
    public var events: [GenealogyEvent]
    public var citations: [Citation]
    @ObservationIgnored private var isSynchronizingStructured = false

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
    public var birthLat: Double? { didSet { synchronizePlaceFromLegacy(.birth, value: birthPlace, lat: birthLat, lon: birthLon) } }
    public var birthLon: Double? { didSet { synchronizePlaceFromLegacy(.birth, value: birthPlace, lat: birthLat, lon: birthLon) } }
    public var deathLat: Double? { didSet { synchronizePlaceFromLegacy(.death, value: deathPlace, lat: deathLat, lon: deathLon) } }
    public var deathLon: Double? { didSet { synchronizePlaceFromLegacy(.death, value: deathPlace, lat: deathLat, lon: deathLon) } }
    // Precise grave/burial coordinates (entered manually, not geocoded)
    public var burialLat: Double? { didSet { synchronizePlaceFromLegacy(.burial, value: burialPlace, lat: burialLat, lon: burialLon) } }
    public var burialLon: Double? { didSet { synchronizePlaceFromLegacy(.burial, value: burialPlace, lat: burialLat, lon: burialLon) } }

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
        self.names = [PersonName(
            givenNames: givenNames,
            patronymic: patronymic,
            surname: surname,
            maidenName: maidenName
        )]
        self.events = Self.initialEvents(
            birthDate: birthDate,
            birthPlace: birthPlace,
            deathDate: deathDate,
            deathPlace: deathPlace,
            burialPlace: burialPlace,
            occupation: occupation,
            education: education
        )
        self.citations = []
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

    // MARK: - Structured compatibility

    public func event(ofKind kind: GenealogyEvent.Kind) -> GenealogyEvent? {
        events.first(where: { $0.kind == kind })
    }

    public func replaceEvent(_ event: GenealogyEvent) {
        isSynchronizingStructured = true
        defer { isSynchronizingStructured = false }
        if let index = events.firstIndex(where: { $0.id == event.id || $0.kind == event.kind }) {
            events[index] = event
        } else {
            events.append(event)
        }
        applyStructuredEventToLegacy(event)
    }

    /// Called by the GEDCOM parser so qualifiers/ranges remain canonical while the
    /// old UI can continue displaying its normalized compatibility value.
    public func setStructuredDate(_ date: GenealogyDate?, for kind: GenealogyEvent.Kind) {
        isSynchronizingStructured = true
        defer { isSynchronizingStructured = false }
        updateEvent(kind: kind) { $0.date = date }
    }

    public func setStructuredPlace(_ place: PlaceReference?, for kind: GenealogyEvent.Kind) {
        isSynchronizingStructured = true
        defer { isSynchronizingStructured = false }
        updateEvent(kind: kind) { $0.place = place }
        switch kind {
        case .birth:
            birthPlace = place?.displayName; birthLat = place?.latitude; birthLon = place?.longitude
        case .death:
            deathPlace = place?.displayName; deathLat = place?.latitude; deathLon = place?.longitude
        case .burial:
            burialPlace = place?.displayName; burialLat = place?.latitude; burialLon = place?.longitude
        default: break
        }
    }

    private func synchronizePrimaryNameFromLegacy() {
        guard !isSynchronizingStructured else { return }
        if names.isEmpty {
            names = [PersonName()]
        }
        let index = names.firstIndex(where: \.isPrimary) ?? 0
        names[index].isPrimary = true
        names[index].givenNames = givenNames
        names[index].patronymic = patronymic
        names[index].surname = surname
        names[index].maidenName = maidenName
    }

    private func synchronizeDateFromLegacy(_ kind: GenealogyEvent.Kind, value: String?) {
        guard !isSynchronizingStructured else { return }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        updateEvent(kind: kind) { event in
            event.date = (trimmed?.isEmpty == false) ? GenealogyDate(userInput: trimmed!) : nil
        }
        removeEventIfEmpty(kind)
    }

    private func synchronizePlaceFromLegacy(_ kind: GenealogyEvent.Kind, value: String?, lat: Double?, lon: Double?) {
        guard !isSynchronizingStructured else { return }
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updateEvent(kind: kind) { event in
            if trimmed.isEmpty, lat == nil, lon == nil {
                event.place = nil
            } else {
                var place = event.place ?? PlaceReference(displayName: trimmed, isCustom: true)
                place.displayName = trimmed
                place.latitude = lat
                place.longitude = lon
                if place.datasetID == nil { place.isCustom = true }
                event.place = place
            }
        }
        removeEventIfEmpty(kind)
    }

    private func synchronizeValueFromLegacy(_ kind: GenealogyEvent.Kind, value: String?) {
        guard !isSynchronizingStructured else { return }
        updateEvent(kind: kind) { $0.value = value }
        removeEventIfEmpty(kind)
    }

    private func updateEvent(kind: GenealogyEvent.Kind, mutate: (inout GenealogyEvent) -> Void) {
        if let index = events.firstIndex(where: { $0.kind == kind }) {
            mutate(&events[index])
        } else {
            var event = GenealogyEvent(kind: kind)
            mutate(&event)
            events.append(event)
        }
    }

    private func removeEventIfEmpty(_ kind: GenealogyEvent.Kind) {
        events.removeAll { event in
            event.kind == kind && event.value == nil && event.date == nil && event.place == nil &&
                event.notes == nil && event.citations.isEmpty && event.mediaIDs.isEmpty && event.rawGEDCOMBranches.isEmpty
        }
    }

    private func applyStructuredEventToLegacy(_ event: GenealogyEvent) {
        switch event.kind {
        case .birth:
            birthDate = event.date?.displayValue; birthPlace = event.place?.displayName
            birthLat = event.place?.latitude; birthLon = event.place?.longitude
        case .death:
            deathDate = event.date?.displayValue; deathPlace = event.place?.displayName
            deathLat = event.place?.latitude; deathLon = event.place?.longitude
        case .burial:
            burialPlace = event.place?.displayName; burialLat = event.place?.latitude; burialLon = event.place?.longitude
        case .occupation: occupation = event.value
        case .education: education = event.value
        default: break
        }
    }

    private static func initialEvents(
        birthDate: String?,
        birthPlace: String?,
        deathDate: String?,
        deathPlace: String?,
        burialPlace: String?,
        occupation: String?,
        education: String?
    ) -> [GenealogyEvent] {
        var result: [GenealogyEvent] = []
        func add(_ kind: GenealogyEvent.Kind, date: String? = nil, place: String? = nil, value: String? = nil) {
            let trimmedDate = date?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedPlace = place?.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedValue = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedDate?.isEmpty == false || trimmedPlace?.isEmpty == false || trimmedValue?.isEmpty == false else { return }
            result.append(GenealogyEvent(
                kind: kind,
                value: trimmedValue,
                date: trimmedDate.map { GenealogyDate(userInput: $0) },
                place: trimmedPlace.map { PlaceReference(displayName: $0, isCustom: true) }
            ))
        }
        add(.birth, date: birthDate, place: birthPlace)
        add(.death, date: deathDate, place: deathPlace)
        add(.burial, place: burialPlace)
        add(.occupation, value: occupation)
        add(.education, value: education)
        return result
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
        case names, events, citations
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
        names = try c.decodeIfPresent([PersonName].self, forKey: .names) ?? [PersonName(
            givenNames: c.decode(String.self, forKey: .givenNames),
            patronymic: c.decodeIfPresent(String.self, forKey: .patronymic),
            surname: c.decode(String.self, forKey: .surname),
            maidenName: c.decodeIfPresent(String.self, forKey: .maidenName)
        )]
        events = try c.decodeIfPresent([GenealogyEvent].self, forKey: .events) ?? Self.initialEvents(
            birthDate: c.decodeIfPresent(String.self, forKey: .birthDate),
            birthPlace: c.decodeIfPresent(String.self, forKey: .birthPlace),
            deathDate: c.decodeIfPresent(String.self, forKey: .deathDate),
            deathPlace: c.decodeIfPresent(String.self, forKey: .deathPlace),
            burialPlace: c.decodeIfPresent(String.self, forKey: .burialPlace),
            occupation: c.decodeIfPresent(String.self, forKey: .occupation),
            education: c.decodeIfPresent(String.self, forKey: .education)
        )
        citations = try c.decodeIfPresent([Citation].self, forKey: .citations) ?? []
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
        try c.encode(names, forKey: .names)
        if !events.isEmpty { try c.encode(events, forKey: .events) }
        if !citations.isEmpty { try c.encode(citations, forKey: .citations) }
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
