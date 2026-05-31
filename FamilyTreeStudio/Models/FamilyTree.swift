import Foundation
import Observation

@Observable
final class FamilyTree: Identifiable, Codable {
    var id: UUID
    var name: String
    var subtitle: String?
    var homePersonId: UUID?
    var rootUnionId: UUID?
    var people: [Person]
    var unions: [Union]
    var createdAt: Date
    var updatedAt: Date
    
    init(name: String, subtitle: String? = nil) {
        self.id = UUID()
        self.name = name
        self.subtitle = subtitle
        self.people = []
        self.unions = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    var homePerson: Person? {
        guard let hid = homePersonId else { return nil }
        return people.first(where: { $0.id == hid })
    }
    
    var rootUnion: Union? {
        guard let rid = rootUnionId else { return nil }
        return unions.first(where: { $0.id == rid })
    }
    
    func person(byId pid: UUID) -> Person? {
        people.first(where: { $0.id == pid })
    }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id, name, subtitle, homePersonId, rootUnionId, people, unions, createdAt, updatedAt
    }
    
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        subtitle = try c.decodeIfPresent(String.self, forKey: .subtitle)
        homePersonId = try c.decodeIfPresent(UUID.self, forKey: .homePersonId)
        rootUnionId = try c.decodeIfPresent(UUID.self, forKey: .rootUnionId)
        people = try c.decode([Person].self, forKey: .people)
        unions = try c.decode([Union].self, forKey: .unions)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
    
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encodeIfPresent(homePersonId, forKey: .homePersonId)
        try c.encodeIfPresent(rootUnionId, forKey: .rootUnionId)
        try c.encode(people, forKey: .people)
        try c.encode(unions, forKey: .unions)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
