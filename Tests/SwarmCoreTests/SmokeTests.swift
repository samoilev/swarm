@testable import SwarmCore
import Testing

/// Smoke test: confirms the SwarmCore module builds and is importable by tests.
struct SmokeTests {
    @Test func treeStartsEmpty() {
        let tree = FamilyTree(name: "Тест")
        #expect(tree.name == "Тест")
        #expect(tree.people.isEmpty)
        #expect(tree.unions.isEmpty)
    }
}
