@testable import SwarmCore
import Testing

struct FamilyDateTests {

    @Test func parsesFullNumericDate() {
        let c = FamilyDate.parse("05.03.1978")
        #expect(c.day == 5 && c.month == 3 && c.year == 1978)
        #expect(c.isComplete)
    }

    @Test func parsesAlternateSeparators() {
        #expect(FamilyDate.parse("05/03/1978").month == 3)
        #expect(FamilyDate.parse("05-03-1978").day == 5)
        #expect(FamilyDate.parse("1978-03-05").day == 5)
    }

    @Test func parsesMonthYearAndYearOnly() {
        let my = FamilyDate.parse("03.1978")
        #expect(my.day == nil && my.month == 3 && my.year == 1978)
        let y = FamilyDate.parse("1978")
        #expect(y.day == nil && y.month == nil && y.year == 1978)
    }

    @Test func parsesMonthNames() {
        #expect(FamilyDate.parse("5 мар 1978").month == 3)
        #expect(FamilyDate.parse("5 MAR 1978").month == 3)
        #expect(FamilyDate.parse("5 марта 1978").day == 5)
        #expect(FamilyDate.parse("5 March 1978").year == 1978)
    }

    @Test func rejectsImpossibleDateButKeepsYear() {
        let c = FamilyDate.parse("32.13.1978")
        #expect(c.day == nil && c.month == nil)
        #expect(c.year == 1978) // recovered via the trailing-year fallback
    }

    @Test func rejectsDayImpossibleForMonth() {
        // 31 February is not a real date — the day must be dropped, the year kept.
        let feb = FamilyDate.parse("31.02.1900")
        #expect(feb.day == nil && feb.month == nil)
        #expect(feb.year == 1900)
        // 29 Feb is valid in a leap year but not in a common year.
        #expect(FamilyDate.parse("29.02.2000").day == 29) // 2000 is a leap year
        #expect(FamilyDate.parse("29.02.1900").day == nil) // 1900 is not (century rule)
        // 31 April doesn't exist.
        #expect(FamilyDate.parse("31.04.1980").day == nil)
    }

    @Test func normalizeProducesStandardForm() {
        #expect(FamilyDate.normalize("5 MAR 1978") == "05.03.1978")
        #expect(FamilyDate.normalize("1978-03-05") == "05.03.1978")
        #expect(FamilyDate.normalize("1978") == "1978")
        // Unparseable input is returned unchanged rather than dropped.
        #expect(FamilyDate.normalize("неизвестно") == "неизвестно")
    }

    @Test func toGEDCOMFormatsByPrecision() {
        #expect(FamilyDate.toGEDCOM("05.03.1978") == "5 MAR 1978")
        #expect(FamilyDate.toGEDCOM("03.1978") == "MAR 1978")
        #expect(FamilyDate.toGEDCOM("1978") == "1978")
    }

    @Test func presentsEnglishDatesWithoutRegionalAmbiguity() {
        let full = FamilyDate.parse("05.03.1978")
        #expect(full.displayString(language: .english) == "5 Mar 1978")
        #expect(full.displayString(language: .russian) == "5 мар 1978")
        #expect(FamilyDate.parse("Mar 1978").displayString(language: .english) == "Mar 1978")
    }

    @Test func structuredDatesAcceptBothLanguagesAndPreserveGEDCOMWireFormat() {
        let english = GenealogyDate(userInput: "5 Mar 1978", language: .english)
        let russian = GenealogyDate(userInput: "5 марта 1978", language: .russian)
        let iso = GenealogyDate(userInput: "1978-03-05", language: .english)

        #expect(english.isValid)
        #expect(russian.isValid)
        #expect(iso.isValid)
        #expect(english.displayValue(language: .english) == "5 Mar 1978")
        #expect(english.displayValue(language: .russian) == "5 мар 1978")
        #expect(english.canonicalGEDCOMValue == "5 MAR 1978")
        #expect(russian.canonicalGEDCOMValue == english.canonicalGEDCOMValue)
        #expect(iso.canonicalGEDCOMValue == english.canonicalGEDCOMValue)
        #expect(GenealogyDate(userInput: "31 Feb 1978", language: .english).isValid == false)
    }

