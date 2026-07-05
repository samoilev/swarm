import Foundation
import Observation

@Observable
public final class Union: Identifiable, Codable, Hashable {
    public var id: UUID
    public var partner1Id: UUID?
    public var partner2Id: UUID?
    public var marriageDate: String?
    public var marriagePlace: String?
    public var status: String?
    public var childrenIds: [UUID]

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
        self.createdAt = Date()
    }

    public var partnerIds: [UUID] {
        [partner1Id, partner2Id].compactMap { $0 }
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
        case id, partner1Id, partner2Id, marriageDate, marriagePlace, status, childrenIds, createdAt
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
        gedcomXref = try c.decodeIfPresent(String.self, forKey: .gedcomXref)
        unknownBranches = try c.decodeIfPresent([[String]].self, forKey: .unknownBranches) ?? []
        marriageExtras = try c.decodeIfPresent([String].self, forKey: .marriageExtras) ?? []
        createdAt = try c.decode(Date.self, forKey: .createdAt)
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
        try c.encodeIfPresent(gedcomXref, forKey: .gedcomXref)
        if !unknownBranches.isEmpty { try c.encode(unknownBranches, forKey: .unknownBranches) }
        if !marriageExtras.isEmpty { try c.encode(marriageExtras, forKey: .marriageExtras) }
        try c.encode(createdAt, forKey: .createdAt)
    }
}
