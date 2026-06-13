@testable import FamilyTreeCore
import Foundation
import Testing

struct FamilyTreeTests {

    private func tree(_ people: Person...) -> FamilyTree {
        let t = FamilyTree(name: "T")
        t.people = people
        return t
    }

    @Test func addParentLinksChildToParentUnion() {
        let me = Person(givenNames: "Я", sex: .male)
        let dad = Person(givenNames: "Папа", sex: .male)
        let t = tree(me, dad)
        t.addRelation(.parent, person: me, target: dad.id)
        let idx = FamilyIndex(tree: t)
        #expect(idx.mergedParentIds(me.id).father == dad.id)
    }

    @Test func addBothParentsCollapsesIntoOneUnion() {
        let me = Person(givenNames: "Я", sex: .male)
        let dad = Person(givenNames: "Папа", sex: .male)
        let mom = Person(givenNames: "Мама", sex: .female)
        let t = tree(me, dad, mom)
        t.addRelation(.parent, person: me, target: dad.id)
        t.addRelation(.parent, person: me, target: mom.id)
        // A child belongs to exactly one parent union holding both parents.
        #expect(t.unions.count == 1)
        let parents = FamilyIndex(tree: t).mergedParentIds(me.id)
        #expect(parents.father == dad.id)
        #expect(parents.mother == mom.id)
    }

    @Test func addSpouseFormsCouple() {
        let a = Person(givenNames: "А", sex: .male)
        let b = Person(givenNames: "Б", sex: .female)
        let t = tree(a, b)
        t.addRelation(.spouse, person: a, target: b.id)
        #expect(t.unions.count == 1)
        #expect(Set(t.unions[0].partnerIds) == Set([a.id, b.id]))
    }

    @Test func addChildThenSpouseShareOneUnion() {
        let dad = Person(givenNames: "Папа", sex: .male)
        let kid = Person(givenNames: "Дитя", sex: .female)
        let mom = Person(givenNames: "Мама", sex: .female)
        let t = tree(dad, kid, mom)
        t.addRelation(.child, person: dad, target: kid.id)
        t.addRelation(.spouse, person: dad, target: mom.id)
        // The spouse slots into dad's existing single-parent union, keeping the child.
        #expect(t.unions.count == 1)
        #expect(t.unions[0].childrenIds.contains(kid.id))
        #expect(Set(t.unions[0].partnerIds) == Set([dad.id, mom.id]))
    }

    @Test func siblingsShareParentUnion() {
        let a = Person(givenNames: "А", sex: .male)
        let b = Person(givenNames: "Б", sex: .female)
        let t = tree(a, b)
        t.addRelation(.sibling, person: a, target: b.id)
        let idx = FamilyIndex(tree: t)
        #expect(idx.mergedSiblingIds(a.id) == [b.id])
    }

    @Test func optimizeRootDeduplicatesDuplicatePartnerUnions() {
        let dad = Person(givenNames: "Папа", sex: .male)
        let mom = Person(givenNames: "Мама", sex: .female)
        let kid1 = Person(givenNames: "Раз", sex: .male)
        let kid2 = Person(givenNames: "Два", sex: .female)
        let t = tree(dad, mom, kid1, kid2)
        // Two separate FAM records for the same couple — should merge on optimize.
        t.unions = [
            Union(partner1Id: dad.id, partner2Id: mom.id, childrenIds: [kid1.id]),
            Union(partner1Id: dad.id, partner2Id: mom.id, childrenIds: [kid2.id]),
        ]
        t.optimizeRoot()
        #expect(t.unions.count == 1)
        #expect(Set(t.unions[0].childrenIds) == Set([kid1.id, kid2.id]))
    }

    @Test func optimizeRootPicksTopAncestralCouple() {
        let gf = Person(givenNames: "Дед", sex: .male)
        let gm = Person(givenNames: "Баба", sex: .female)
        let dad = Person(givenNames: "Папа", sex: .male)
        let mom = Person(givenNames: "Мама", sex: .female)
        let me = Person(givenNames: "Я", sex: .male)
        let t = tree(gf, gm, dad, mom, me)
        let top = Union(partner1Id: gf.id, partner2Id: gm.id, childrenIds: [dad.id])
        t.unions = [
            Union(partner1Id: dad.id, partner2Id: mom.id, childrenIds: [me.id]),
            top,
        ]
        t.optimizeRoot()
        // The couple whose partners are nobody's children is the root.
        #expect(t.rootUnionId == top.id)
    }

    @Test func sharedParentCountDistinguishesFullAndHalf() {
        let dad = Person(givenNames: "Папа", sex: .male)
        let mom = Person(givenNames: "Мама", sex: .female)
        let step = Person(givenNames: "Мачеха", sex: .female)
        let a = Person(givenNames: "А", sex: .male)
        let full = Person(givenNames: "Полный", sex: .male)
        let half = Person(givenNames: "Полу", sex: .male)
        let t = tree(dad, mom, step, a, full, half)
        t.unions = [
            Union(partner1Id: dad.id, partner2Id: mom.id, childrenIds: [a.id, full.id]),
            Union(partner1Id: dad.id, partner2Id: step.id, childrenIds: [half.id]),
        ]
        let idx = FamilyIndex(tree: t)
        #expect(idx.sharedParentCount(a.id, full.id) == 2)
        #expect(idx.sharedParentCount(a.id, half.id) == 1)
    }
}
