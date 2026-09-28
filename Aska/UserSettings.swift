import Foundation

struct UserSettings: Codable, Equatable {
    var birthDate: Date
    /// Year of the first period.
    var menarcheYear: Int
    var cycleLength: Int
    var periodLength: Int
    var remindersOn: Bool = true

    static let cycleLengthRange = 15...45
    static let periodLengthRange = 1...12
    /// Age of the first period, in years.
    static let menarcheAgeRange = 8...18
    /// Allowed age of the user, in years.
    static let ageRange = 8...80

    static var currentYear: Int { Calendar.current.component(.year, from: .now) }

    static func birthYearRange(currentYear: Int = UserSettings.currentYear) -> ClosedRange<Int> {
        (currentYear - ageRange.upperBound)...(currentYear - ageRange.lowerBound)
    }

    /// Years the first period may fall in for someone born in `birthYear`.
    static func menarcheYearRange(birthYear: Int, currentYear: Int = UserSettings.currentYear) -> ClosedRange<Int> {
        let lower = birthYear + menarcheAgeRange.lowerBound
        let upper = max(lower, min(birthYear + menarcheAgeRange.upperBound, currentYear))
        return lower...upper
    }

    static var `default`: UserSettings {
        let birthYear = currentYear - 25
        let birthDate = Calendar.current.date(from: DateComponents(year: birthYear, month: 1, day: 1)) ?? .now
        return UserSettings(birthDate: birthDate, menarcheYear: birthYear + 13, cycleLength: 28, periodLength: 5)
    }

    func birthYear(calendar: Calendar = .current) -> Int {
        calendar.component(.year, from: birthDate)
    }

    func isValid(currentYear: Int = UserSettings.currentYear, calendar: Calendar = .current) -> Bool {
        let birthYear = birthYear(calendar: calendar)
        return Self.birthYearRange(currentYear: currentYear).contains(birthYear)
            && Self.cycleLengthRange.contains(cycleLength)
            && Self.periodLengthRange.contains(periodLength)
            && menarcheYear >= birthYear + Self.menarcheAgeRange.lowerBound
            && menarcheYear <= birthYear + Self.menarcheAgeRange.upperBound
            && menarcheYear <= currentYear
    }
}
