import Foundation

/// Standardized date handling for family tree dates.
/// Internal format: "DD.MM.YYYY" (e.g. "05.03.1978")
/// Also supports partial dates: "MM.YYYY" or "YYYY"
/// Handles GEDCOM format on import: "5 MAR 1978", "MAR 1978", "1978"
enum FamilyDate {
    
    /// Standard display format
    static let displayFormat = "dd.MM.yyyy"
    
    // MARK: - Parse any date string into components
    
    struct Components {
        var day: Int?
        var month: Int?
        var year: Int?
        
        var isComplete: Bool { day != nil && month != nil && year != nil }
        
        /// Format as standardized string
        var formatted: String {
            if let d = day, let m = month, let y = year {
                return String(format: "%02d.%02d.%04d", d, m, y)
            } else if let m = month, let y = year {
                return String(format: "%02d.%04d", m, y)
            } else if let y = year {
                return "\(y)"
            }
            return ""
        }
        
        /// Formatted for user display in Russian
        var displayString: String {
            if let d = day, let m = month, let y = year {
                let monthName = FamilyDate.russianMonthsShort[m - 1]
                return "\(d) \(monthName) \(y)"
            } else if let m = month, let y = year {
                let monthName = FamilyDate.russianMonthsShort[m - 1]
                return "\(monthName) \(y)"
            } else if let y = year {
                return "\(y)"
            }
            return ""
        }
        
        /// Convert to Swift Date (for precise age calculation)
        var date: Date? {
            guard let y = year else { return nil }
            var dc = DateComponents()
            dc.year = y
            dc.month = month ?? 1
            dc.day = day ?? 1
            return Calendar.current.date(from: dc)
        }
    }
    
    private static let russianMonthsShort = [
        "янв", "фев", "мар", "апр", "май", "июн",
        "июл", "авг", "сен", "окт", "ноя", "дек"
    ]
    
    private static let russianMonthsFull = [
        "январь", "февраль", "март", "апрель", "май", "июнь",
        "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"
    ]
    
    private static let gedcomMonths = [
        "JAN", "FEB", "MAR", "APR", "MAY", "JUN",
        "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"
    ]
    
    private static let englishMonthsShort = [
        "jan", "feb", "mar", "apr", "may", "jun",
        "jul", "aug", "sep", "oct", "nov", "dec"
    ]
    
    // MARK: - Parse
    
    /// Parse any date string into components. Supports:
    /// - "DD.MM.YYYY" (standard)
    /// - "DD/MM/YYYY"
    /// - "DD-MM-YYYY"
    /// - "YYYY"
    /// - "MM.YYYY"
    /// - "D MMM YYYY" (GEDCOM/Russian: "5 мар 1978", "5 MAR 1978")
    /// - "DD MMMM YYYY" (full month name)
    static func parse(_ string: String?) -> Components {
        guard let str = string?.trimmingCharacters(in: .whitespaces), !str.isEmpty else {
            return Components()
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
        }
        
        // Try just YYYY
        let yearOnly = #"^\d{4}$"#
        if str.range(of: yearOnly, options: .regularExpression) != nil, let y = Int(str) {
            if y >= 1 && y <= 9999 {
                return Components(day: nil, month: nil, year: y)
            }
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
                }
            }
            // "MONTH YYYY"
            if wordParts.count == 2, let y = Int(wordParts[1]) {
                if let m = monthNumber(wordParts[0]) {
                    return Components(day: nil, month: m, year: y)
                }
            }
        }
        
        // Last resort: extract year from string
        if let range = str.range(of: #"\b\d{4}\b"#, options: .regularExpression) {
            if let y = Int(str[range]) {
                return Components(day: nil, month: nil, year: y)
            }
        }
        
        return Components()
    }
    
    /// Normalize a date string to the standard format (DD.MM.YYYY)
    /// Returns the original if it cannot be parsed
    static func normalize(_ string: String?) -> String {
        guard let str = string, !str.isEmpty else { return "" }
        let components = parse(str)
        let result = components.formatted
        return result.isEmpty ? str : result
    }
    
    // MARK: - Age Calculation
    
    /// Calculate age with day-level precision
    /// Returns (years, isApproximate) where isApproximate means only year was available
    static func calculateAge(birth: String?, death: String?) -> (years: Int, approximate: Bool)? {
        let birthComp = parse(birth)
        guard let birthYear = birthComp.year else { return nil }
        
        let endComp: Components
        if let death = death {
            endComp = parse(death)
        } else {
            // Living person — use today
            let now = Date()
            let cal = Calendar.current
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
            let ageComponents = Calendar.current.dateComponents([.year], from: birthDate, to: endDate)
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
    static func toGEDCOM(_ string: String?) -> String {
        let comp = parse(string)
        if let d = comp.day, let m = comp.month, let y = comp.year {
            return "\(d) \(gedcomMonths[m - 1]) \(y)"
        } else if let m = comp.month, let y = comp.year {
            return "\(gedcomMonths[m - 1]) \(y)"
        } else if let y = comp.year {
            return "\(y)"
        }
        return string ?? ""
    }
    
    // MARK: - Private
    
    private static func monthNumber(_ name: String) -> Int? {
        let lower = name.lowercased().trimmingCharacters(in: .punctuationCharacters)
        
        // Russian short
        if let idx = russianMonthsShort.firstIndex(where: { lower.hasPrefix($0) }) {
            return idx + 1
        }
        // Russian full
        if let idx = russianMonthsFull.firstIndex(where: { lower.hasPrefix($0.prefix(3)) }) {
            return idx + 1
        }
        // English/GEDCOM
        if let idx = englishMonthsShort.firstIndex(where: { lower.hasPrefix($0) }) {
            return idx + 1
        }
        
        return nil
    }
    
    private static func isValid(day: Int, month: Int, year: Int) -> Bool {
        guard year >= 1 && year <= 9999 else { return false }
        guard month >= 1 && month <= 12 else { return false }
        guard day >= 1 && day <= 31 else { return false }
        return true
    }
}
