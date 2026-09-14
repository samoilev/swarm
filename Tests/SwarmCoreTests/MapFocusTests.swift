import Foundation
@testable import SwarmCore
import Testing

/// Map dimming rules: who keeps full strength once a branch is selected, and who fades.
struct MapFocusTests {

    private let selected = UUID()
    private let relative = UUID()
    private let stranger = UUID()

    private var activeFocus: MapFocus {
        MapFocus(selectedID: selected, branchIDs: [selected, relative])
    }

    @Test func withoutASelectionNothingFades() {
        let idle = MapFocus(selectedID: nil, branchIDs: [])
        #expect(idle.isActive == false)
        #expect(idle.emphasis(for: stranger) == .normal)
        #expect(idle.emphasis(forAny: [stranger, relative]) == .normal)

        // A selection whose branch never resolved must not blank out the whole map.
        let emptyBranch = MapFocus(selectedID: selected, branchIDs: [])
        #expect(emptyBranch.isActive == false)
        #expect(emptyBranch.emphasis(for: stranger) == .normal)
    }

    @Test func selectedPersonLeadsTheirBranchAndOutsidersFade() {
        let focus = activeFocus
        #expect(focus.isActive)
        #expect(focus.emphasis(for: selected) == .focused)
        #expect(focus.emphasis(for: relative) == .normal)
        #expect(focus.emphasis(for: stranger) == .dimmed)
    }

    @Test func clusteredPinTakesTheStrongestEmphasisAmongItsPeople() {
        let focus = activeFocus
        // One person on the branch is enough to keep a shared place visible.
        #expect(focus.emphasis(forAny: [stranger, relative]) == .normal)
        #expect(focus.emphasis(forAny: [stranger, relative, selected]) == .focused)
        #expect(focus.emphasis(forAny: [stranger, UUID()]) == .dimmed)
        #expect(focus.emphasis(forAny: []) == .dimmed)
    }

    @Test func personScopeFadesTheLineageToo() {
        let focus = MapFocus(selectedID: selected, branchIDs: [selected, relative], scope: .person)
        #expect(focus.isActive)
        #expect(focus.emphasis(for: selected) == .focused)
        // The whole point of the scope: a relative on the branch fades like a stranger.
        #expect(focus.emphasis(for: relative) == .dimmed)
        #expect(focus.emphasis(for: stranger) == .dimmed)
    }

    @Test func personScopeDoesNotDependOnTheBranchSet() {
        let focus = MapFocus(selectedID: selected, branchIDs: [], scope: .person)
        #expect(focus.isActive)
        #expect(focus.emphasis(for: selected) == .focused)
        #expect(focus.emphasis(for: stranger) == .dimmed)
    }

    @Test func everyoneScopeNeverFades() {
        let focus = MapFocus(selectedID: selected, branchIDs: [selected, relative], scope: .everyone)
        #expect(focus.isActive == false)
        #expect(focus.emphasis(for: selected) == .normal)
        #expect(focus.emphasis(for: relative) == .normal)
        #expect(focus.emphasis(for: stranger) == .normal)
    }

    @Test func personScopeClusterKeepsOnlyTheSelectedPerson() {
        let focus = MapFocus(selectedID: selected, branchIDs: [selected, relative], scope: .person)
        #expect(focus.emphasis(forAny: [stranger, selected]) == .focused)
        // A place shared by two relatives is no longer worth keeping lit.
        #expect(focus.emphasis(forAny: [relative, stranger]) == .dimmed)
    }

    @Test func lineageResultDrivesTheFade() {
        let tree = FamilyTree(name: "Род")
        let father = Person(givenNames: "Отец", surname: "Тест", sex: .male)
        let me = Person(givenNames: "Я", surname: "Тест", sex: .male)
        let son = Person(givenNames: "Сын", surname: "Тест", sex: .male)
        let outsider = Person(givenNames: "Чужой", surname: "Тест", sex: .male)
        tree.people = [father, me, son, outsider]
        tree.unions = [
            Union(partner1Id: father.id, partner2Id: nil, childrenIds: [me.id]),
            Union(partner1Id: me.id, partner2Id: nil, childrenIds: [son.id]),
        ]

        let lineage = LineageCalculator(index: FamilyIndex(tree: tree)).compute(for: me)
        let focus = MapFocus(selectedID: me.id, branchIDs: lineage.ids)

        #expect(focus.emphasis(for: me.id) == .focused)
        #expect(focus.emphasis(for: father.id) == .normal)
        #expect(focus.emphasis(for: son.id) == .normal)
        #expect(focus.emphasis(for: outsider.id) == .dimmed)
    }
}
