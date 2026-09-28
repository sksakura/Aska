import Foundation
import SwiftData
import Testing
@testable import Aska

/// Settings in these tests: cycle 28 days, period 5 days, UTC calendar.
struct CalendarPeriodsTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// A day in 2026 at the given hour.
    func d(_ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    func month(_ month: Int, periods: [Period], today: Date) -> [CalendarPeriod] {
        CalendarPeriods.forMonth(containing: d(month, 15), periods: periods, cycleLength: 28,
                                 periodLength: 5, today: today, calendar: calendar)
    }

    func fact(_ start: Date, _ end: Date) -> CalendarPeriod {
        CalendarPeriod(start: start, end: end, startCertainty: .fact, endCertainty: .fact)
    }

    func forecast(_ start: Date, _ end: Date) -> CalendarPeriod {
        CalendarPeriod(start: start, end: end, startCertainty: .forecast, endCertainty: .forecast)
    }

    let closedAugust = [Period(start: d0(8, 1, 10), end: d0(8, 5, 18))]

    @Test("FC1: нет истории — ни фактов, ни прогноза")
    func emptyHistory() {
        #expect(month(9, periods: [], today: d(9, 10)).isEmpty)
    }

    @Test("FC2: закрытый период — факт/факт, даты приведены к началу дня")
    func closedFact() {
        #expect(month(8, periods: closedAugust, today: d(8, 10)) == [fact(d(8, 1), d(8, 5))])
    }

    @Test("FC3: прогноз — начало = последнее окончание + цикл, окончание = + цикл + период")
    func forecastAfterClosed() {
        // 5 авг + 28 = 2 сент; 5 авг + 33 = 7 сент
        #expect(month(9, periods: closedAugust, today: d(8, 10)) == [forecast(d(9, 2), d(9, 7))])
    }

    @Test("FC4: цепочка прогнозов — следующий считается от окончания предыдущего прогноза")
    func forecastChain() {
        // 7 сент + 28 = 5 окт … 10 окт; 10 окт + 28 = 7 нояб … 12 нояб
        #expect(month(10, periods: closedAugust, today: d(8, 10)) == [forecast(d(10, 5), d(10, 10))])
        #expect(month(11, periods: closedAugust, today: d(8, 10)) == [forecast(d(11, 7), d(11, 12))])
    }

    @Test("FC5: в месяце и факт, и прогноз")
    func factAndForecastInOneMonth() {
        let periods = [Period(start: d(8, 1), end: d(8, 3))]
        // 3 авг + 28 = 31 авг … 5 сент
        #expect(month(8, periods: periods, today: d(8, 10)) == [fact(d(8, 1), d(8, 3)), forecast(d(8, 31), d(9, 5))])
    }

    @Test("FC6: идущий период — начало факт, окончание прогноз = начало + период")
    func activePeriod() {
        let periods = [Period(start: d(9, 20, hour: 9), end: nil)]
        let expected = CalendarPeriod(start: d(9, 20), end: d(9, 25), startCertainty: .fact, endCertainty: .forecast)
        #expect(month(9, periods: periods, today: d(9, 22)) == [expected])
    }

    @Test("FC7: идущий период дольше обычного — прогноз окончания не раньше сегодня")
    func overdueActivePeriod() {
        let periods = [Period(start: d(9, 1), end: nil)]
        let result = month(9, periods: periods, today: d(9, 12, hour: 15))
        #expect(result.first == CalendarPeriod(start: d(9, 1), end: d(9, 12), startCertainty: .fact, endCertainty: .forecast))
    }

    @Test("FC8: после идущего периода прогноз считается от прогнозного окончания")
    func forecastAfterActive() {
        let periods = [Period(start: d(9, 20), end: nil)]
        // окончание ≈ 25 сент; 25 сент + 28 = 23 окт … 28 окт
        #expect(month(10, periods: periods, today: d(9, 22)) == [forecast(d(10, 23), d(10, 28))])
    }

    @Test("FC9: период на стыке месяцев попадает в оба месяца")
    func periodAcrossMonths() {
        let periods = [Period(start: d(8, 29), end: d(9, 2))]
        #expect(month(8, periods: periods, today: d(9, 10)).first == fact(d(8, 29), d(9, 2)))
        #expect(month(9, periods: periods, today: d(9, 10)).first == fact(d(8, 29), d(9, 2)))
    }

    @Test("FC10: границы месяца — окончание 1-го числа входит, начало 1-го следующего месяца — нет")
    func monthBoundaries() {
        let endsOnFirst = [Period(start: d(8, 28), end: d(9, 1))]
        #expect(month(9, periods: endsOnFirst, today: d(9, 10)).contains(fact(d(8, 28), d(9, 1))))
        // 3 сент + 28 = 1 окт
        let forecastOnFirst = [Period(start: d(9, 1), end: d(9, 3))]
        #expect(month(9, periods: forecastOnFirst, today: d(9, 10)) == [fact(d(9, 1), d(9, 3))])
        #expect(month(10, periods: forecastOnFirst, today: d(9, 10)) == [forecast(d(10, 1), d(10, 6))])
    }

    @Test("FC11: прогноз строится только от последнего периода, старые факты его не порождают")
    func forecastOnlyFromLatest() {
        let periods = [Period(start: d(8, 1), end: d(8, 5)), Period(start: d(9, 1), end: d(9, 5))]
        // без правила в сентябре был бы прогноз 2–7 сент от августа
        #expect(month(9, periods: periods, today: d(9, 10)) == [fact(d(9, 1), d(9, 5))])
        #expect(month(10, periods: periods, today: d(9, 10)) == [forecast(d(10, 3), d(10, 8))])
    }

    @Test("FC12: прошлый месяц без фактов — пусто, прогноз назад не строится")
    func pastMonthWithoutFacts() {
        #expect(month(6, periods: closedAugust, today: d(8, 10)).isEmpty)
    }

    @Test("FC13: nextForecast — ближайший прогноз")
    func nextForecast() {
        let next = CalendarPeriods.nextForecast(periods: closedAugust, cycleLength: 28, periodLength: 5,
                                                today: d(8, 10), calendar: calendar)
        #expect(next == forecast(d(9, 2), d(9, 7)))
        #expect(CalendarPeriods.nextForecast(periods: [], cycleLength: 28, periodLength: 5,
                                             today: d(8, 10), calendar: calendar) == nil)
    }

    @Test("FC14: длины цикла и периода берутся из настроек")
    func usesSettingsLengths() {
        let result = CalendarPeriods.forMonth(containing: d(9, 15), periods: closedAugust, cycleLength: 30,
                                              periodLength: 7, today: d(8, 10), calendar: calendar)
        // 5 авг + 30 = 4 сент; 5 авг + 37 = 11 сент
        #expect(result == [forecast(d(9, 4), d(9, 11))])
    }
}

