import Foundation

/// A file attached to a person. Only metadata lives in the model — the bytes are
/// stored strictly locally on disk inside the tree's `Attachments/` folder.
public struct Attachment: Identifiable, Codable, Hashable {
    public var id: UUID
    /// Filename on disk inside `<tree>/Attachments/`, e.g. "<uuid>.pdf".
    /// A UUID-based name avoids collisions between files sharing an original name.
    public var storedName: String
    /// Original name as chosen by the user, used for display, e.g. "Свидетельство.pdf".
    public var originalName: String
    public var notes: String?
    public var citations: [Citation]

    public init(
        id: UUID = UUID(),
        storedName: String,
        originalName: String,
        notes: String? = nil,
        citations: [Citation] = []
    ) {
        self.id = id
        self.storedName = storedName
        self.originalName = originalName
        self.notes = notes
        self.citations = citations
    }

    /// Uppercased file extension for display, e.g. "PDF". Empty if the name has none.
    public var format: String {
        (originalName as NSString).pathExtension.uppercased()
    }

    /// Whether this attachment is an image and should be shown as a thumbnail.
    public var isImage: Bool {
        let ext = (originalName as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "heic", "heif", "tiff", "tif", "bmp", "webp"].contains(ext)
    }

    private enum CodingKeys: String, CodingKey { case id, storedName, originalName, notes, citations }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        storedName = try container.decode(String.self, forKey: .storedName)
        originalName = try container.decode(String.self, forKey: .originalName)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        citations = try container.decodeIfPresent([Citation].self, forKey: .citations) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(storedName, forKey: .storedName)
        try container.encode(originalName, forKey: .originalName)
        try container.encodeIfPresent(notes, forKey: .notes)
        if !citations.isEmpty { try container.encode(citations, forKey: .citations) }
    }
}
