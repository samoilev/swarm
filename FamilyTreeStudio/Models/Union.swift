import Foundation
import Observation

@Observable
final class Union: Identifiable, Codable, Hashable {
    var id: UUID
    var partner1Id: UUID?
    var partner2Id: UUID?
    var marriageDate: String?
    var marriagePlace: String?
    var status: String?
    var childrenIds: [UUID]
    var createdAt: Date
    
    init(
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
    
    var partnerIds: [UUID] {
        [partner1Id, partner2Id].compactMap { $0 }
    }
    
    // MARK: - Hashable
    static func == (lhs: Union, rhs: Union) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id, partner1Id, partner2Id, marriageDate, marriagePlace, status, childrenIds, createdAt
    }
    
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        partner1Id = try c.decodeIfPresent(UUID.self, forKey: .partner1Id)
        partner2Id = try c.decodeIfPresent(UUID.self, forKey: .partner2Id)
        marriageDate = try c.decodeIfPresent(String.self, forKey: .marriageDate)
        marriagePlace = try c.decodeIfPresent(String.self, forKey: .marriagePlace)
        status = try c.decodeIfPresent(String.self, forKey: .status)
        childrenIds = try c.decode([UUID].self, forKey: .childrenIds)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(partner1Id, forKey: .partner1Id)
        try c.encodeIfPresent(partner2Id, forKey: .partner2Id)
        try c.encodeIfPresent(marriageDate, forKey: .marriageDate)
        try c.encodeIfPresent(marriagePlace, forKey: .marriagePlace)
        try c.encodeIfPresent(status, forKey: .status)
        try c.encode(childrenIds, forKey: .childrenIds)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