    @Test func calculatesPreciseAge() {
        let r = FamilyDate.calculateAge(birth: "01.01.2000", death: "01.01.2020")
        #expect(r?.years == 20)
        #expect(r?.approximate == false)
    }

    @Test func calculatesApproximateAgeFromYears() {
        let r = FamilyDate.calculateAge(birth: "2000", death: "2020")
        #expect(r?.years == 20)
        #expect(r?.approximate == true)
    }

    /// `31 FEB 1900` names no real day. Its year still shows, but the card used to add
    /// an age counted from it, "b. 1900 (~126)", as if the date were merely vague.
    @Test func anImpossibleDateGivesNoAge() {
        for impossible in ["31 FEB 1900", "31.02.1900", "1900-02-31", "30 фев 1900"] {
            #expect(FamilyDate.calculateAge(birth: impossible, death: nil) == nil, "\(impossible)")
            #expect(FamilyDate.calculateAge(birth: "1850", death: impossible) == nil, "\(impossible)")
        }
        for usable in ["1900", "ABT 1900", "1 JAN 1900", "29 FEB 1904"] {
            #expect(FamilyDate.calculateAge(birth: usable, death: "1950") != nil, "\(usable)")
        }
    }

    @Test func anImportedImpossibleBirthDateShowsItsYearWithoutAnAge() throws {
        let gedcom = "0 HEAD\n0 @I1@ INDI\n1 NAME BadDay /Person/\n1 BIRT\n2 DATE 31 FEB 1900\n0 TRLR"
        let person = try #require(GEDCOMCodec.parse(gedcom).tree.people.first)
        #expect(person.lifespan.contains("1900"))
        #expect(!person.lifespan.contains("("))
    }

    @Test func ageSubtractsUnreachedBirthday() {
        // Birthday not yet reached in the death year → one year younger.
        let r = FamilyDate.calculateAge(birth: "12.2000", death: "06.2020")
        #expect(r?.years == 19)
    }

    /// "MONTH YYYY" skipped the 1…9999 bound every other form has, so an Int-sized
    /// year reached `year * 10000` and `endYear - birthYear` and trapped.
    @Test func namedMonthYearsOutsideTheSupportedRangeAreRejected() throws {
        let huge = "JAN 9223372036854775807", tiny = "JAN -9223372036854775808"
        #expect(FamilyDate.parseExact(huge) == nil)
        #expect(FamilyDate.parseExact(tiny) == nil)
        #expect(FamilyDate.parseExact("JAN 9999")?.year == 9999)
        #expect(!GenealogyDate(rawGEDCOM: "BET \(huge) AND FEB 9223372036854775807").isValid)
        #expect(!GenealogyDate.PartialDate(year: 10000).isValid)
        #expect(FamilyDate.calculateAge(birth: tiny, death: nil) == nil)

        let text = """
        0 HEAD
        1 GEDC
        2 VERS 7.0
        0 @I1@ INDI
        1 BIRT
        2 DATE \(huge)
        1 DEAT
        2 DATE \(huge)
        1 FAMS @F1@
        0 @I2@ INDI
        1 BIRT
        2 DATE BET \(huge) AND FEB 9223372036854775807
        1 FAMC @F1@
        0 @F1@ FAM
        1 HUSB @I1@
        1 CHIL @I2@
        0 TRLR
        """
        let tree = try GEDCOMCodec.parse(text).tree
        _ = TreeValidator.validate(tree)
        _ = TreeLayoutEngine(config: LayoutConfig()).layout(tree: tree, direction: .topDown)
    }
}
