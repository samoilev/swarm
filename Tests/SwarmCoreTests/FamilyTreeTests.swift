import Foundation
@testable import SwarmCore
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

    @Test func newSiblingJoinsExistingParentUnionAndSurvivesOptimize() {
        let dad = Person(givenNames: "Папа", sex: .male)
        let mom = Person(givenNames: "Мама", sex: .female)
        let brother = Person(givenNames: "Брат", sex: .male)
        let sister = Person(givenNames: "Сестра", sex: .female)
        let t = tree(dad, mom, brother, sister)
        t.unions = [Union(partner1Id: dad.id, partner2Id: mom.id, childrenIds: [brother.id])]

        t.addRelation(.sibling, person: sister, target: brother.id)
        t.optimizeRoot()

        #expect(Set(t.unions[0].childrenIds) == Set([brother.id, sister.id]))
        let idx = FamilyIndex(tree: t)
        #expect(idx.mergedParentIds(sister.id).father == dad.id)
        #expect(idx.mergedSiblingIds(sister.id) == [brother.id])
    }

    @Test func linkingAParentlessSiblingGroupMovesTheWholeGroup() {
        let dad = Person(givenNames: "Папа", sex: .male)
        let known = Person(givenNames: "Знакомый", sex: .male)
        let a = Person(givenNames: "А", sex: .male)
        let b = Person(givenNames: "Б", sex: .female)
        let t = tree(dad, known, a, b)
        t.unions = [Union(partner1Id: dad.id, childrenIds: [known.id])]
        t.addRelation(.sibling, person: a, target: b.id)

        t.addRelation(.sibling, person: a, target: known.id)
        t.optimizeRoot()

        // Б must come along; leaving her behind would silently drop her sibling link.
        let idx = FamilyIndex(tree: t)
        #expect(idx.mergedParentIds(b.id).father == dad.id)
        #expect(Set(idx.mergedSiblingIds(b.id)) == Set([a.id, known.id]))
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

    @Test func optimizeRootKeepsWidowedUnionWithMarriageData() {
        let widow = Person(givenNames: "Вдова", sex: .female)
        // A couple whose other partner was removed, leaving one partner + a recorded
        // marriage. optimizeRoot() must not discard the surviving marriage record.
        let u = Union(partner1Id: widow.id, partner2Id: nil)
        u.marriageDate = "12.06.1950"
        u.marriagePlace = "Москва"
        let t = tree(widow)
        t.unions = [u]
        t.optimizeRoot()
        #expect(t.unions.count == 1)
        #expect(t.unions.first?.marriageDate == "12.06.1950")
        #expect(t.unions.first?.marriagePlace == "Москва")
    }

    @Test func optimizeRootStillDropsEmptyLonePartnerUnion() {
        // A lone partner with no children and no marriage data is a true orphan link.
        let p = Person(givenNames: "Один", sex: .male)
        let t = tree(p)
        t.unions = [Union(partner1Id: p.id, partner2Id: nil)]
        t.optimizeRoot()
        #expect(t.unions.isEmpty)
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

    /// Onboarding's last step names the *relative's* role, but `addRelation` reads the
    /// kind from the new person's perspective. Get the inversion wrong and the father a
    /// user just typed becomes their child — silently, in the file that is the record.
    @Test func firstRelativeRolesLinkInTheRightDirection() {
        for role in FirstRelative.allCases {
            let me = Person(givenNames: "Я", surname: "Иванов", sex: .male)
            let t = tree(me)
            let relative = Person(givenNames: "Родня", surname: "Иванов", sex: role.sex)
            t.people.append(relative)
            t.addRelation(role.relation, person: relative, target: me.id)

            let index = FamilyIndex(tree: t)
            switch role {
            case .father:
                #expect(index.mergedParentIds(me.id).father == relative.id)
                #expect(relative.sex == .male)
            case .mother:
                #expect(index.mergedParentIds(me.id).mother == relative.id)
                #expect(relative.sex == .female)
            case .spouse:
                #expect(t.unions.contains { $0.partnerIds.contains(me.id) && $0.partnerIds.contains(relative.id) })
                #expect(index.mergedParentIds(me.id).father == nil)
            case .child:
                #expect(index.mergedParentIds(relative.id).father == me.id)
            }
        }
    }

    /// A spouse arrives under their own surname; everyone else usually shares one.
    @Test func onlySpouseSkipsTheInheritedSurname() {
        #expect(FirstRelative.spouse.inheritsSurname == false)
        #expect(FirstRelative.allCases.filter(\.inheritsSurname).count == 3)
    }

    // MARK: - Lossless family merging

    private static func couple(_ families: String) -> String {
        """
        0 HEAD
        1 GEDC
        2 VERS 5.5.1
        0 @I1@ INDI
        1 NAME Иван /Петров/
        1 SEX M
        0 @I2@ INDI
        1 NAME Анна /Петрова/
        1 SEX F
        0 @I3@ INDI
        1 NAME Пётр /Петров/
        1 FAMC @F1@
        0 @I4@ INDI
        1 NAME Ольга /Петрова/
        1 FAMC @F2@
        2 PEDI adopted
        0 @S1@ SOUR
        1 TITL Метрическая книга
        \(families)
        0 TRLR
        """
    }

    /// Two FAM records for one couple are folded into one after every edit. The one
    /// dropped used to take its divorce, citation, custom tags and the adoption of its
    /// child with it; everything now moves to the family that stays.
    @Test func foldingDuplicateFamiliesKeepsEverythingTheyRecorded() throws {
        let imported = try GEDCOMCodec.parse(Self.couple("""
        0 @F1@ FAM
        1 HUSB @I1@
        1 WIFE @I2@
        1 CHIL @I3@
        1 MARR
        2 DATE 1901
        0 @F2@ FAM
        1 HUSB @I1@
        1 WIFE @I2@
        1 CHIL @I4@
        1 DIV
        2 DATE 1920
        1 SOUR @S1@
        2 PAGE 12
        1 _CUSTOM keep me
        """))
        let tree = imported.tree
        let olga = try #require(tree.people.first { $0.givenNames == "Ольга" })

        tree.optimizeRoot()
        tree.reconcileParentLinks()

        #expect(tree.unions.count == 1)
        let family = try #require(tree.unions.first)
        #expect(family.event(ofKind: .marriage)?.date?.year == 1901)
        #expect(family.event(ofKind: .divorce)?.date?.year == 1920)
        #expect(family.citations.map(\.page) == ["12"])
        #expect(family.unknownBranches.contains { $0.first?.contains("_CUSTOM keep me") == true })
        let olgasLinks = tree.parentLinks.filter { $0.childID == olga.id }
        #expect(olgasLinks.count == 2)
        #expect(olgasLinks.allSatisfy { $0.kind == .adoptive && $0.unionID == family.id })

        let saved = try GEDCOMCodec.serialize(tree: tree, document: imported.document).gedcom
        let reread = try GEDCOMCodec.parse(saved).tree
        #expect(reread.unions.first?.event(ofKind: .divorce)?.date?.year == 1920)
        #expect(saved.contains("_CUSTOM keep me"))
        #expect(saved.contains("PEDI adopted"))
    }

    /// When both records state the same event differently, folding would have to throw
    /// one version away, so both families stay.
    @Test func duplicateFamiliesThatDisagreeAreLeftApart() throws {
        let tree = try GEDCOMCodec.parse(Self.couple("""
        0 @F1@ FAM
        1 HUSB @I1@
        1 WIFE @I2@
        1 CHIL @I3@
        1 DIV
        2 DATE 1920
        0 @F2@ FAM
        1 HUSB @I1@
        1 WIFE @I2@
        1 CHIL @I4@
        1 DIV
        2 DATE 1925
        """)).tree

        tree.optimizeRoot()

        #expect(tree.unions.count == 2)
        #expect(Set(tree.unions.compactMap { $0.event(ofKind: .divorce)?.date?.year }) == [1920, 1925])
    }

    private static func sharedChild(noteA: String, noteB: String) -> String {
        """
        0 HEAD
        1 GEDC
        2 VERS 5.5.1
        0 @I1@ INDI
        1 NAME Иван /Петров/
        1 SEX M
        0 @I2@ INDI
        1 NAME Анна /Петрова/
        1 SEX F
        0 @I3@ INDI
        1 NAME Пётр /Петров/
        1 FAMC @F1@
        2 _PLINK @I1@
        3 NOTE \(noteA)
        1 FAMC @F2@
        2 _PLINK @I1@
        3 NOTE \(noteB)
        0 @F1@ FAM
        1 HUSB @I1@
        1 WIFE @I2@
        1 CHIL @I3@
        0 @F2@ FAM
        1 HUSB @I1@
        1 WIFE @I2@
        1 CHIL @I3@
        0 TRLR
        """
    }

    /// Folding joins the two links a child has to one parent, and the joined link kept
    /// only the first note. Families whose links carry different notes now stay apart.
    @Test func duplicateFamiliesWithDifferentLinkNotesAreLeftApart() throws {
        let tree = try GEDCOMCodec.parse(Self.sharedChild(noteA: "LINK-NOTE-A", noteB: "LINK-NOTE-B")).tree

        tree.optimizeRoot()
        tree.reconcileParentLinks()

        #expect(tree.unions.count == 2)
        let saved = try GEDCOMCodec.serialize(tree: tree, document: nil).gedcom
        #expect(saved.contains("LINK-NOTE-A"))
        #expect(saved.contains("LINK-NOTE-B"))
    }

    @Test func duplicateFamiliesWithTheSameLinkNoteStillFold() throws {
        let tree = try GEDCOMCodec.parse(Self.sharedChild(noteA: "LINK-NOTE", noteB: "LINK-NOTE")).tree

        tree.optimizeRoot()

        #expect(tree.unions.count == 1)
    }

    /// A single-partner family with no children used to survive only if it held a
    /// marriage date or place. A citation or any other recorded detail keeps it too.
    @Test func aLonePartnerFamilyWithOnlyACitationIsKept() throws {
        let tree = try GEDCOMCodec.parse(Self.couple("""
        0 @F1@ FAM
        1 HUSB @I1@
        1 SOUR @S1@
        2 PAGE 7
        """)).tree

        tree.optimizeRoot()

        #expect(tree.unions.contains { $0.citations.map(\.page) == ["7"] })
    }
}
