import Foundation

/// Structural edits the editors make to a tree. They lived in the SwiftUI views, where
/// no unit test could reach them; the views now call these and keep only selection,
/// undo and saving.
public extension FamilyTree {
    /// Add `person` and link each relative in the order that lets several relatives
    /// collapse into shared families: parents before siblings, spouses before children.
    func addPerson(_ person: Person, relations: [(kind: RelationKind, personID: UUID)]) {
        people.append(person)
        for relation in relations.sorted(by: { $0.kind.applyOrder < $1.kind.applyOrder }) {
            addRelation(relation.kind, person: person, target: relation.personID)
        }
        optimizeRoot()
    }

    /// Remove a person and every reference to them.
    func deletePerson(_ personID: UUID) {
        for union in unions {
            union.childrenIds.removeAll { $0 == personID }
            if union.partner1Id == personID { union.partner1Id = nil }
            if union.partner2Id == personID { union.partner2Id = nil }
        }
        // A partner-less union that still has children is a valid sibling grouping
        // (possibly for unrelated people), so keep it — only drop unions with no
        // partners AND no children.
        unions.removeAll { $0.partner1Id == nil && $0.partner2Id == nil && $0.childrenIds.isEmpty }

        if homePersonId == personID {
            homePersonId = people.first(where: { $0.id != personID })?.id
        }
        if let rootID = rootUnionId, !unions.contains(where: { $0.id == rootID }) {
            rootUnionId = unions.first?.id
        }

        people.removeAll { $0.id == personID }
        parentLinks.removeAll { $0.parentID == personID || $0.childID == personID }
        optimizeRoot()
    }

    /// Unlink one parent from one child, and nothing else.
    ///
    /// A child's two parents share one union with the child's siblings. This used to
    /// clear the parent's slot in that union, which removed them as a parent of every
    /// sibling and broke up the couple. Now only this child leaves: the couple and the
    /// siblings stay as they were, and the child moves to a family with the other parent
    /// alone, taking that parent's link — its kind, notes and citations — along.
    func removeParent(_ parentID: UUID, of childID: UUID) {
        guard let family = unions.first(where: { $0.childrenIds.contains(childID) && $0.partnerIds.contains(parentID) }) else { return }
        family.childrenIds.removeAll { $0 == childID }
        parentLinks.removeAll { $0.childID == childID && $0.parentID == parentID && $0.unionID == family.id }

        if let otherParent = family.partnerIds.first(where: { $0 != parentID }) {
            let home: Union
            if let existing = unions.first(where: { $0 !== family && $0.partnerIds == [otherParent] }) {
                home = existing
            } else {
                home = Union(partner1Id: otherParent)
                unions.append(home)
            }
            if !home.childrenIds.contains(childID) { home.childrenIds.append(childID) }
            for index in parentLinks.indices where parentLinks[index].childID == childID &&
                parentLinks[index].parentID == otherParent && parentLinks[index].unionID == family.id {
                parentLinks[index].unionID = home.id
            }
        }
        optimizeRoot()
        reconcileParentLinks()
    }

    /// Unlink a sibling: they leave the family `personID` is a child of.
    func removeSibling(_ siblingID: UUID, of personID: UUID) {
        if let family = unions.first(where: { $0.childrenIds.contains(personID) && $0.childrenIds.contains(siblingID) }) {
            family.childrenIds.removeAll { $0 == siblingID }
        }
        optimizeRoot()
        reconcileParentLinks()
    }
}
