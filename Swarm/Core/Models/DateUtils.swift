import Foundation

/// Standardized date handling for family tree dates.
/// Internal format: "DD.MM.YYYY" (e.g. "05.03.1978")
/// Also supports partial dates: "MM.YYYY" or "YYYY"
/// Handles GEDCOM format on import: "5 MAR 1978", "MAR 1978", "1978"
public enum FamilyDate {

    // MARK: - Parse any date string into components

    public struct Components: Hashable, Sendable {
        public var day: Int?
        public var month: Int?
        public var year: Int?

        public init(day: Int? = nil, month: Int? = nil, year: Int? = nil) {
            self.day = day
            self.month = month
            self.year = year
        }

        public var isComplete: Bool {
            day != nil && month != nil && year != nil
        }

        /// Format as standardized string
        public var formatted: String {
            if let d = day, let m = month, let y = year {
                return String(format: "%02d.%02d.%04d", d, m, y)
            } else if let m = month, let y = year {
                return String(format: "%02d.%04d", m, y)
            } else if let y = year {
                return "\(y)"
            }
            return ""
        }

        /// Formatted for user display in the selected app language.
        public var displayString: String {
            displayString(language: .current)
        }

        public func displayString(language: AppLanguage) -> String {
            let months = FamilyDate.displayMonthsShort(language: language)
            if let d = day, let m = month, let y = year {
                guard months.indices.contains(m - 1) else { return formatted }
                let monthName = months[m - 1]
                return "\(d) \(monthName) \(y)"
            } else if let m = month, let y = year {
                guard months.indices.contains(m - 1) else { return formatted }
                let monthName = months[m - 1]
                return "\(monthName) \(y)"
            } else if let y = year {
                return "\(y)"
            }
            return ""
        }

        /// Convert to Swift Date (for precise age calculation)
        public var date: Date? {
            guard let y = year else { return nil }
            var dc = DateComponents()
            dc.year = y
            dc.month = month ?? 1
            dc.day = day ?? 1
            return Calendar(identifier: .gregorian).date(from: dc)
        }
    }

    private static let russianMonthsShort = [
        "янв", "фев", "мар", "апр", "май", "июн",
        "июл", "авг", "сен", "окт", "ноя", "дек"
    ]

    private static let gedcomMonths = [
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
        "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
    ]

