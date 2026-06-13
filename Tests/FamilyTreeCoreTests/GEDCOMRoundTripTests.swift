import Testing
import Foundation
@testable import FamilyTreeCore

/// Round-trip and interop coverage for the GEDCOM parser/serializer. Identity is
/// regenerated on parse, so everything is compared by content, not UUID.
@Suite struct GEDCOMRoundTripTests {

    /// A representative tree: a deceased couple (one with a maiden name, birth coords,
    /// multi-line notes), their living child, marriage data, home person and root union.
    private func makeTree() -> FamilyTree {
        let tree = FamilyTree(name: "Тестовое дерево", subtitle: "Подзаголовок")

        let father = Person(
            givenNames: "Иван", patronymic: "Петрович", surname: "Сидоров", sex: .male,
            birthDate: "05.03.1901", birthPlace: "Москва",
            deathDate: "12.11.1970", deathPlace: "Ленинград", isLiving: false,
            occupation: "Инженер", education: "МГУ",
            notes: "Первая строка\nВторая строка", sources: ["Перепись 1926"]
        )
        father.birthLat = 55.7558; father.birthLon = 37.6173
        father.burialPlace = "Волково кладбище"

        let mother = Person(
            givenNames: "Анна", patronymic: "Сергеевна", surname: "Сидорова",
            maidenName: "Иванова", sex: .female,
            birthDate: "1905", birthPlace: "Тверь", deathDate: "1980", isLiving: false
        )
        mother.deathLat = 56.8587; mother.deathLon = 35.9176

        let child = Person(
            givenNames: "Пётр", patronymic: "Иванович", surname: "Сидоров", sex: .male,
            birthDate: "20.06.1930", birthPlace: "Москва", isLiving: true
        )
        child.attachments = [Attachment(storedName: "abc.pdf", originalName: "Свидетельство.pdf")]

        tree.people = [father, mother, child]
        let union = Union(
            partner1Id: father.id, partner2Id: mother.id,
            marriageDate: "14.04.1928", marriagePlace: "Москва",
            childrenIds: [child.id]
        )
        tree.unions = [union]
        tree.homePersonId = child.id
        tree.rootUnionId = union.id
        return tree
    }

    private func roundTrip(_ tree: FamilyTree) -> GEDCOMParser.ParsedTree {
        let gedcom = GEDCOMSerializer.serialize(tree: tree).gedcom
        return GEDCOMParser.parse(gedcom: gedcom)
    }

    @Test func preservesTreeMetadata() {
        let parsed = roundTrip(makeTree())
        #expect(parsed.name == "Тестовое дерево")
        #expect(parsed.subtitle == "Подзаголовок")
        #expect(parsed.people.count == 3)
        #expect(parsed.unions.count == 1)
        // Home person and root union pointers resolve back to the right records.
        #expect(parsed.homePersonId != nil)
        #expect(parsed.rootUnionId == parsed.unions.first?.id)
        let home = parsed.people.first { $0.id == parsed.homePersonId }
        #expect(home?.givenNames == "Пётр")
    }

    @Test func preservesPersonFields() {
        let parsed = roundTrip(makeTree())
        let father = parsed.people.first { $0.givenNames == "Иван" }!
        #expect(father.surname == "Сидоров")
        #expect(father.patronymic == "Петрович")
        #expect(father.sex == .male)
        #expect(father.isLiving == false)
        #expect(father.birthDate == "05.03.1901")
        #expect(father.birthPlace == "Москва")
        #expect(father.deathPlace == "Ленинград")
        #expect(father.occupation == "Инженер")
        #expect(father.education == "МГУ")
        #expect(father.burialPlace == "Волково кладбище")
        #expect(father.notes == "Первая строка\nВторая строка")
        #expect(father.sources.contains("Перепись 1926"))
    }

    @Test func preservesMaidenName() {
        let parsed = roundTrip(makeTree())
        let mother = parsed.people.first { $0.givenNames == "Анна" }!
        #expect(mother.surname == "Сидорова")
        #expect(mother.maidenName == "Иванова")
    }

    @Test func preservesUnionAndChildLinks() {
        let parsed = roundTrip(makeTree())
        let idx = FamilyIndex(tree: treeFrom(parsed))
        let child = parsed.people.first { $0.givenNames == "Пётр" }!
        let parents = idx.mergedParentIds(child.id)
        let father = parents.father.flatMap { id in parsed.people.first { $0.id == id } }
        let mother = parents.mother.flatMap { id in parsed.people.first { $0.id == id } }
        #expect(father?.givenNames == "Иван")
        #expect(mother?.givenNames == "Анна")
        let union = parsed.unions.first!
        #expect(union.marriageDate == "14.04.1928")
        #expect(union.marriagePlace == "Москва")
    }

