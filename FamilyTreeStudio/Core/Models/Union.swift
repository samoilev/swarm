import Foundation
import Observation

@Observable
public final class Union: Identifiable, Codable, Hashable {
    public var id: UUID
    public var partner1Id: UUID?
    public var partner2Id: UUID?
    public var marriageDate: String? { didSet { synchronizeMarriageFromLegacy() } }
    public var marriagePlace: String? { didSet { synchronizeMarriageFromLegacy() } }
    public var status: String? { didSet { synchronizeStatusFromLegacy() } }
    public var childrenIds: [UUID]
    public var events: [GenealogyEvent]
    public var citations: [Citation]
    @ObservationIgnored private var isSynchronizingStructured = false

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
        self.marriageDate = marriageDate
        self.marriagePlace = marriagePlace
        self.status = status
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
        [partner1Id, partner2Id].compactMap { $0 }
    }

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
        if event.kind == .marriage {
            marriageDate = event.date?.displayValue
            marriagePlace = event.place?.displayName
        } else if event.kind == .divorce {
            status = "divorced"
        } else if event.kind == .separation {
            status = "separated"
        }
    }

    public func setStructuredEvent(_ event: GenealogyEvent) {
        isSynchronizingStructured = true
        defer { isSynchronizingStructured = false }
        if let index = events.firstIndex(where: { $0.kind == event.kind }) { events[index] = event }
        else { events.append(event) }
    }

    private func synchronizeMarriageFromLegacy() {
        guard !isSynchronizingStructured else { return }
        let hasValue = marriageDate?.isEmpty == false || marriagePlace?.isEmpty == false
        if let index = events.firstIndex(where: { $0.kind == .marriage }) {
            if hasValue {
                events[index].date = marriageDate.map { GenealogyDate(userInput: $0) }
                events[index].place = marriagePlace.map { PlaceReference(displayName: $0, isCustom: true) }
            } else {
                events.remove(at: index)
            }
        } else if hasValue {
            events.append(GenealogyEvent(
                kind: .marriage,
                date: marriageDate.map { GenealogyDate(userInput: $0) },
                place: marriagePlace.map { PlaceReference(displayName: $0, isCustom: true) }
            ))
        }
    }

    private func synchronizeStatusFromLegacy() {
        guard !isSynchronizingStructured else { return }
        events.removeAll { [.divorce, .separation, .partnership].contains($0.kind) }
        switch status {
        case "divorced": events.append(GenealogyEvent(kind: .divorce))
        case "separated": events.append(GenealogyEvent(kind: .separation))
        case let value?:
            if !value.isEmpty { events.append(GenealogyEvent(kind: .partnership, value: value)) }
        case nil: break
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
        marriageDate = try c.decodeIfPresent(String.self, forKey: .marriageDate)
        marriagePlace = try c.decodeIfPresent(String.self, forKey: .marriagePlace)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        childrenIds = try c.decode([UUID].self, forKey: .childrenIds)
        events = try c.decodeIfPresent([GenealogyEvent].self, forKey: .events) ?? []
        citations = try c.decodeIfPresent([Citation].self, forKey: .citations) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        if events.isEmpty {
            if marriageDate?.isEmpty == false || marriagePlace?.isEmpty == false {
                events.append(GenealogyEvent(
                    kind: .marriage,
                    date: marriageDate.map { GenealogyDate(userInput: $0) },
                    place: marriagePlace.map { PlaceReference(displayName: $0, isCustom: true) }
                ))
            }
            if status == "divorced" { events.append(GenealogyEvent(kind: .divorce)) }
        }
        gedcomXref = try c.decodeIfPresent(String.self, forKey: .gedcomXref)
        unknownBranches = try c.decodeIfPresent([[String]].self, forKey: .unknownBranches) ?? []
        marriageExtras = try c.decodeIfPresent([String].self, forKey: .marriageExtras) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(partner1Id, forKey: .partner1Id)
        try c.encodeIfPresent(partner2Id, forKey: .partner2Id)
        try c.encodeIfPresent(marriageDate, forKey: .marriageDate)
        try c.encodeIfPresent(marriagePlace, forKey: .marriagePlace)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encode(childrenIds, forKey: .childrenIds)
        if !events.isEmpty { try c.encode(events, forKey: .events) }
        if !citations.isEmpty { try c.encode(citations, forKey: .citations) }
        try c.encodeIfPresent(gedcomXref, forKey: .gedcomXref)
        if !unknownBranches.isEmpty { try c.encode(unknownBranches, forKey: .unknownBranches) }
        if !marriageExtras.isEmpty { try c.encode(marriageExtras, forKey: .marriageExtras) }
        try c.encode(createdAt, forKey: .createdAt)
    }
}
