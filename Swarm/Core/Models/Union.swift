import Foundation
import Observation

@Observable
public final class Union: Identifiable, Codable, Hashable {
    public var id: UUID
    public var partner1Id: UUID?
    public var partner2Id: UUID?
    public var childrenIds: [UUID]
    /// Canonical structured records — the single source of truth. `marriageDate`,
    /// `marriagePlace` and `status` below are computed views over this array.
    public var events: [GenealogyEvent]
    public var citations: [Citation]

    public var marriageDate: String? {
        get {
            guard let date = event(ofKind: .marriage)?.date else { return nil }
            if date.qualifier == .exact, date.end == nil, let start = date.start {
                return FamilyDate.Components(day: start.day, month: start.month, year: start.year).formatted
            }
            if date.start != nil { return date.canonicalGEDCOMValue }
            return date.rawValue.isEmpty ? nil : date.rawValue
        }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            updateEvent(kind: .marriage) { event in
                event.date = (trimmed?.isEmpty == false) ? GenealogyDate(userInput: trimmed!) : nil
            }
            removeEventIfEmpty(.marriage)
        }
    }

    public var marriagePlace: String? {
        get { event(ofKind: .marriage)?.place?.displayName }
        set {
            let trimmed = newValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            updateEvent(kind: .marriage) { event in
                if trimmed.isEmpty {
                    event.place = nil
                } else {
                    var place = event.place ?? PlaceReference(displayName: trimmed, isCustom: true)
                    place.displayName = trimmed
                    if place.datasetID == nil { place.isCustom = true }
                    event.place = place
                }
            }
            removeEventIfEmpty(.marriage)
        }
    }

    public var status: String? {
        get {
            if event(ofKind: .divorce) != nil { return "divorced" }
            if event(ofKind: .separation) != nil { return "separated" }
            return event(ofKind: .partnership)?.value
        }
        set {
            events.removeAll { [.divorce, .separation, .partnership].contains($0.kind) }
            switch newValue {
            case "divorced": events.append(GenealogyEvent(kind: .divorce))
            case "separated": events.append(GenealogyEvent(kind: .separation))
            case let value?:
                if !value.isEmpty { events.append(GenealogyEvent(kind: .partnership, value: value)) }
            case nil: break
            }
        }
    }

    // MARK: - GEDCOM interop preservation (see Person for the rationale)

    /// Original `@F..@` xref from an imported file, reused on export.
    public var gedcomXref: String?
    /// Whole unmodeled level-1 branches, re-emitted verbatim at the end of the FAM record.
    public var unknownBranches: [[String]] = []
    /// Unmodeled sub-lines of the MARR event, re-emitted inside it.
    public var marriageExtras: [String] = []

    public var createdAt: Date

    public init(
        partner1Id: UUID? = nil,
        partner2Id: UUID? = nil,
        marriageDate: String? = nil,
        marriagePlace: String? = nil,
        status: String? = nil,
        childrenIds: [UUID] = []
    ) {
        self.id = UUID()
        self.partner1Id = partner1Id
        self.partner2Id = partner2Id
        self.childrenIds = childrenIds
        var initialEvents: [GenealogyEvent] = []
        if marriageDate?.isEmpty == false || marriagePlace?.isEmpty == false {
            initialEvents.append(GenealogyEvent(
                kind: .marriage,
                date: marriageDate.map { GenealogyDate(userInput: $0) },
                place: marriagePlace.map { PlaceReference(displayName: $0, isCustom: true) }
            ))
        }
        if status == "divorced" { initialEvents.append(GenealogyEvent(kind: .divorce)) }
        else if status == "separated" { initialEvents.append(GenealogyEvent(kind: .separation)) }
        else if let status, !status.isEmpty { initialEvents.append(GenealogyEvent(kind: .partnership, value: status)) }
        self.events = initialEvents
        self.citations = []
        self.createdAt = Date()
    }

    public var partnerIds: [UUID] {
        var seen = Set<UUID>()
        return [partner1Id, partner2Id].compactMap { $0 }.filter { seen.insert($0).inserted }
    }

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

    public func setStructuredEvent(_ event: GenealogyEvent) {
        if let index = events.firstIndex(where: { $0.kind == event.kind }) { events[index] = event }
        else { events.append(event) }
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

    // MARK: - Hashable

    public static func == (lhs: Union, rhs: Union) -> Bool {
        lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, partner1Id, partner2Id, marriageDate, marriagePlace, status, childrenIds, events, citations, createdAt
        case gedcomXref, unknownBranches, marriageExtras
    }

    public required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        partner1Id = try c.decodeIfPresent(UUID.self, forKey: .partner1Id)
        partner2Id = try c.decodeIfPresent(UUID.self, forKey: .partner2Id)
        childrenIds = try c.decode([UUID].self, forKey: .childrenIds)
        events = try c.decodeIfPresent([GenealogyEvent].self, forKey: .events) ?? []
        citations = try c.decodeIfPresent([Citation].self, forKey: .citations) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        // Legacy JSON predates the structured events; rebuild them from its flat keys.
        if events.isEmpty {
            let legacyDate = try c.decodeIfPresent(String.self, forKey: .marriageDate)
            let legacyPlace = try c.decodeIfPresent(String.self, forKey: .marriagePlace)
            if legacyDate?.isEmpty == false || legacyPlace?.isEmpty == false {
                events.append(GenealogyEvent(
                    kind: .marriage,
                    date: legacyDate.map { GenealogyDate(userInput: $0) },
                    place: legacyPlace.map { PlaceReference(displayName: $0, isCustom: true) }
                ))
            }
            if try c.decodeIfPresent(String.self, forKey: .status) == "divorced" {
                events.append(GenealogyEvent(kind: .divorce))
            }
        }
        gedcomXref = try c.decodeIfPresent(String.self, forKey: .gedcomXref)
        unknownBranches = try c.decodeIfPresent([[String]].self, forKey: .unknownBranches) ?? []
        marriageExtras = try c.decodeIfPresent([String].self, forKey: .marriageExtras) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        // marriageDate/marriagePlace/status are decode-only compatibility for old
        // snapshots; everything they carried lives in `events` now.
        try c.encodeIfPresent(partner1Id, forKey: .partner1Id)
        try c.encodeIfPresent(partner2Id, forKey: .partner2Id)
        try c.encode(childrenIds, forKey: .childrenIds)
        if !events.isEmpty { try c.encode(events, forKey: .events) }
        if !citations.isEmpty { try c.encode(citations, forKey: .citations) }
        try c.encodeIfPresent(gedcomXref, forKey: .gedcomXref)
        if !unknownBranches.isEmpty { try c.encode(unknownBranches, forKey: .unknownBranches) }
        if !marriageExtras.isEmpty { try c.encode(marriageExtras, forKey: .marriageExtras) }
        try c.encode(createdAt, forKey: .createdAt)
    }
}
