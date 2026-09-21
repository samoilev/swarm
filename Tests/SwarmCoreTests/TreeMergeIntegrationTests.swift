import Foundation
@testable import SwarmCore
import Testing

/// End-to-end coverage for the merge engine. These tests deliberately cross the
/// preview, mutation, persistence and GEDCOM parse boundaries instead of checking
/// the candidate matcher in isolation.
@Suite(.serialized)
@MainActor
struct TreeMergeIntegrationTests {
    private final class Temp {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-merge-integration-\(UUID().uuidString)", isDirectory: true)

        init() throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    /// A realistic overlap: 1,500 records on each side, 750 shared people, 500
    /// family records per input and evidence owned by both trees. The assertion on
    /// the reparsed file catches failures that an in-memory count alone would miss.
    @Test func largeOverlappingTreesMergeSaveAndReparse() async throws {
        let temp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        let local = makeGenerationalTree(name: "Local", range: 0 ..< 1_500)
        let sharedIDs = Dictionary(uniqueKeysWithValues: local.people.enumerated().map { ($0.offset, $0.element.id) })
        let incoming = makeGenerationalTree(
            name: "Incoming",
            range: 750 ..< 2_250,
            sharedIDs: sharedIDs,
            noteEvery: 127
        )
        try await store.addTreeVerified(local)

        let started = Date()
        let engine = TreeMergeEngine(store: store)
        let preview = engine.preview(local: local, incoming: incoming)
        #expect(preview.automaticMatches.count == 750)
        #expect(preview.heuristicSuggestions.isEmpty)
        #expect(preview.incomingOnlyPersonIDs.count == 750)

        _ = try await engine.apply(preview, to: local)
        let elapsed = Date().timeIntervalSince(started)

        #expect(local.people.count == 2_250)
        #expect(local.unions.count == 750)
        #expect(local.parentLinks.count == 1_500)
        #expect(local.sourceRecords.count == 2)
        #expect(TreeValidator.validate(local).allSatisfy { !$0.isBlocking })
        #expect(local.person(byId: sharedIDs[762]!)?.notes == "Incoming note 762")

        let reparsed = try GEDCOMCodec.parse(store.gedFileURL(for: local)).tree
        #expect(reparsed.people.count == 2_250)
        #expect(reparsed.unions.count == 750)
        #expect(reparsed.parentLinks.count == 1_500)
        #expect(TreeValidator.validate(reparsed).allSatisfy { !$0.isBlocking })

        // This is intentionally generous for debug/CI machines. Its job is to catch
        // an accidental return to minutes-long pairwise work, not micro-optimise I/O.
        #expect(elapsed < 15, "Large merge took \(elapsed) seconds")
    }

    @Test func conflictChoicesSurviveTheSavedMerge() async throws {
        let temp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        let localSource = SourceRecord(title: "Local register")
        let incomingSource = SourceRecord(title: "Incoming register")
        let local = FamilyTree(name: "Local")
        let left = Person(givenNames: "Anna", surname: "Local", birthDate: "1900")
        left.citations = [Citation(sourceID: localSource.id, page: "1")]
        local.people = [left]
        local.sourceRecords = [localSource]
        try await store.addTreeVerified(local)

        let incoming = FamilyTree(name: "Incoming")
        let right = Person(givenNames: "Anne", surname: "Incoming", birthDate: "1901")
        right.id = left.id
        right.citations = [Citation(sourceID: incomingSource.id, page: "2")]
        incoming.people = [right]
        incoming.sourceRecords = [incomingSource]

        let engine = TreeMergeEngine(store: store)
        var preview = engine.preview(local: local, incoming: incoming)
        #expect(Set(preview.conflicts.map(\.field)) == ["names", "events", "citations"])
        for index in preview.conflicts.indices {
            switch preview.conflicts[index].field {
            case "names": preview.conflicts[index].choice = .incoming
            case "events": preview.conflicts[index].choice = .local
            case "citations": preview.conflicts[index].choice = .both
            default: break
            }
        }

        _ = try await engine.apply(preview, to: local)
        let merged = try #require(local.people.first)
        #expect(merged.givenNames == "Anne")
        #expect(merged.surname == "Incoming")
        #expect(merged.birthDate == "1900")
        #expect(Set(merged.citations.map(\.page)) == ["1", "2"])
        #expect(Set(local.sourceRecords.map(\.title)) == ["Local register", "Incoming register"])

        let reparsed = try GEDCOMCodec.parse(store.gedFileURL(for: local)).tree
        #expect(reparsed.people.first?.givenNames == "Anne")
        #expect(reparsed.people.first?.birthDate == "1900")
        #expect(Set(reparsed.people.first?.citations.map(\.page) ?? []) == ["1", "2"])
    }

