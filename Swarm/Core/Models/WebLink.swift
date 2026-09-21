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

    /// The genealogy site this address belongs to, when it is one Swarm recognizes.
    public var site: GenealogySite? { GenealogySite.match(url: Self.normalize(url)) }

    /// The person identifier inside the address, e.g. FamilySearch's `LZDP-6M9`.
    public var externalID: String? { site?.extractID(from: Self.normalize(url)) }

    /// The line under the title: "FamilySearch · LZDP-6M9" where the address is a
    /// recognized person page, the bare host otherwise.
    public var displaySubtitle: String {
        guard let site else { return displayHost }
        guard let externalID else { return site.name }
        return "\(site.name) · \(externalID)"
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
    ///
    /// A bare person identifier pasted on its own — a FamilySearch `LZDP-6M9` — expands
    /// to that site's person page instead; without this it became `https://LZDP-6M9`,
    /// which opens nothing. Idempotent either way: what comes back holds a scheme, so a
    /// second pass returns it unchanged.
    public static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("://"), !trimmed.lowercased().hasPrefix("mailto:") else {
            return trimmed
        }
        if let match = GenealogySite.matchingBareID(trimmed) { return match.site.url(for: match.id) }
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
