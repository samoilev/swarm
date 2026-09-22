import Foundation
@testable import SwarmCore
import Testing

/// A privacy export is only worth offering if nothing about a living person survives it.
/// These check the redaction itself, what reaches the serialized GEDCOM, and what lands
/// on disk in an exported archive.
@Suite(.serialized)
@MainActor
struct PrivacyRedactionTests {
    private final class Temp {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("swarm-privacy-tests-\(UUID().uuidString)", isDirectory: true)
        init() throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }

        deinit { try? FileManager.default.removeItem(at: url) }
    }

    /// A grandfather who died, his living son, and the son's wife — so the fixture has a
    /// public person, a private one, and a union spanning both states.
    private func makeTree() -> (tree: FamilyTree, living: Person, deceased: Person) {
        let deceased = Person(
            givenNames: "Пётр",
            surname: "Иванов",
            sex: .male,
            birthDate: "1901",
            birthPlace: "Тверь",
            deathDate: "1970",
            isLiving: false,
            occupation: "Плотник"
        )
        let living = Person(
            givenNames: "Анна",
            patronymic: "Петровна",
            surname: "Иванова",
            maidenName: "Смирнова",
            sex: .female,
            birthDate: "12.03.1975",
            birthPlace: "Москва",
            isLiving: true,
            occupation: "Врач",
            education: "МГУ",
            notes: "Живёт на Садовой 14",
            sources: ["Личный архив"]
        )
        living.gedcomXref = "I42"
        living.birthLat = 55.75
        living.birthLon = 37.61
        living.links = [WebLink(url: "https://example.com/anna", title: "Профиль")]
        living.attachments = [Attachment(storedName: "aaa.txt", originalName: "паспорт.txt")]
        living.unknownBranches = [["1 _CUSTOM Анна Петровна, Садовая 14"]]
        living.eventExtras = ["BIRT": ["2 NOTE роддом №4"]]
        living.citations = [Citation(sourceID: UUID(), page: "л. 7")]

        let spouse = Person(givenNames: "Игорь", surname: "Иванов", sex: .male, isLiving: true)
        let union = Union(
            partner1Id: living.id,
            partner2Id: spouse.id,
            marriageDate: "1998",
            marriagePlace: "Москва"
        )
        let ancestors = Union(partner1Id: deceased.id, childrenIds: [living.id])
        ancestors.marriageDate = "1930"

        let tree = FamilyTree(name: "Ивановы")
        tree.people = [deceased, living, spouse]
        tree.unions = [ancestors, union]
        return (tree, living, deceased)
    }

    @Test func redactionStripsEveryPersonalFieldOfALivingPerson() throws {
        let (tree, living, _) = makeTree()
        let redacted = tree.redactingLivingPeople(language: .russian)
        let person = try #require(redacted.people.first { $0.id == living.id })

        #expect(person.givenNames == "Живой человек")
        #expect(person.surname == "Иванова")
        #expect(person.patronymic == nil)
        #expect(person.maidenName == nil)
        #expect(person.birthDate == nil)
        #expect(person.birthPlace == nil)
        #expect(person.birthLat == nil)
        #expect(person.birthLon == nil)
        #expect(person.occupation == nil)
        #expect(person.education == nil)
        #expect(person.notes == nil)
        #expect(person.sources.isEmpty)
        #expect(person.citations.isEmpty)
        #expect(person.events.isEmpty)
        #expect(person.attachments.isEmpty)
        #expect(person.links.isEmpty)
        #expect(person.hasPhoto == false)
        #expect(person.unknownBranches.isEmpty)
        #expect(person.eventExtras.isEmpty)
        // Identity and interop anchors survive, or nothing would still point at them.
        #expect(person.id == living.id)
        #expect(person.gedcomXref == "I42")
        #expect(person.sex == .female)
        #expect(person.isLiving)
    }

    @Test func redactionLeavesDeceasedPeopleAndTheTreeItselfAlone() throws {
        let (tree, _, deceased) = makeTree()
        let redacted = tree.redactingLivingPeople(language: .russian)
        let person = try #require(redacted.people.first { $0.id == deceased.id })

        #expect(person.givenNames == "Пётр")
        #expect(person.birthPlace == "Тверь")
        #expect(person.deathDate == "1970")
        #expect(person.occupation == "Плотник")
        // The live tree is untouched — this is a copy, and the app keeps working on the
        // original after an export.
        #expect(tree.people.first { $0.isLiving }?.givenNames == "Анна")
        #expect(redacted.id == tree.id)
        #expect(redacted.name == "Ивановы")
    }

    @Test func redactionKeepsStructureButDropsALivingCouplesMarriage() throws {
        let (tree, living, deceased) = makeTree()
        let redacted = tree.redactingLivingPeople(language: .russian)

        let withLiving = try #require(redacted.unions.first { $0.partnerIds.contains(living.id) && $0.partner2Id != nil })
        #expect(withLiving.marriageDate == nil)
        #expect(withLiving.marriagePlace == nil)
        #expect(withLiving.partnerIds.count == 2)

        let ancestors = try #require(redacted.unions.first { $0.partnerIds == [deceased.id] })
        #expect(ancestors.marriageDate == "1930")
        #expect(ancestors.childrenIds == [living.id])
    }

    @Test func serializedGEDCOMCarriesNoLivingDetailsButKeepsTheLinks() {
        let (tree, living, _) = makeTree()
        let gedcom = GEDCOMSerializer.serialize(tree: tree.redactingLivingPeople(language: .russian)).gedcom

        for secret in ["Анна", "Петровна", "Смирнова", "Москва", "Врач", "МГУ", "Садовая", "1975", "роддом"] {
            #expect(!gedcom.contains(secret), "GEDCOM leaked \(secret)")
        }
        #expect(gedcom.contains("@I42@ INDI"))
        #expect(gedcom.contains("1 _FTSID \(living.id.uuidString)"))
        // Still placed in the family: a reader sees the shape without the person.
        #expect(gedcom.contains("1 FAMC"))
        #expect(gedcom.contains("1 FAMS"))
        #expect(gedcom.contains("Пётр"))
    }

    @Test func exportedArchiveOmitsLivingFilesAndTheRawImport() async throws {
        let library = try Temp()
        let exports = try Temp()
        let sourceFolder = try Temp()
        let attachmentSource = sourceFolder.url.appendingPathComponent("паспорт.txt")
        try Data("passport".utf8).write(to: attachmentSource)

        let store = TreeStore(storageFolder: library.url)
        let (tree, living, deceased) = makeTree()
        living.attachments = []
        _ = try await store.addTreeVerified(tree)

        let attachment = try store.prepareAttachment(in: tree, sourceURL: attachmentSource)
        living.attachments = [attachment]
        living.photoData = Data("living-portrait".utf8)
        deceased.photoData = Data("ancestor-portrait".utf8)
        _ = try await store.saveTree(tree)

        let bundle = try await store.exportTree(tree, to: exports.url, hidingLivingPeople: true, packaging: .folder).finalURL
        let fm = FileManager.default
        let ged = try #require(try fm.contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "ged" })
        let text = try String(contentsOf: ged, encoding: .utf8)
        #expect(!text.contains("Анна"))
        #expect(text.contains("Пётр"))

        // Exactly one portrait travels, and it is the ancestor's — portraits are named
        // after the GEDCOM xref, so the bytes are what identifies whose it is.
        let mediaFolder = bundle.appendingPathComponent("Media")
        let media = try fm.contentsOfDirectory(atPath: mediaFolder.path)
        #expect(media.count == 1)
        let portrait = try #require(media.first)
        #expect(try Data(contentsOf: mediaFolder.appendingPathComponent(portrait)) == Data("ancestor-portrait".utf8))

        let attachmentsPath = bundle.appendingPathComponent("Attachments").path
        let attachments = (try? fm.contentsOfDirectory(atPath: attachmentsPath)) ?? []
        #expect(attachments.isEmpty)
        #expect(!fm.fileExists(atPath: bundle.appendingPathComponent("original-import.ged").path))
    }

    @Test func exportWithoutTheOptionStillCarriesEverything() async throws {
        let library = try Temp()
        let exports = try Temp()
        let store = TreeStore(storageFolder: library.url)
        let (tree, living, _) = makeTree()
        _ = try await store.addTreeVerified(tree)
        living.photoData = Data("living-portrait".utf8)
        _ = try await store.saveTree(tree)

        let bundle = try await store.exportTree(tree, to: exports.url, packaging: .folder).finalURL
        let ged = try #require(try FileManager.default
            .contentsOfDirectory(at: bundle, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "ged" })
        let text = try String(contentsOf: ged, encoding: .utf8)
        #expect(text.contains("Анна"))
        #expect(text.contains("Садовая"))
    }
}