    private static let englishMonthsShort = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun",
        "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
    ]

    private static func displayMonthsShort(language: AppLanguage) -> [String] {
        language == .english ? englishMonthsShort : russianMonthsShort
    }

    // MARK: - Parse

    /// Parse any date string into components. Supports:
    /// - "DD.MM.YYYY" (standard)
    /// - "DD/MM/YYYY"
    /// - "DD-MM-YYYY"
    /// - "YYYY"
    /// - "MM.YYYY"
    /// - "D MMM YYYY" (GEDCOM/Russian: "5 мар 1978", "5 MAR 1978")
    /// - "DD MMMM YYYY" (full month name)
    public static func parse(_ string: String?) -> Components {
        guard let str = string?.trimmingCharacters(in: .whitespaces), !str.isEmpty else {
            return Components()
        }

        if let exact = parseExact(str) { return exact }

        // Imported free-form dates historically yielded a usable year even when
        // the rest of the phrase was not understood. Keep that compatibility in
        // the forgiving parser; editors use parseExact so invalid dates stay invalid.
        if let range = str.range(of: #"\b\d{4}\b"#, options: .regularExpression),
           let y = Int(str[range]) {
            return Components(day: nil, month: nil, year: y)
        }

        return Components()
    }

    /// Parses only supported date forms, without extracting a year from otherwise
    /// invalid text. This is the validator used by editable genealogy fields.
    public static func parseExact(_ string: String?) -> Components? {
        guard let str = string?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty else {
            return nil
        }

        // ISO 8601 calendar date. Check this before the day-first hyphen form.
        let isoPattern = #"^(\d{4})-(\d{1,2})-(\d{1,2})$"#
        if str.range(of: isoPattern, options: .regularExpression) != nil {
            let parts = str.split(separator: "-")
            if parts.count == 3,
               let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
               isValid(day: d, month: m, year: y) {
                return Components(day: d, month: m, year: y)
            }
            return nil
        }

        // Try DD.MM.YYYY or DD/MM/YYYY or DD-MM-YYYY
        let separatorPattern = #"^(\d{1,2})[./\-](\d{1,2})[./\-](\d{4})$"#
        if let match = str.range(of: separatorPattern, options: .regularExpression) {
            let parts = str[match].components(separatedBy: CharacterSet(charactersIn: "./-"))
            if parts.count == 3, let d = Int(parts[0]), let m = Int(parts[1]), let y = Int(parts[2]) {
                if isValid(day: d, month: m, year: y) {
                    return Components(day: d, month: m, year: y)
                }
            }
            return nil
        }

        // Try MM.YYYY or MM/YYYY
        let monthYearPattern = #"^(\d{1,2})[./\-](\d{4})$"#
        if let match = str.range(of: monthYearPattern, options: .regularExpression) {
            let parts = str[match].components(separatedBy: CharacterSet(charactersIn: "./-"))
            if parts.count == 2, let m = Int(parts[0]), let y = Int(parts[1]) {
                if m >= 1 && m <= 12 && y >= 1 && y <= 9999 {
                    return Components(day: nil, month: m, year: y)
                }
            }
            return nil
        }

        // Try YYYY.
        let yearOnly = #"^\d{4}$"#
        if str.range(of: yearOnly, options: .regularExpression) != nil, let y = Int(str) {
            if y >= 1 && y <= 9999 {
                return Components(day: nil, month: nil, year: y)
            }
            return nil
        }

        // Try "D MMM YYYY" or "DD MMMM YYYY" (with month name in Russian, English or GEDCOM)
        let wordParts = str.lowercased().components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if wordParts.count >= 2 {
            // "D MONTH YYYY" or "MONTH YYYY"
            if wordParts.count == 3, let d = Int(wordParts[0]), let y = Int(wordParts[2]) {
                if let m = monthNumber(wordParts[1]) {
                    if isValid(day: d, month: m, year: y) {
                        return Components(day: d, month: m, year: y)
                    }
                    return nil
                }
            }
            // "MONTH YYYY"
            if wordParts.count == 2, let y = Int(wordParts[1]) {
                if let m = monthNumber(wordParts[0]) {
                    return Components(day: nil, month: m, year: y)
                }
            }
        }
        return nil
    }

    /// Normalize a date string to the standard format (DD.MM.YYYY)
    /// Returns the original if it cannot be parsed
    public static func normalize(_ string: String?) -> String {
        guard let str = string, !str.isEmpty else { return "" }
        guard let components = parseExact(str) else { return str }
        let result = components.formatted
        return result.isEmpty ? str : result
    }

    // MARK: - Age Calculation

    /// Calculate age with day-level precision
    /// Returns (years, isApproximate) where isApproximate means only year was available
    public static func calculateAge(birth: String?, death: String?) -> (years: Int, approximate: Bool)? {
        let birthComp = parse(birth)
        guard let birthYear = birthComp.year else { return nil }

        let endComp: Components
        if let death {
            endComp = parse(death)
        } else {
            // Living person — use today
            let now = Date()
            let cal = Calendar(identifier: .gregorian)
            endComp = Components(
                day: cal.component(.day, from: now),
                month: cal.component(.month, from: now),
                year: cal.component(.year, from: now)
            )
        }

        guard let endYear = endComp.year else { return nil }

        // If we have full dates, use Calendar for precise calculation
        if birthComp.isComplete && endComp.isComplete,
           let birthDate = birthComp.date, let endDate = endComp.date {
            let ageComponents = Calendar(identifier: .gregorian)
                .dateComponents([.year], from: birthDate, to: endDate)
            if let years = ageComponents.year, years >= 0 && years < 200 {
                return (years, false)
            }
        }

        // Fallback: year-only calculation (approximate)
        var age = endYear - birthYear

        // Adjust if we have partial month info
        if let bm = birthComp.month, let em = endComp.month {
            if em < bm || (em == bm && (endComp.day ?? 31) < (birthComp.day ?? 1)) {
                age -= 1
            }
        }

        guard age >= 0 && age < 200 else { return nil }
        return (age, !birthComp.isComplete || !endComp.isComplete)
    }

    // MARK: - GEDCOM Format

    /// Convert to GEDCOM date format: "5 MAR 1978"
    public static func toGEDCOM(_ string: String?) -> String {
        let comp = parse(string)
        let monthName: (Int) -> String? = { m in (1 ... 12).contains(m) ? gedcomMonths[m - 1] : nil }
        if let d = comp.day, let m = comp.month, let y = comp.year, let mon = monthName(m) {
            return "\(d) \(mon) \(y)"
        } else if let m = comp.month, let y = comp.year, let mon = monthName(m) {
            return "\(mon) \(y)"
        } else if let y = comp.year {
            return "\(y)"
        }
        return string ?? ""
    }

    // MARK: - Private

    private static func monthNumber(_ name: String) -> Int? {
        let lower = name.lowercased().trimmingCharacters(in: .punctuationCharacters)

        // Russian short (also matches full names: "январь".hasPrefix("янв"))
        if let idx = russianMonthsShort.firstIndex(where: { lower.hasPrefix($0) }) {
            return idx + 1
        }
        // English/GEDCOM
        if let idx = englishMonthsShort.firstIndex(where: { lower.hasPrefix($0.lowercased()) }) {
            return idx + 1
        }

        return nil
    }

    private static func isValid(day: Int, month: Int, year: Int) -> Bool {
        // `isValidDate` rejects impossible days for the month (e.g. 31 Feb) and gets
        // leap years right, so the calendar owns the rule rather than a local table.
        guard year >= 1, year <= 9999 else { return false }
        return DateComponents(
            calendar: Calendar(identifier: .gregorian),
            year: year,
            month: month,
            day: day
        ).isValidDate
    }
}
