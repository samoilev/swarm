import Foundation

/// Isolated working copy used by editors. Mutations made through `draftTree` cannot
/// reach the live tree until the caller validates and persists them successfully.
public final class EditSession {
    public let draftTree: FamilyTree

    public init(tree: FamilyTree) throws {
        let data = try JSONEncoder().encode(tree)
        draftTree = try JSONDecoder().decode(FamilyTree.self, from: data)
    }
}