/// Helper usable in stored property initialisers (no `self`).
private func d0(_ month: Int, _ day: Int, _ hour: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
}

@MainActor
struct CalendarPeriodsStoreTests {
    @Test("FC15: API стора — события + настройки → периоды месяца с пометками факт/прогноз")
    func storeMonthQuery() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: CycleEvent.self, configurations: config)
        let today = d0(9, 22, 12)
        let store = CycleStore(context: container.mainContext, now: { today }, calendar: calendar)
        let settings = UserSettings(birthYear: 1995, menarcheAge: 13, cycleLength: 28, periodLength: 5)

        try store.startCycle(at: d0(8, 28, 8))
        try store.stopCycle(at: d0(9, 1, 20))
        try store.startCycle(at: d0(9, 20, 9))

        let september = try store.periods(inMonthOf: d0(9, 1, 0), settings: settings)
        #expect(september == [
            CalendarPeriod(start: d0(8, 28, 0), end: d0(9, 1, 0), startCertainty: .fact, endCertainty: .fact),
            CalendarPeriod(start: d0(9, 20, 0), end: d0(9, 25, 0), startCertainty: .fact, endCertainty: .forecast),
        ])
        let october = try store.periods(inMonthOf: d0(10, 10, 0), settings: settings)
        #expect(october.allSatisfy(\.isForecast))
        #expect(october.first?.start == d0(10, 23, 0))
    }
}
