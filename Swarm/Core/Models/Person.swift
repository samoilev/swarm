import Foundation
import Observation

@Observable
public final class Person: Identifiable, Codable, Hashable {
    public var id: UUID
    public var sex: Sex
    public var isLiving: Bool
    public var notes: String?
    public internal(set) var sources: [String]

    /// Canonical structured genealogy records — the single source of truth. The
    /// legacy scalar accessors (`givenNames`, `birthDate`, `birthLat`, …) further
    /// down are computed views over these arrays, not separate storage.
    public var names: [PersonName]
    public var events: [GenealogyEvent]
    public var citations: [Citation]

    /// The portrait's filename inside the tree's `Media/` folder. The bytes are loaded
    /// lazily (see `photoData`) so opening a library doesn't pull every photo into RAM.
    public var photoFilename: String?
    /// The `Media/` folder to lazily load the portrait from. Transient — set by the
    /// parser/store, never persisted; restored after an undo via `TreeStore`.
    /// Pointing at a new folder drops a cached read, since a lookup made before the
    /// folder was known cached "no portrait" from a place that could never have one.
    /// Unsaved bytes stay: they are the truth until the next save writes them out.
    @ObservationIgnored public var mediaFolderURL: URL? = nil {
        didSet {
            guard mediaFolderURL != oldValue, !photoIsDirty else { return }
            loadedPhoto = nil
        }
    }

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
            photoRevision &+= 1
            // Removing the portrait must also drop the on-disk reference; otherwise
            // hasPhoto stays true, the exporter re-emits OBJE, and the next load
            // silently restores the deleted photo from Media/.
            if newValue == nil { photoFilename = nil }
        }
    }

    /// Bumped whenever the portrait changes. Transient, never persisted: it exists so
    /// a thumbnail cache can be keyed without reading the bytes back, which is what
    /// forced the full-size image to stay resident for every card on the canvas.
    @ObservationIgnored public private(set) var photoRevision = 0

    /// The portrait bytes *without* caching them on this person. The canvas keeps
    /// only downsampled thumbnails; letting it go through `photoData` pinned a
    /// full-size JPEG per drawn card, which is precisely what the thumbnailer exists
    /// to avoid. Unsaved in-memory bytes still win over what is on disk.
    public func photoDataUncached() -> Data? {
        if let loaded = loadedPhoto { return loaded }
        guard let name = photoFilename, let folder = mediaFolderURL else { return nil }
        return try? Data(contentsOf: folder.appendingPathComponent(name))
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

    /// Web links attached to this person (archive records, memorial pages).
    public var links: [WebLink] = []

    // MARK: - Legacy accessors (computed views over `names`/`events`)

    // These keep the pre-structured call sites compiling and behave exactly like
    // the old stored fields did in their steady state; the storage itself is gone.

    public var givenNames: String {
        get { primaryName?.givenNames ?? "" }
        set { withPrimaryName { $0.givenNames = newValue } }
    }

    public var patronymic: String? {
        get { primaryName?.patronymic }
        set { withPrimaryName { $0.patronymic = newValue } }
    }

    public var surname: String {
        get { primaryName?.surname ?? "" }
        set { withPrimaryName { $0.surname = newValue } }
    }

    public var maidenName: String? {
        get { primaryName?.maidenName }
        set { withPrimaryName { $0.maidenName = newValue } }
    }

    public var birthDate: String? {
        get { legacyDateString(.birth) }
        set { setLegacyDate(.birth, value: newValue) }
    }

    public var birthPlace: String? {
        get { event(ofKind: .birth)?.place?.displayName }
        set { setLegacyPlaceName(.birth, value: newValue) }
    }

    public var deathDate: String? {
        get { legacyDateString(.death) }
        set { setLegacyDate(.death, value: newValue) }
    }

    public var deathPlace: String? {
        get { event(ofKind: .death)?.place?.displayName }
        set { setLegacyPlaceName(.death, value: newValue) }
    }

    public var burialPlace: String? {
        get { event(ofKind: .burial)?.place?.displayName }
        set { setLegacyPlaceName(.burial, value: newValue) }
    }

    public var occupation: String? {
        get { event(ofKind: .occupation)?.value }
        set { setLegacyValue(.occupation, value: newValue) }
    }

    public var education: String? {
        get { event(ofKind: .education)?.value }
        set { setLegacyValue(.education, value: newValue) }
    }

    public var birthLat: Double? {
        get { event(ofKind: .birth)?.place?.latitude }
        set { setLegacyCoordinate(.birth, lat: newValue, lon: event(ofKind: .birth)?.place?.longitude) }
    }

    public var birthLon: Double? {
        get { event(ofKind: .birth)?.place?.longitude }
        set { setLegacyCoordinate(.birth, lat: event(ofKind: .birth)?.place?.latitude, lon: newValue) }
    }

    public var deathLat: Double? {
        get { event(ofKind: .death)?.place?.latitude }
        set { setLegacyCoordinate(.death, lat: newValue, lon: event(ofKind: .death)?.place?.longitude) }
    }

    public var deathLon: Double? {
        get { event(ofKind: .death)?.place?.longitude }
        set { setLegacyCoordinate(.death, lat: event(ofKind: .death)?.place?.latitude, lon: newValue) }
    }

    /// Precise grave/burial coordinates (entered manually, not geocoded).
    public var burialLat: Double? {
        get { event(ofKind: .burial)?.place?.latitude }
        set { setLegacyCoordinate(.burial, lat: newValue, lon: event(ofKind: .burial)?.place?.longitude) }
    }

    public var burialLon: Double? {
        get { event(ofKind: .burial)?.place?.longitude }
        set { setLegacyCoordinate(.burial, lat: event(ofKind: .burial)?.place?.latitude, lon: newValue) }
    }

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

    public enum Sex: String, Codable, CaseIterable, Sendable {
        case male = "M"
        case female = "F"
        case unknown = "U"

        public var displayName: String {
            displayName(language: .current)
        }

        public func displayName(language: AppLanguage) -> String {
            switch self {
            case .male: L10n.tr("Мужской", language: language)
            case .female: L10n.tr("Женский", language: language)
            case .unknown: L10n.tr("Не указан", language: language)
            }
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
        self.sex = sex
        self.isLiving = isLiving
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
        // Only touch photo state when bytes are supplied, so a plain new
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

    /// Locale-appropriate presentation name. The stored name parts remain unchanged;
    /// only their display order changes.
    public func displayName(language: AppLanguage = .current) -> String {
        switch language {
        case .russian:
            listName
        case .english:
            fullName
        }
    }

    /// Stable, locale-aware sort key. English still sorts genealogical lists by
    /// surname, while showing the natural given-name-first form.
    public func sortName(language: AppLanguage = .current) -> String {
        let components = switch language {
        case .russian:
            [surname, givenNames, patronymic ?? ""]
        case .english:
            [surname, givenNames, patronymic ?? ""]
        }
        return components
            .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: language.locale) }
            .joined(separator: "\u{001F}")
    }

    public var displaySurname: String {
        surname.isEmpty ? (maidenName ?? "") : surname
    }

    // MARK: - Structured compatibility

    public func event(ofKind kind: GenealogyEvent.Kind) -> GenealogyEvent? {
        events.first(where: { $0.kind == kind })
    }

    public func replaceEvent(_ event: GenealogyEvent) {
        if let index = events.firstIndex(where: { $0.id == event.id || $0.kind == event.kind }) {
            events[index] = event
        } else {
            events.append(event)
        }
    }

    /// Copy every content field of `source` onto this live instance, keeping identity
    /// (`id`, `createdAt`). The canonical rollback path for editors that must preserve
    /// the shared `Person` reference other views hold — hand-copied field lists drift
    /// and silently drop new fields (see the applyContent completeness test).
    public func applyContent(of source: Person) {
        sex = source.sex
        isLiving = source.isLiving
        notes = source.notes
        sources = source.sources
        // Names, dates, places, coordinates, occupation and education all live in
        // the structured arrays; the legacy accessors are computed views over them.
        names = source.names
        events = source.events
        citations = source.citations
        attachments = source.attachments
        links = source.links
        photoFilename = source.photoFilename
        // Snapshots carry only the portrait filename. Drop any dirty in-memory bytes
        // so the portrait lazily re-reads from disk, which still holds the state the
        // snapshot was taken from — unless the snapshot itself carries legacy inline
        // bytes (old JSON), which stay dirty so the next save writes them out.
        if case .some(let bytes) = source.loadedPhoto, source.photoIsDirty {
            loadedPhoto = .some(bytes)
            photoIsDirty = true
        } else {
            loadedPhoto = nil
            photoIsDirty = false
        }
        gedcomXref = source.gedcomXref
        unknownBranches = source.unknownBranches
        eventExtras = source.eventExtras
        updatedAt = source.updatedAt
    }

    /// Called by the GEDCOM parser so qualifiers/ranges remain canonical.
    public func setStructuredDate(_ date: GenealogyDate?, for kind: GenealogyEvent.Kind) {
        updateEvent(kind: kind) { $0.date = date }
    }

    public func setStructuredPlace(_ place: PlaceReference?, for kind: GenealogyEvent.Kind) {
        updateEvent(kind: kind) { $0.place = place }
    }

    private var primaryName: PersonName? {
        guard !names.isEmpty else { return nil }
        return names[names.firstIndex(where: \.isPrimary) ?? 0]
    }

    private func withPrimaryName(_ mutate: (inout PersonName) -> Void) {
        if names.isEmpty { names = [PersonName()] }
        let index = names.firstIndex(where: \.isPrimary) ?? 0
        names[index].isPrimary = true
        mutate(&names[index])
    }

    /// The string the old stored date fields held in steady state: DD.MM.YYYY for a
    /// plain exact date, canonical GEDCOM for qualified/ranged dates, the imported
    /// raw text when nothing parsed.
    private func legacyDateString(_ kind: GenealogyEvent.Kind) -> String? {
        guard let date = event(ofKind: kind)?.date else { return nil }
        if date.qualifier == .exact, date.end == nil, let start = date.start {
            return FamilyDate.Components(day: start.day, month: start.month, year: start.year).formatted
        }
        if date.start != nil { return date.canonicalGEDCOMValue }
        return date.rawValue.isEmpty ? nil : date.rawValue
    }

    private func setLegacyDate(_ kind: GenealogyEvent.Kind, value: String?) {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        updateEvent(kind: kind) { event in
            event.date = (trimmed?.isEmpty == false) ? GenealogyDate(userInput: trimmed!) : nil
        }
        removeEventIfEmpty(kind)
    }

    private func setLegacyPlaceName(_ kind: GenealogyEvent.Kind, value: String?) {
        let existing = event(ofKind: kind)?.place
        setLegacyPlace(kind, name: value, lat: existing?.latitude, lon: existing?.longitude)
    }

    private func setLegacyCoordinate(_ kind: GenealogyEvent.Kind, lat: Double?, lon: Double?) {
        setLegacyPlace(kind, name: event(ofKind: kind)?.place?.displayName, lat: lat, lon: lon)
    }

    private func setLegacyPlace(_ kind: GenealogyEvent.Kind, name: String?, lat: Double?, lon: Double?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

    private func setLegacyValue(_ kind: GenealogyEvent.Kind, value: String?) {
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

        if !isLiving {
            let base = "\(birthStr.isEmpty ? "?" : birthStr)–\(deathStr.isEmpty ? "?" : deathStr)"
            // Age only when a death date exists; otherwise it would count up to today.
            if deathDate != nil, let result = FamilyDate.calculateAge(birth: birthDate, death: deathDate) {
                let approx = result.approximate ? "~" : ""
                return "\(base) (\(approx)\(result.years))"
            }
            return base
        }
        if !birthStr.isEmpty {
            if let result = FamilyDate.calculateAge(birth: birthDate, death: nil) {
                let approx = result.approximate ? "~" : ""
                return L10n.tr("р. \(birthStr) (\(approx)\(result.years))")
            }
            return L10n.tr("р. \(birthStr)")
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
        case burialPlace, occupation, education, notes, sources, photoData, photoFilename, attachments, links
        case names, events, citations
        case birthLat, birthLon, deathLat, deathLon, burialLat, burialLon
        case gedcomXref, unknownBranches, eventExtras
        case createdAt, updatedAt
    }

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sex = try c.decode(Sex.self, forKey: .sex)
        isLiving = try c.decode(Bool.self, forKey: .isLiving)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        sources = try c.decode([String].self, forKey: .sources)
        // Legacy JSON predates the structured arrays; rebuild them from its flat keys.
        names = try c.decodeIfPresent([PersonName].self, forKey: .names) ?? [PersonName(
            givenNames: c.decodeIfPresent(String.self, forKey: .givenNames) ?? "",
            patronymic: c.decodeIfPresent(String.self, forKey: .patronymic),
            surname: c.decodeIfPresent(String.self, forKey: .surname) ?? "",
            maidenName: c.decodeIfPresent(String.self, forKey: .maidenName)
        )]
        if let decoded = try c.decodeIfPresent([GenealogyEvent].self, forKey: .events) {
            events = decoded
        } else {
            events = try Self.initialEvents(
                birthDate: c.decodeIfPresent(String.self, forKey: .birthDate),
                birthPlace: c.decodeIfPresent(String.self, forKey: .birthPlace),
                deathDate: c.decodeIfPresent(String.self, forKey: .deathDate),
                deathPlace: c.decodeIfPresent(String.self, forKey: .deathPlace),
                burialPlace: c.decodeIfPresent(String.self, forKey: .burialPlace),
                occupation: c.decodeIfPresent(String.self, forKey: .occupation),
                education: c.decodeIfPresent(String.self, forKey: .education)
            )
        }
        citations = try c.decodeIfPresent([Citation].self, forKey: .citations) ?? []
        photoFilename = try c.decodeIfPresent(String.self, forKey: .photoFilename)
        // Legacy JSON stored the bytes inline; if present, take them (marked dirty so
        // the next save writes them into Media/ and the GEDCOM). New snapshots carry
        // only the filename, keeping undo/snapshots free of megabytes of photo data.
        if let legacy = try c.decodeIfPresent(Data.self, forKey: .photoData) {
            loadedPhoto = .some(legacy); photoIsDirty = true
        }
        attachments = try c.decodeIfPresent([Attachment].self, forKey: .attachments) ?? []
        links = try c.decodeIfPresent([WebLink].self, forKey: .links) ?? []
        gedcomXref = try c.decodeIfPresent(String.self, forKey: .gedcomXref)
        unknownBranches = try c.decodeIfPresent([[String]].self, forKey: .unknownBranches) ?? []
        eventExtras = try c.decodeIfPresent([String: [String]].self, forKey: .eventExtras) ?? [:]
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        // Legacy JSON kept map coordinates outside the events; fold them in.
        if try c.decodeIfPresent([GenealogyEvent].self, forKey: .events) == nil {
            let coords: [(GenealogyEvent.Kind, CodingKeys, CodingKeys)] = [
                (.birth, .birthLat, .birthLon), (.death, .deathLat, .deathLon), (.burial, .burialLat, .burialLon),
            ]
            for (kind, latKey, lonKey) in coords {
                let lat = try c.decodeIfPresent(Double.self, forKey: latKey)
                let lon = try c.decodeIfPresent(Double.self, forKey: lonKey)
                if lat != nil || lon != nil { setLegacyCoordinate(kind, lat: lat, lon: lon) }
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        // The legacy flat keys are decode-only compatibility for old snapshots;
        // everything they carried lives in `names`/`events` now.
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(sex, forKey: .sex)
        try c.encode(isLiving, forKey: .isLiving)
        try c.encodeIfPresent(notes, forKey: .notes)
        try c.encode(sources, forKey: .sources)
        try c.encode(names, forKey: .names)
        if !events.isEmpty { try c.encode(events, forKey: .events) }
        if !citations.isEmpty { try c.encode(citations, forKey: .citations) }
        // Persist only the portrait's filename, never the bytes — this keeps undo
        // snapshots (which use Codable) free of megabytes of image data.
        try c.encodeIfPresent(photoFilename, forKey: .photoFilename)
        if !attachments.isEmpty { try c.encode(attachments, forKey: .attachments) }
        if !links.isEmpty { try c.encode(links, forKey: .links) }
        try c.encodeIfPresent(gedcomXref, forKey: .gedcomXref)
        if !unknownBranches.isEmpty { try c.encode(unknownBranches, forKey: .unknownBranches) }
        if !eventExtras.isEmpty { try c.encode(eventExtras, forKey: .eventExtras) }
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
