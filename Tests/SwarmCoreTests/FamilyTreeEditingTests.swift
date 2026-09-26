import Foundation
@testable import SwarmCore
import Testing

struct FamilyTreeEditingTests {
    private struct Family {
        let tree = FamilyTree(name: "Семья")
        let dad = Person(givenNames: "Иван", sex: .male)
        let mom = Person(givenNames: "Анна", sex: .female)
        let first = Person(givenNames: "Пётр", sex: .male)
        let second = Person(givenNames: "Ольга", sex: .female)
        let union: Union

        init() {
            union = Union(partner1Id: dad.id, partner2Id: mom.id, marriageDate: "1901", childrenIds: [first.id, second.id])
            tree.people = [dad, mom, first, second]
            tree.unions = [union]
            tree.reconcileParentLinks()
        }
    }

    /// Removing a parent from one child used to clear that parent's slot in the shared
    /// family, which also took them away from every sibling and broke up the couple.
    @Test func removingAParentUnlinksOnlyThatChild() throws {
        let family = Family()
        let tree = family.tree
        let index = try #require(tree.parentLinks.firstIndex { $0.parentID == family.mom.id && $0.childID == family.first.id })
        tree.parentLinks[index].kind = .adoptive
        tree.parentLinks[index].notes = "Усыновлён в 1910"

        tree.removeParent(family.dad.id, of: family.first.id)

        let parents = FamilyIndex(tree: tree)
        #expect(parents.mergedParentIds(family.first.id).father == nil)
        #expect(parents.mergedParentIds(family.first.id).mother == family.mom.id)
        #expect(parents.mergedParentIds(family.second.id).father == family.dad.id)
        #expect(parents.mergedParentIds(family.second.id).mother == family.mom.id)
        #expect(family.union.partnerIds == [family.dad.id, family.mom.id])
        #expect(family.union.marriageDate == "1901")
        let momsLink = try #require(tree.parentLinks.first { $0.parentID == family.mom.id && $0.childID == family.first.id })
        #expect(momsLink.kind == .adoptive)
        #expect(momsLink.notes == "Усыновлён в 1910")
        #expect(!tree.parentLinks.contains { $0.parentID == family.dad.id && $0.childID == family.first.id })
    }

    @Test func removingTheOnlyParentLeavesTheSiblingsWithThem() {
        let tree = FamilyTree(name: "Одна мама")
        let mom = Person(givenNames: "Анна", sex: .female)
        let first = Person(givenNames: "Пётр")
        let second = Person(givenNames: "Ольга")
        tree.people = [mom, first, second]
        tree.unions = [Union(partner1Id: mom.id, childrenIds: [first.id, second.id])]
        tree.reconcileParentLinks()

        tree.removeParent(mom.id, of: first.id)

        #expect(tree.unions.map(\.childrenIds) == [[second.id]])
        #expect(tree.parentLinks.map(\.childID) == [second.id])
    }

    @Test func removingASiblingTakesThemOutOfTheSharedFamily() {
        let family = Family()

        family.tree.removeSibling(family.second.id, of: family.first.id)

        #expect(family.union.childrenIds == [family.first.id])
        #expect(!family.tree.parentLinks.contains { $0.childID == family.second.id })
    }

    @Test func deletingAPersonRemovesEveryReferenceToThem() {
        let family = Family()
        let tree = family.tree
        tree.homePersonId = family.dad.id

        tree.deletePerson(family.dad.id)

        #expect(!tree.people.contains { $0.id == family.dad.id })
        #expect(family.union.partnerIds == [family.mom.id])
        #expect(!tree.parentLinks.contains { $0.parentID == family.dad.id })
        #expect(tree.homePersonId != nil && tree.homePersonId != family.dad.id)
    }

    /// Two parents and a sibling chosen together collapse into one family.
    @Test func addingAPersonWithRelativesBuildsOneFamily() {
        let family = Family()
        let tree = family.tree
        let newcomer = Person(givenNames: "Мария", sex: .female)

        tree.addPerson(newcomer, relations: [
            (.sibling, family.first.id),
            (.parent, family.dad.id),
            (.parent, family.mom.id),
        ])

        #expect(tree.unions.count == 1)
        #expect(family.union.childrenIds.contains(newcomer.id))
        #expect(tree.people.contains { $0.id == newcomer.id })
    }
}
