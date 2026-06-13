import Testing
@testable import FamilyTreeCore

/// Smoke test: confirms the FamilyTreeCore module builds and is importable by tests.
@Suite struct SmokeTests {
    @Test func treeStartsEmpty() {
        let tree = FamilyTree(name: "Тест")
        #expect(tree.name == "Тест")
        #expect(tree.people.isEmpty)
        #expect(tree.unions.isEmpty)
    }
}
