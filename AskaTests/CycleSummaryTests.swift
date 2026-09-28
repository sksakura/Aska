import Foundation
import SwiftData
import Testing
@testable import Aska

struct CycleSummaryTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func d(_ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func summary(_ periods: [Period], today: Date, cycle: Int = 28, period: Int = 4) -> CycleSummary {
        CycleSummary.make(periods: periods, cycleLength: cycle, periodLength: period, today: today, calendar: calendar)
    }

    @Test("CS1: нет истории — длины и доля периода есть, дня цикла и доли сегодня нет")
    func noHistory() {
        let result = summary([], today: d(9, 14))
        #expect(result.cycleLength == 28)
        #expect(result.periodLength == 4)
        #expect(result.dayOfCycle == nil)
        #expect(result.todayPercent == nil)
        #expect(abs(result.periodPercent - 100.0 * 4 / 28) < 0.0001)
        #expect(!result.isLate)
    }

    @Test("CS2: 14-й день цикла из 28 — 50%")
    func middleOfCycle() {
        let result = summary([Period(start: d(9, 1, hour: 10), end: d(9, 4))], today: d(9, 14, hour: 8))
        #expect(result.dayOfCycle == 14)
        #expect(result.todayPercent == 50)
    }

    @Test("CS3: день начала периода — день 1")
    func firstDay() {
        let result = summary([Period(start: d(9, 1, hour: 23), end: nil)], today: d(9, 1, hour: 23))
        #expect(result.dayOfCycle == 1)
        #expect(abs((result.todayPercent ?? 0) - 100.0 / 28) < 0.0001)
    }

    @Test("CS4: последний день цикла — 100%, ещё не задержка")
    func lastDayOfCycle() {
        let result = summary([Period(start: d(9, 1), end: d(9, 4))], today: d(9, 28))
        #expect(result.dayOfCycle == 28)
        #expect(result.todayPercent == 100)
        #expect(!result.isLate)
    }

    @Test("CS5: задержка — день цикла больше длины, процент не больше 100")
    func late() {
        let result = summary([Period(start: d(9, 1), end: d(9, 4))], today: d(10, 1))
        #expect(result.dayOfCycle == 31)
        #expect(result.todayPercent == 100)
        #expect(result.isLate)
    }

    @Test("CS6: день цикла считается от начала последнего периода, даже идущего")
    func countsFromLatestStart() {
        let periods = [Period(start: d(8, 1), end: d(8, 5)), Period(start: d(9, 1), end: nil)]
        #expect(summary(periods, today: d(9, 3)).dayOfCycle == 3)
    }

    @Test("CS7: переход через полночь — следующий день цикла")
    func acrossMidnight() {
        let result = summary([Period(start: d(9, 1, hour: 23), end: nil)], today: d(9, 2, hour: 0))
        #expect(result.dayOfCycle == 2)
    }

    @Test("CS8: длины берутся из настроек")
    func usesSettings() {
        let result = summary([Period(start: d(9, 1), end: nil)], today: d(9, 15), cycle: 30, period: 6)
        #expect(result.cycleLength == 30)
        #expect(result.periodLength == 6)
        #expect(result.periodPercent == 20)
        #expect(result.todayPercent == 50)
    }
}

@MainActor
struct CycleSummaryStoreTests {
    @Test("CS9: API стора — события + настройки → данные главного экрана")
    func storeSummary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func d(_ month: Int, _ day: Int, _ hour: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
        }
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: CycleEvent.self, configurations: config)
        let today = d(9, 14, 12)
        let store = CycleStore(context: container.mainContext, now: { today }, calendar: calendar)
        let settings = UserSettings(birthDate: birthday(1995), menarcheYear: 2008, cycleLength: 28, periodLength: 4)

        #expect(try store.summary(settings: settings).dayOfCycle == nil)

        try store.startCycle(at: d(9, 1, 9))
        try store.stopCycle(at: d(9, 4, 20))
        let result = try store.summary(settings: settings)
        #expect(result.cycleLength == 28)
        #expect(result.periodLength == 4)
        #expect(result.dayOfCycle == 14)
        #expect(abs(result.periodPercent - 100.0 * 4 / 28) < 0.0001)
        #expect(result.todayPercent == 50)
    }
}
