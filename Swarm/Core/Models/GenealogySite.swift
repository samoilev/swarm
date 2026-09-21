import Foundation

/// A genealogy site whose person pages carry a stable identifier.
///
/// Nothing here is stored — a `WebLink` keeps only its address, and the site and the
/// identifier are recovered from that address on demand. That is deliberate: recognition
/// can gain or lose a site without touching the model, the GEDCOM codec or a migration.
public struct GenealogySite: Sendable, Hashable {
    /// Where the identifier sits in a person-page URL.
    public enum IDInPath: Sendable, Hashable {
        /// The component right after a fixed one, e.g. `/memorial/12345/john-doe`.
        case following(String)
        /// The last component, e.g. Geni's `/people/John-Doe/6000000012345678901`.
        case last
        /// The component carrying a fixed prefix, e.g. MyHeritage's `person-1_2_3`.
        case prefixed(String)
        /// The site is recognized by host alone and has no single identifier.
        case none
    }

    /// The shape of a bare identifier a user may paste instead of a whole URL. Only
    /// sites with a distinctive shape take part — see `matchingBareID(_:)`.
    public enum BareID: Sendable, Hashable {
        case none
        /// FamilySearch PID: four characters, a dash, three more — `LZDP-6M9`.
        case familySearchPID
        /// WikiTree ID: a surname, a dash, a number — `Doe-123`.
        case wikiTreeID
    }

    public let id: String
    /// Shown in the interface as-is. A proper noun, so it is never localized.
    public let name: String
    /// Matched against the URL's host after a leading `www.` is dropped. A host also
    /// matches its subdomains, so `gw.geneanet.org` matches `geneanet.org`.
    public let hosts: [String]
    /// Builds a person-page URL from a bare identifier. `%@` is the identifier.
    public let urlTemplate: String
    public let idInPath: IDInPath
    public let bareID: BareID

    public static let all: [GenealogySite] = [
        GenealogySite(
            id: "familysearch", name: "FamilySearch", hosts: ["familysearch.org"],
            urlTemplate: "https://www.familysearch.org/tree/person/details/%@",
            idInPath: .following("details"), bareID: .familySearchPID
        ),
        GenealogySite(
            id: "wikitree", name: "WikiTree", hosts: ["wikitree.com"],
            urlTemplate: "https://www.wikitree.com/wiki/%@",
            idInPath: .following("wiki"), bareID: .wikiTreeID
        ),
        GenealogySite(
            id: "findagrave", name: "Find a Grave", hosts: ["findagrave.com"],
            urlTemplate: "https://www.findagrave.com/memorial/%@",
            // A bare memorial number is just digits — too ordinary to claim as an id.
            idInPath: .following("memorial"), bareID: .none
        ),
        GenealogySite(
            id: "geni", name: "Geni", hosts: ["geni.com"],
            urlTemplate: "https://www.geni.com/people/x/%@",
            idInPath: .last, bareID: .none
        ),
        GenealogySite(
            id: "myheritage", name: "MyHeritage", hosts: ["myheritage.com"],
            urlTemplate: "https://www.myheritage.com/person-%@",
            idInPath: .prefixed("person-"), bareID: .none
        ),
        GenealogySite(
            // Geneanet addresses a person with `?p=jean&n=dupont`, not one identifier,
            // so the host is all that is recognized.
            id: "geneanet", name: "Geneanet", hosts: ["geneanet.org"],
            urlTemplate: "https://gw.geneanet.org/%@",
            idInPath: .none, bareID: .none
        ),
    ]

    /// The site owning this address, or nil when it belongs to none of them.
    public static func match(url: String) -> GenealogySite? {
        guard let host = URL(string: url)?.host?.lowercased() else { return nil }
        return all.first { site in
            site.hosts.contains { host == $0 || host.hasSuffix("." + $0) }
        }
    }

    /// The identifier inside one of this site's person-page URLs.
    public func extractID(from url: String) -> String? {
        guard let components = URL(string: url)?.pathComponents else { return nil }
        // pathComponents leads with "/" and can hold empty strings for doubled slashes.
        let parts = components.filter { $0 != "/" && !$0.isEmpty }
        let found: String? = switch idInPath {
        case let .following(marker):
            parts.firstIndex(of: marker).flatMap { idx in
                parts.indices.contains(idx + 1) ? parts[idx + 1] : nil
            }
        case .last:
            parts.last
        case let .prefixed(prefix):
            parts.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
        case .none:
            nil
        }
        guard let found, !found.isEmpty else { return nil }
        return found.removingPercentEncoding ?? found
    }

    /// A person-page URL for a bare identifier.
    public func url(for identifier: String) -> String {
        urlTemplate.replacingOccurrences(of: "%@", with: identifier)
    }

