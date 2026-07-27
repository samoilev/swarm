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
        #expect(FamilyDate.normalize("1978") == "1978")
        // Unparseable input is returned unchanged rather than dropped.
        #expect(FamilyDate.normalize("неизвестно") == "неизвестно")
    }

    @Test func toGEDCOMFormatsByPrecision() {
        #expect(FamilyDate.toGEDCOM("05.03.1978") == "5 MAR 1978")
        #expect(FamilyDate.toGEDCOM("03.1978") == "MAR 1978")
        #expect(FamilyDate.toGEDCOM("1978") == "1978")
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

    @Test func ageSubtractsUnreachedBirthday() {
        // Birthday not yet reached in the death year → one year younger.
        let r = FamilyDate.calculateAge(birth: "12.2000", death: "06.2020")
        #expect(r?.years == 19)
    }
}