    @Test func roundTripsCoordinatesViaStandardMap() {
        let parsed = roundTrip(makeTree())
        let father = parsed.people.first { $0.givenNames == "Иван" }!
        #expect(abs((father.birthLat ?? 0) - 55.7558) < 1e-4)
        #expect(abs((father.birthLon ?? 0) - 37.6173) < 1e-4)
        let mother = parsed.people.first { $0.givenNames == "Анна" }!
        #expect(abs((mother.deathLat ?? 0) - 56.8587) < 1e-4)
        #expect(abs((mother.deathLon ?? 0) - 35.9176) < 1e-4)
    }

    @Test func emitsStandardMapTriple() {
        let gedcom = GEDCOMSerializer.serialize(tree: makeTree()).gedcom
        #expect(gedcom.contains("3 MAP"))
        #expect(gedcom.contains("4 LATI N55.7558"))
        #expect(gedcom.contains("4 LONG E37.6173"))
    }

    @Test func preservesAttachments() {
        let parsed = roundTrip(makeTree())
        let child = parsed.people.first { $0.givenNames == "Пётр" }!
        #expect(child.attachments.count == 1)
        #expect(child.attachments.first?.storedName == "abc.pdf")
        #expect(child.attachments.first?.originalName == "Свидетельство.pdf")
    }

    // MARK: - Interop & robustness

    /// Coordinates written by other tools (standard MAP/LATI/LONG, southern/western
    /// hemispheres) must import correctly.
    @Test func importsThirdPartyCoordinates() {
        let gedcom = """
        0 HEAD
        1 _NAME External
        0 @I1@ INDI
        1 NAME Maria /Silva/
        1 SEX F
        1 BIRT
        2 PLAC São Paulo, Brazil
        3 MAP
        4 LATI S23.5505
        4 LONG W46.6333
        0 TRLR
        """
        let parsed = GEDCOMParser.parse(gedcom: gedcom)
        let maria = parsed.people.first!
        #expect(maria.surname == "Silva")
        #expect(abs((maria.birthLat ?? 0) - (-23.5505)) < 1e-4)
        #expect(abs((maria.birthLon ?? 0) - (-46.6333)) < 1e-4)
    }

    /// Legacy private `_COORD` (what older saves used) must still import.
    @Test func importsLegacyCoordTag() {
        let gedcom = """
        0 HEAD
        0 @I1@ INDI
        1 NAME Test /Person/
        1 BIRT
        2 PLAC Somewhere
        2 _COORD 50.45 30.52
        0 TRLR
        """
        let p = GEDCOMParser.parse(gedcom: gedcom).people.first!
        #expect(abs((p.birthLat ?? 0) - 50.45) < 1e-4)
        #expect(abs((p.birthLon ?? 0) - 30.52) < 1e-4)
    }

    /// A value that begins with what looks like another tag must not be mis-split.
    @Test func valueContainingTagWordIsNotMisparsed() {
        let gedcom = """
        0 HEAD
        0 @I1@ INDI
        1 NAME Ann /Lee/
        1 OCCU DATE clerk and PLAC keeper
        0 TRLR
        """
        let p = GEDCOMParser.parse(gedcom: gedcom).people.first!
        #expect(p.occupation == "DATE clerk and PLAC keeper")
    }

    /// A file missing its TRLR (and with trailing blank lines) must still parse.
    @Test func toleratesMissingTrailer() {
        let gedcom = "0 HEAD\n0 @I1@ INDI\n1 NAME Bob /Stone/\n1 SEX M\n\n"
        let parsed = GEDCOMParser.parse(gedcom: gedcom)
        #expect(parsed.people.count == 1)
        #expect(parsed.people.first?.surname == "Stone")
    }

    /// Father and mother recorded in separate FAM records must merge into one parentage.
    @Test func mergesSplitFamilyParents() {
        let gedcom = """
        0 HEAD
        0 @I1@ INDI
        1 NAME Dad /Roe/
        1 SEX M
        0 @I2@ INDI
        1 NAME Mom /Doe/
        1 SEX F
        0 @I3@ INDI
        1 NAME Kid /Roe/
        0 @F1@ FAM
        1 HUSB @I1@
        1 CHIL @I3@
        0 @F2@ FAM
        1 WIFE @I2@
        1 CHIL @I3@
        0 TRLR
        """
        let parsed = GEDCOMParser.parse(gedcom: gedcom)
        let idx = FamilyIndex(tree: treeFrom(parsed))
        let kid = parsed.people.first { $0.givenNames == "Kid" }!
        let parents = idx.mergedParentIds(kid.id)
        #expect(parents.father != nil)
        #expect(parents.mother != nil)
    }

    // Rebuild a FamilyTree shell from a ParsedTree so FamilyIndex can be used.
    private func treeFrom(_ parsed: GEDCOMParser.ParsedTree) -> FamilyTree {
        let t = FamilyTree(name: parsed.name)
        t.people = parsed.people
        t.unions = parsed.unions
        t.homePersonId = parsed.homePersonId
        t.rootUnionId = parsed.rootUnionId
        return t
    }
}
