import Foundation
@testable import SwarmCore
import Testing

struct CopyCleanupTests {
    @Test func russianCountsAndDistantKinshipAgree() {
        #expect(L10n.count(1, .child, language: .russian) == "1 ребёнок")
        #expect(L10n.count(2, .child, language: .russian) == "2 ребёнка")
        #expect(L10n.count(11, .child, language: .russian) == "11 детей")
        #expect(L10n.count(21, .citation, language: .russian) == "21 ссылка на источник")
        let formatter = KinshipFormatter(language: .russian)
        #expect(formatter.label(for: .ancestor(generation: 5, sex: .unknown)) == "Предок в 5-м поколении")
        #expect(formatter.label(for: .descendant(generation: 6, sex: .unknown)) == "Потомок в 6-м поколении")
        #expect(formatter.label(for: .cousin(degree: 1, removed: 5, direction: .older, sex: .male)).contains("5 поколений"))
        #expect(formatter.label(for: .inLaw(.brotherHusbandsSide)) == "Деверь")
    }

    @Test func englishKinshipStaysReadableAcrossGenerationsAndUncertainty() {
        let formatter = KinshipFormatter(language: .english)
        #expect(formatter.label(for: .ancestor(generation: 4, sex: .male)) == "Great-great-grandfather")
        #expect(formatter.label(for: .ancestor(generation: 5, sex: .unknown)) == "Ancestor, 5 generations back")
        #expect(formatter.label(for: .descendant(generation: 6, sex: .unknown)) == "Descendant, 6 generations down")
        #expect(formatter.label(for: .parent(sex: .male, kind: .uncertain)) == "Father (uncertain)")
        #expect(formatter.label(for: .qualified(base: .parent(sex: .female, kind: .adoptive), kind: .uncertain)) == "Adoptive mother (uncertain)")
    }

    @Test func uncertaintySurvivesGEDCOMAndJSONWithoutLosingRelationshipType() throws {
        let parent = Person(givenNames: "Parent", sex: .male)
        let child = Person(givenNames: "Child")
        let union = Union(partner1Id: parent.id, childrenIds: [child.id])
        let tree = FamilyTree(name: "Test")
        tree.people = [parent, child]
        tree.unions = [union]
        tree.parentLinks = [ParentLink(parentID: parent.id, childID: child.id, unionID: union.id, kind: .adoptive, isUncertain: true)]
        let text = GEDCOMSerializer.serialize(tree: tree).gedcom
        let parsed = GEDCOMParser.parse(gedcom: text)
        let link = try #require(parsed.parentLinks.first)
        #expect(link.kind == .adoptive)
        #expect(link.hasUncertainParentage)
        let decoded = try JSONDecoder().decode(ParentLink.self, from: JSONEncoder().encode(link))
        #expect(decoded == link)
        let edge = try #require(FamilyIndex(tree: tree).parentEdges(of: child.id).first)
        #expect(edge.qualifiers == [.adoptive, .uncertain])
        let result = try #require(RelationshipCalculator(tree: tree).relationship(from: child, to: parent, language: .russian))
        #expect(result.name.contains("Приёмный отец"))
        #expect(result.name.contains("предполагаемой"))
        let lineage = LineageCalculator(index: FamilyIndex(tree: tree)).compute(for: child)
        #expect(lineage.labels[parent.id]?.contains("предполагаемой") == true)
    }

    @Test func legacyParentLinksDecodeWithoutInventingCertainty() throws {
        let old = ParentLink(parentID: UUID(), childID: UUID(), kind: .uncertain)
        let data = try JSONEncoder().encode(old)
        #expect(!String(decoding: data, as: UTF8.self).contains("isUncertain"))
        let decoded = try JSONDecoder().decode(ParentLink.self, from: data)
        #expect(decoded.kind == .uncertain)
        #expect(decoded.hasUncertainParentage)
    }

    @Test @MainActor func mergeKeepsUncertaintyWithoutDuplicatingParentEdge() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = TreeStore(storageFolder: folder)
        let parent = Person(givenNames: "Parent")
        let child = Person(givenNames: "Child")
        let union = Union(partner1Id: parent.id, childrenIds: [child.id])
        let tree = FamilyTree(name: "Merge")
        tree.people = [parent, child]
        tree.unions = [union]
        tree.parentLinks = [ParentLink(parentID: parent.id, childID: child.id, unionID: union.id, kind: .adoptive)]
        try await store.addTreeVerified(tree)
        let incoming = try JSONDecoder().decode(FamilyTree.self, from: JSONEncoder().encode(tree))
        incoming.parentLinks[0].isUncertain = true
        let engine = TreeMergeEngine(store: store)
        _ = try await engine.apply(engine.preview(local: tree, incoming: incoming), to: tree)
        #expect(tree.parentLinks.count == 1)
        #expect(tree.parentLinks[0].kind == .adoptive)
        #expect(tree.parentLinks[0].hasUncertainParentage)
        let reloaded = TreeStore(storageFolder: folder)
        #expect(reloaded.trees.first?.parentLinks.first?.hasUncertainParentage == true)
    }

    @Test func unspecifiedTypeDoesNotImplyUncertainty() {
        let parent = Person(givenNames: "Parent")
        let child = Person(givenNames: "Child")
        let union = Union(partner1Id: parent.id, childrenIds: [child.id])
        let tree = FamilyTree(name: "Unspecified")
        tree.people = [parent, child]
        tree.unions = [union]
        for uncertain in [false, true] {
            tree.parentLinks = [ParentLink(parentID: parent.id, childID: child.id, unionID: union.id, kind: .unspecified, isUncertain: uncertain ? true : nil)]
            let parsed = GEDCOMParser.parse(gedcom: GEDCOMSerializer.serialize(tree: tree).gedcom)
            #expect(parsed.parentLinks.first?.kind == .unspecified)
            #expect(parsed.parentLinks.first?.hasUncertainParentage == uncertain)
        }
    }

}