    /// Fail on the final incoming person, after matches and source records have
    /// already changed the destination. The in-memory model must return byte-for-byte
    /// to its pre-merge Codable representation and no partial save may land.
    @Test func lateAttachmentFailureRollsBackAHundredsRecordMerge() async throws {
        let temp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        let local = makeGenerationalTree(name: "Rollback", range: 0 ..< 300)
        try await store.addTreeVerified(local)
        let before = try canonicalJSON(local)
        let committed = try Data(contentsOf: store.gedFileURL(for: local))

        let incoming = FamilyTree(name: "Incoming")
        incoming.people = try local.people.map { person in
            let copy = try clone(person)
            copy.notes = "This mutation must roll back"
            return copy
        }
        incoming.sourceRecords = [SourceRecord(title: "Must roll back")]
        let final = Person(givenNames: "Missing", surname: "Attachment")
        final.attachments = [Attachment(storedName: "absent.pdf", originalName: "absent.pdf")]
        incoming.people.append(final)

        let engine = TreeMergeEngine(store: store)
        let preview = engine.preview(local: local, incoming: incoming)
        do {
            _ = try await engine.apply(preview, to: local)
            Issue.record("Merge unexpectedly succeeded with a missing attachment")
        } catch let error as TreeMergeError {
            guard case .attachmentMissing("absent.pdf") = error else {
                Issue.record("Unexpected merge error: \(error)")
                return
            }
        }

        #expect(try canonicalJSON(local) == before)
        #expect(try Data(contentsOf: store.gedFileURL(for: local)) == committed)
        #expect(store.recoveryItems(for: local).contains {
            $0.kind == .migrationBackup && $0.displayName.contains("pre-merge")
        })
    }

    /// A common genealogy ambiguity (two namesakes in the destination) produces two
    /// suggestions for one incoming person. Unless the user explicitly accepts one,
    /// neither suggestion may collapse or mutate any record.
    @Test func ambiguousHeuristicsStaySeparateUntilExplicitlyAccepted() async throws {
        let temp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        let local = FamilyTree(name: "Local")
        let first = Person(givenNames: "John", surname: "Smith", birthDate: "1900", birthPlace: "York")
        let second = Person(givenNames: "John", surname: "Smith", birthDate: "1900", birthPlace: "York")
        local.people = [first, second]
        try await store.addTreeVerified(local)

        let incoming = FamilyTree(name: "Incoming")
        incoming.people = [Person(
            givenNames: "John", surname: "Smith", birthDate: "1900", birthPlace: "York", notes: "Incoming"
        )]
        let engine = TreeMergeEngine(store: store)
        let preview = engine.preview(local: local, incoming: incoming)
        #expect(preview.heuristicSuggestions.count == 2)
        #expect(preview.acceptedHeuristicMatchIDs.isEmpty)

        _ = try await engine.apply(preview, to: local)
        #expect(local.people.count == 3)
        #expect(first.notes == nil)
        #expect(second.notes == nil)
        #expect(local.people.count { $0.notes == "Incoming" } == 1)
    }

    @Test(arguments: [
        "corpus-curie", "corpus-darwin", "corpus-kennedy",
        "corpus-romanov", "corpus-roosevelt", "corpus-tudors",
    ])
    func mergingARealCorpusWithItselfIsIdempotent(fixtureName: String) async throws {
        let fixture = try #require(Bundle.module.url(
            forResource: fixtureName,
            withExtension: "ged",
            subdirectory: "Fixtures"
        ))
        let local = try GEDCOMCodec.parse(fixture).tree
        let incoming = try GEDCOMCodec.parse(fixture).tree
        let originalPeople = local.people.count
        let originalUnions = local.unions.count
        let originalLinks = local.parentLinks.count
        let originalEdges = relationshipEdges(in: local)
        let temp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        try await store.addTreeVerified(local)

        let engine = TreeMergeEngine(store: store)
        let preview = engine.preview(local: local, incoming: incoming)
        #expect(preview.automaticMatches.count == originalPeople)
        #expect(preview.incomingOnlyPersonIDs.isEmpty)
        _ = try await engine.apply(preview, to: local)

        #expect(local.people.count == originalPeople)
        // optimizeRoot canonicalises redundant family records (the Romanov corpus
        // intentionally contains one), but must neither add a duplicate nor lose an
        // actual partner/child relationship.
        #expect(local.unions.count <= originalUnions)
        #expect(relationshipEdges(in: local) == originalEdges)
        #expect(local.parentLinks.count == originalLinks)
        #expect(TreeValidator.validate(local, context: .init(
            acceptedBaselineIssueIDs: local.acceptedBaselineIssueIDs
        )).allSatisfy { !$0.isBlocking })
    }

    @Test(arguments: [
        ("curie-joliot", "darwin-wedgwood"),
        ("kennedy", "roosevelt"),
        ("romanovy", "tudor-succession"),
    ])
    func distinctShippingExamplesMergeWithMediaAndRemainImportable(
        localName: String,
        incomingName: String
    ) async throws {
        func example(_ name: String) throws -> URL {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
            let url = root.appendingPathComponent("Examples/\(name)/\(name).ged")
            #expect(FileManager.default.fileExists(atPath: url.path))
            return url
        }

        let temp = try Temp()
        let incomingTemp = try Temp()
        let store = TreeStore(storageFolder: temp.url)
        let incomingStore = TreeStore(storageFolder: incomingTemp.url)
        let local = try await store.importGEDCOM(from: example(localName)).tree
        let incoming = try await incomingStore.importGEDCOM(from: example(incomingName)).tree
        let expectedPeople = local.people.count + incoming.people.count
        let expectedAttachments = local.people.flatMap(\.attachments).count + incoming.people.flatMap(\.attachments).count
        let expectedEdges = relationshipEdges(in: local).union(relationshipEdges(in: incoming))

        let engine = TreeMergeEngine(store: store)
        let preview = engine.preview(local: local, incoming: incoming)
        #expect(preview.automaticMatches.isEmpty)
        _ = try await engine.apply(preview, to: local)

        #expect(local.people.count == expectedPeople)
        #expect(local.people.flatMap(\.attachments).count == expectedAttachments)
        #expect(local.people.flatMap(\.attachments).allSatisfy {
            FileManager.default.fileExists(atPath: store.attachmentURL($0, in: local).path)
        })
        #expect(relationshipEdges(in: local).isSuperset(of: expectedEdges))
        let reparsed = try GEDCOMCodec.parse(store.gedFileURL(for: local)).tree
        #expect(reparsed.people.count == expectedPeople)
        #expect(TreeValidator.validate(reparsed, context: .init(
            acceptedBaselineIssueIDs: reparsed.acceptedBaselineIssueIDs
        )).allSatisfy { !$0.isBlocking })
    }

    private func makeGenerationalTree(
        name: String,
        range: Range<Int>,
        sharedIDs: [Int: UUID] = [:],
        noteEvery: Int? = nil
    ) -> FamilyTree {
        let tree = FamilyTree(name: name)
        let source = SourceRecord(title: "\(name) register")
        tree.sourceRecords = [source]
        var byOrdinal: [Int: Person] = [:]
        for ordinal in range {
            let person = Person(
                givenNames: "Person \(ordinal)",
                surname: "Family \(ordinal / 3)",
                sex: ordinal % 3 == 1 ? .female : .male,
                birthDate: String(1700 + ordinal % 300),
                birthPlace: "Place \(ordinal % 80)"
            )
            if let id = sharedIDs[ordinal] { person.id = id }
            if let noteEvery, ordinal % noteEvery == 0 { person.notes = "Incoming note \(ordinal)" }
            if ordinal % 97 == 0 {
                person.citations = [Citation(sourceID: source.id, page: "p. \(ordinal)")]
            }
            tree.people.append(person)
            byOrdinal[ordinal] = person
        }
        for first in stride(from: range.lowerBound, to: range.upperBound - 2, by: 3) {
            guard let father = byOrdinal[first],
                  let mother = byOrdinal[first + 1],
                  let child = byOrdinal[first + 2] else { continue }
            let union = Union(
                partner1Id: father.id,
                partner2Id: mother.id,
                marriageDate: String(1720 + first % 280),
                marriagePlace: "Union place \(first % 50)",
                childrenIds: [child.id]
            )
            tree.unions.append(union)
            tree.parentLinks.append(ParentLink(parentID: father.id, childID: child.id, unionID: union.id))
            tree.parentLinks.append(ParentLink(parentID: mother.id, childID: child.id, unionID: union.id))
        }
        tree.homePersonId = tree.people.first?.id
        tree.rootUnionId = tree.unions.first?.id
        return tree
    }

    private func canonicalJSON(_ tree: FamilyTree) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(tree)
    }

    private func clone<T: Codable>(_ value: T) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONEncoder().encode(value))
    }

    private func relationshipEdges(in tree: FamilyTree) -> Set<String> {
        var edges = Set<String>()
        for union in tree.unions {
            for child in union.childrenIds {
                for parent in union.partnerIds {
                    edges.insert("parent:\(parent.uuidString):\(child.uuidString)")
                }
            }
            let partners = union.partnerIds.map(\.uuidString).sorted()
            if partners.count == 2 { edges.insert("partners:\(partners.joined(separator: ":"))") }
        }
        return edges
    }
}