    /// The one site whose bare-identifier shape this text fits.
    ///
    /// Nil when nothing matches *and* when more than one site does: silently filing a
    /// reference under the wrong archive is worse than leaving the text as the user
    /// typed it. `WXYZ-123` reads as both a FamilySearch PID and a WikiTree ID, so it
    /// stays untouched and the user pastes the full address instead.
    public static func matchingBareID(_ text: String) -> (site: GenealogySite, id: String)? {
        let candidate = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = all.filter { $0.accepts(bareID: candidate) }
        guard matches.count == 1, let site = matches.first else { return nil }
        return (site, candidate)
    }

    func accepts(bareID candidate: String) -> Bool {
        let parts = candidate.split(separator: "-", omittingEmptySubsequences: false)
        switch bareID {
        case .none:
            return false
        case .familySearchPID:
            guard parts.count == 2, parts[0].count == 4, parts[1].count == 3 else { return false }
            return parts.allSatisfy { part in
                part.allSatisfy { ($0.isLetter && $0.isUppercase) || $0.isNumber }
            }
        case .wikiTreeID:
            // The number is the last dash-separated part; a surname may itself be
            // hyphenated ("Saint-Exupery-12").
            guard parts.count >= 2, let number = parts.last, !number.isEmpty,
                  number.allSatisfy(\.isNumber) else { return false }
            let surname = parts.dropLast()
            guard surname.allSatisfy({ !$0.isEmpty }) else { return false }
            return surname.allSatisfy { part in
                part.allSatisfy { $0.isLetter || $0 == "'" || $0 == "." }
            }
        }
    }
}

// MARK: - Identifiers carried in from other programs

public extension GenealogySite {
    /// An external identifier an imported file carried on a person.
    struct ExternalID: Identifiable, Hashable, Sendable {
        /// The tag's own name, or the site it names — "Ancestry", "FamilySearch", "UID".
        public let label: String
        public let value: String
        /// Set only where the identifier alone names a page without guesswork.
        public let url: URL?
        public var id: String { "\(label)\u{1F}\(value)" }
    }

    /// Identifiers Swarm keeps but does not model, read back out for display.
    ///
    /// Ancestry, MyHeritage and the rest stamp their own identifier on every person.
    /// Swarm preserves those branches verbatim so an exported file still carries them
    /// (`Person.unknownBranches`), which until now also meant nobody could read them.
    /// This only reads: the branches stay untouched, so nothing here can affect what a
    /// round trip writes back out.
    static func externalIDs(in branches: [[String]]) -> [ExternalID] {
        branches.compactMap { branch in
            guard let head = branch.first else { return nil }
            let headFields = head.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
            guard headFields.count == 3, headFields[0] == "1" else { return nil }
            let tag = String(headFields[1])
            let value = String(headFields[2]).trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, knownIDTags.contains(tag) else { return nil }

            // GEDCOM 7 spells the issuing authority as a URI under the identifier.
            let authority = branch.dropFirst()
                .first { $0.hasPrefix("2 TYPE ") }
                .map { String($0.dropFirst("2 TYPE ".count)).trimmingCharacters(in: .whitespaces) }

            return ExternalID(label: label(for: tag, authority: authority, value: value),
                              value: value,
                              url: url(for: tag, authority: authority, value: value))
        }
    }

    /// Level-1 tags other programs use for a person's identifier.
    private static var knownIDTags: Set<String> {
        ["EXID", "RFN", "AFN", "REFN", "RIN", "_UID", "_APID", "_FSFTID"]
    }

    private static func label(for tag: String, authority: String?, value _: String) -> String {
        if let authority, let site = match(url: authority) { return site.name }
        switch tag {
        case "_APID": return "Ancestry"
        case "_FSFTID": return "FamilySearch"
        case "AFN": return "Ancestral File"
        case "RFN": return "FamilySearch"
        // Nothing better to call it than what the file called it.
        default: return tag.hasPrefix("_") ? String(tag.dropFirst()) : tag
        }
    }

    /// A page for an identifier, only where one follows without guessing.
    ///
    /// `_APID` is Ancestry's citation identifier rather than a person page, and `_UID`,
    /// `REFN`, `RIN` and `AFN` name nothing outside the file that issued them — all of
    /// them stay unlinked. Whatever is built runs through `WebLink.openableURL`, so an
    /// imported file cannot smuggle in a `file://` or a custom scheme.
    private static func url(for tag: String, authority: String?, value: String) -> URL? {
        let candidate: String? = if let authority, let site = match(url: authority) {
            site.url(for: value)
        } else if let authority, authority.contains("://") {
            // GEDCOM 7: the identifier appends to its authority's URI.
            authority.hasSuffix("/") ? authority + value : authority + "/" + value
        } else if tag == "_FSFTID" || tag == "RFN" {
            all.first { $0.id == "familysearch" }
                .flatMap { $0.accepts(bareID: value) ? $0.url(for: value) : nil }
        } else {
            nil
        }
        guard let candidate else { return nil }
        return WebLink(url: candidate).openableURL
    }
}
