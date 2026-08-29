import Foundation
@testable import SwarmCore
import Testing

/// The undo controller and the snapshot-restore primitives it depends on.
/// `applyContent` completeness matters beyond undo: every rollback path in the
/// app routes through it, and a field it forgets is silently lost on restore.
@MainActor
struct TreeUndoControllerTests {

    private func makeTree() -> FamilyTree {
        let tree = FamilyTree(name: "Семья", subtitle: "Ветвь")
        let a = Person(givenNames: "Иван", surname: "Иванов", sex: .male)
        let b = Person(givenNames: "Мария", surname: "Иванова", sex: .female)
        tree.people = [a, b]
        tree.unions = [Union(partner1Id: a.id, partner2Id: b.id)]
        tree.homePersonId = a.id
        return tree
    }

    @Test func sessionRoundTripRestoresAndRedoes() {
        let tree = makeTree()
        let undo = TreeUndoController()

        undo.begin(tree)
        tree.people[0].givenNames = "Пётр"
        undo.commit(tree)
        #expect(undo.canUndo)

        #expect(undo.undo(tree))
        #expect(tree.people[0].givenNames == "Иван")
        #expect(undo.canRedo)

        #expect(undo.redo(tree))
        #expect(tree.people[0].givenNames == "Пётр")
    }

    @Test func unchangedSessionRecordsNothing() {
        let tree = makeTree()
        let undo = TreeUndoController()
        undo.begin(tree)
        undo.commit(tree)
        #expect(!undo.canUndo)
        #expect(!undo.undo(tree))
    }

    @Test func cancelRestoresTheSessionBase() {
        let tree = makeTree()
        let undo = TreeUndoController()
        undo.begin(tree)
        tree.people[0].givenNames = "Пётр"
        undo.cancel(tree)
        #expect(tree.people[0].givenNames == "Иван")
        #expect(!undo.canUndo)
    }

    @Test func stackIsCappedAtFiftyEntries() {
        let tree = makeTree()
        let undo = TreeUndoController()
        for i in 0 ..< 60 {
            undo.begin(tree)
            tree.people[0].givenNames = "Имя \(i)"
            undo.commit(tree)
        }
        var undone = 0
        while undo.undo(tree) { undone += 1 }
        #expect(undone == 50)
        // The oldest surviving entry is #9's state, not the original.
        #expect(tree.people[0].givenNames == "Имя 9")
    }

    @Test func undoWhileSessionActiveIsCallersResponsibility() {
        let tree = makeTree()
        let undo = TreeUndoController()
        undo.begin(tree)
        #expect(undo.isSessionActive)
        undo.commit(tree)
        #expect(!undo.isSessionActive)
    }

    // MARK: - applyContent completeness

    /// Every content field must survive deepCopy → applyContent. A hand-copied
    /// rollback that forgets a new field re-creates the bug class this guards.
    @Test func familyTreeApplyContentIsComplete() throws {
        let original = makeRichTree()
        let snapshot = try original.deepCopy()

        let target = try original.deepCopy()
        // Scramble everything applyContent is responsible for.
        target.name = "x"
        target.subtitle = nil
        target.people = []
        target.unions = []
        target.sourceRecords = []
        target.parentLinks = []
        target.homePersonId = nil
        target.rootUnionId = nil
        target.headUnknownBranches = []
        target.unknownRecords = []
        target.gedcomDocument = nil
        target.importReport = nil
        target.acceptedBaselineIssueIDs = []
        target.schemaVersion = 99

        target.applyContent(of: snapshot)
        target.updatedAt = original.updatedAt // applyContent stamps "now" by design

        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        #expect(try enc.encode(target) == enc.encode(original))
    }

    @Test func personApplyContentIsComplete() throws {
        let original = makeRichTree().people[0]
        let data = try JSONEncoder().encode(original)
        let snapshot = try JSONDecoder().decode(Person.self, from: data)

        let target = try JSONDecoder().decode(Person.self, from: data)
        target.givenNames = "x"
        target.patronymic = nil
        target.surname = "x"
        target.maidenName = nil
        target.sex = .unknown
        target.birthDate = nil
        target.birthPlace = nil
        target.birthLat = nil
        target.birthLon = nil
        target.deathDate = nil
        target.deathPlace = nil
        target.deathLat = nil
        target.deathLon = nil
        target.isLiving = true
        target.burialPlace = nil
        target.burialLat = nil
        target.burialLon = nil
        target.occupation = nil
        target.education = nil
        target.notes = nil
        target.sources = []
        target.names = []
        target.events = []
        target.citations = []
        target.attachments = []
        target.links = []
        target.photoFilename = nil
        target.gedcomXref = nil
        target.unknownBranches = []
        target.eventExtras = [:]

        target.applyContent(of: snapshot)

        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        #expect(try enc.encode(target) == enc.encode(original))
    }

    /// A person exercising every codable content field.
    private func makeRichTree() -> FamilyTree {
        let tree = makeTree()
        let p = tree.people[0]
        p.patronymic = "Иванович"
        p.maidenName = "Петров"
        p.birthDate = "1 JAN 1900"
        p.birthPlace = "Москва"
        p.birthLat = 55.75
        p.birthLon = 37.61
        p.deathDate = "2 FEB 1980"
        p.deathPlace = "Санкт-Петербург"
        p.deathLat = 59.93
        p.deathLon = 30.33
        p.isLiving = false
        p.burialPlace = "Санкт-Петербург"
        p.burialLat = 59.9
        p.burialLon = 30.3
        p.occupation = "Врач"
        p.education = "Университет"
        p.notes = "Заметка"
        p.sources = ["Метрическая книга"]
        p.links = [WebLink(url: "https://example.org", title: "Архив")]
        p.attachments = [Attachment(storedName: "abc.pdf", originalName: "справка.pdf", notes: "Скан")]
        p.photoFilename = "I1.jpg"
        p.gedcomXref = "@I1@"
        p.unknownBranches = [["1 _CUSTOM tag", "2 CONT more"]]
        p.eventExtras = ["BIRT": ["2 NOTE born at home"]]
        tree.sourceRecords = [SourceRecord(title: "Метрическая книга")]
        return tree
    }
}
