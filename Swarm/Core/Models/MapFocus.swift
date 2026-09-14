import Foundation

/// Decides how strongly each person's pins and path draw on the map once a branch is selected.
///
/// The map reuses the selection the rest of the app already computes: `selectedID` is the person
/// under the cursor, `branchIDs` is their lineage (or the relationship path between two ⌘-clicked
/// people). Everyone outside that set fades, so a single family's movement stays readable.
public struct MapFocus: Equatable {
    /// How much of the family stays at full strength around the selected person.
    public enum Scope: String, CaseIterable, Equatable {
        /// Only the selected person. Everyone else fades, lineage included.
        case person
        /// The selected person's whole lineage stays lit.
        case branch
        /// Nobody fades.
        case everyone
    }

    public enum Emphasis {
        /// The selected person's own pins and path.
        case focused
        /// On the selected branch, or nothing is selected at all.
        case normal
        /// Off the branch: drawn faded, still clickable.
        case dimmed

        /// Pin opacity.
        public var pinOpacity: Double { self == .dimmed ? 0.2 : 1 }
        /// Path opacity. A path fades less than a pin because the map line color already
        /// carries its own alpha and SwiftUI multiplies the two.
        public var lineOpacity: Double { self == .dimmed ? 0.25 : 1 }
    }

    public let selectedID: UUID?
    public let branchIDs: Set<UUID>
    public let scope: Scope

    public init(selectedID: UUID?, branchIDs: Set<UUID>, scope: Scope = .branch) {
        self.selectedID = selectedID
        self.branchIDs = branchIDs
        self.scope = scope
    }

    /// Without a selection the map draws exactly as it did before this feature existed.
    /// Person scope never consults `branchIDs`, so an unresolved lineage still fades the map.
    public var isActive: Bool {
        guard selectedID != nil else { return false }
        switch scope {
        case .person: return true
        case .branch: return !branchIDs.isEmpty
        case .everyone: return false
        }
    }

    public func emphasis(for personID: UUID) -> Emphasis {
        guard isActive else { return .normal }
        if personID == selectedID { return .focused }
        guard scope == .branch else { return .dimmed }
        return branchIDs.contains(personID) ? .normal : .dimmed
    }

    /// A clustered pin stands for several people, so it takes the strongest emphasis among them.
    public func emphasis(forAny personIDs: some Sequence<UUID>) -> Emphasis {
        var strongest = Emphasis.dimmed
        for personID in personIDs {
            switch emphasis(for: personID) {
            case .focused: return .focused
            case .normal: strongest = .normal
            case .dimmed: continue
            }
        }
        return strongest
    }
}
