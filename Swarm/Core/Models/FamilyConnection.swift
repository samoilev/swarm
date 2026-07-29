import Foundation

/// One undirected relationship edge in the family graph.
///
/// The canonical ordering makes `A—B` equal to `B—A`, which lets lineage and
/// shortest-path calculations identify the exact connector routes to emphasize.
public struct FamilyConnection: Hashable, Sendable {
    public let firstID: UUID
    public let secondID: UUID

    public init(_ firstID: UUID, _ secondID: UUID) {
        precondition(firstID != secondID, "A family connection requires two people")
        if firstID.uuidString < secondID.uuidString {
            self.firstID = firstID
            self.secondID = secondID
        } else {
            self.firstID = secondID
            self.secondID = firstID
        }
    }

    public func contains(_ personID: UUID) -> Bool {
        firstID == personID || secondID == personID
    }
}
