import Foundation

struct UserSettings: Codable, Equatable {
    var birthYear: Int
    var menarcheAge: Int
    var cycleLength: Int
    var periodLength: Int

    static let menarcheAgeRange = 8...18
    static let cycleLengthRange = 20...45
    static let periodLengthRange = 1...10

    static func birthYearRange(currentYear: Int = UserSettings.currentYear) -> ClosedRange<Int> {
        (currentYear - 80)...(currentYear - menarcheAgeRange.lowerBound)
    }

    static var currentYear: Int { Calendar.current.component(.year, from: .now) }

    static let `default` = UserSettings(birthYear: currentYear - 25, menarcheAge: 13, cycleLength: 28, periodLength: 5)

    func isValid(currentYear: Int = UserSettings.currentYear) -> Bool {
        Self.birthYearRange(currentYear: currentYear).contains(birthYear)
            && Self.menarcheAgeRange.contains(menarcheAge)
            && Self.cycleLengthRange.contains(cycleLength)
            && Self.periodLengthRange.contains(periodLength)
            && birthYear + menarcheAge <= currentYear
    }
}
