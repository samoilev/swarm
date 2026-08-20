import Foundation

/// A web link attached to a person — an archive record, memorial page or article.
/// Unlike `Attachment` nothing is stored on disk; the model holds the address itself.
public struct WebLink: Identifiable, Codable, Hashable {
    public var id: UUID
    /// The address as typed. `normalized` adds a scheme when the user omitted one.
    public var url: String
    /// Optional label. The address is shown when empty.
    public var title: String

    public init(id: UUID = UUID(), url: String = "", title: String = "") {
        self.id = id
        self.url = url
        self.title = title
    }

    public var displayTitle: String {
        title.trimmingCharacters(in: .whitespaces).isEmpty ? url : title
    }

    /// The host shown under the title, e.g. "www.familysearch.org" → "familysearch.org".
    public var displayHost: String {
        guard let host = URL(string: Self.normalize(url))?.host else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Only http(s) and mailto are handed to the system. An imported GEDCOM is untrusted
    /// input, and `file://` or a custom scheme would let it launch something local.
    public var openableURL: URL? {
        guard let candidate = URL(string: Self.normalize(url)),
              let scheme = candidate.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return nil }
        return candidate
    }

    /// Trims and prefixes a bare "example.com/x" with https so it opens as typed.
    public static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://"), !trimmed.lowercased().hasPrefix("mailto:") else {
            return trimmed
        }
        return "https://" + trimmed
    }

    private enum CodingKeys: String, CodingKey { case id, url, title }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(url, forKey: .url)
        if !title.isEmpty { try container.encode(title, forKey: .title) }
    }
}
