import Foundation
import Observation

@Observable
final class Person: Identifiable, Codable, Hashable {
    var id: UUID
    var givenNames: String
    var patronymic: String?
    var surname: String
    var maidenName: String?
    var sex: Sex
    
    var birthDate: String?
    var birthPlace: String?
    
    var deathDate: String?
    var deathPlace: String?
    var isLiving: Bool
    
    var burialPlace: String?
    
    var occupation: String?
    var education: String?
    var notes: String?
    var sources: [String]
    
    var photoData: Data?
    
    var createdAt: Date
    var updatedAt: Date
    
    enum Sex: String, Codable, CaseIterable {
        case male = "M"
        case female = "F"
        case unknown = "U"
        
        var displayName: String {
            switch self {
            case .male: return "Муж"
            case .female: return "Жен"
            case .unknown: return "Не указан"
            }
        }
        
        var russianName: String { displayName }
    }
    
    init(
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
        self.photoData = photoData
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    var fullName: String {
        [givenNames.isEmpty ? nil : givenNames, patronymic, surname.isEmpty ? nil : surname]
            .compactMap { $0 }
            .joined(separator: " ")
    }
    
    var displaySurname: String {
        surname.isEmpty ? (maidenName ?? "") : surname
    }
    
    var lifespan: String {
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
    static func == (lhs: Person, rhs: Person) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    
    // MARK: - Codable
    enum CodingKeys: String, CodingKey {
        case id, givenNames, patronymic, surname, maidenName, sex
        case birthDate, birthPlace, deathDate, deathPlace, isLiving
        case burialPlace, occupation, education, notes, sources, photoData
        case createdAt, updatedAt
    }
    
    required init(from decoder: Decoder) throws {
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
        photoData = try c.decodeIfPresent(Data.self, forKey: .photoData)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
    }
    
    func encode(to encoder: Encoder) throws {
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
        try c.encodeIfPresent(photoData, forKey: .photoData)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
    }
}
