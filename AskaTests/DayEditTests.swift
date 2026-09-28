import Foundation
import SwiftData
import Testing
@testable import Aska

/// Calendar "+" / "×" on single days. Today is 28 Sep 2026, 12:00 UTC.
@MainActor
struct DayEditTests {
    let container: ModelContainer
    let store: CycleStore
    let calendar: Calendar

    init() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        self.calendar = calendar
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: CycleEvent.self, configurations: config)
        let today = calendar.date(from: DateComponents(year: 2026, month: 9, day: 28, hour: 12))!
        store = CycleStore(context: container.mainContext, now: { today }, calendar: calendar)
    }

    func d(_ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    /// Recorded periods as (first day, last day) pairs; an ongoing one ends with nil.
    func days() throws -> [(Date, Date?)] {
        try store.periods().map { (calendar.startOfDay(for: $0.start), $0.end.map { calendar.startOfDay(for: $0) }) }
    }

    func expectDays(_ expected: [(Date, Date?)], sourceLocation: SourceLocation = #_sourceLocation) throws {
        let actual = try days()
        #expect(actual.count == expected.count, sourceLocation: sourceLocation)
        for (a, e) in zip(actual, expected) {
            #expect(a.0 == e.0 && a.1 == e.1, "\(a) != \(e)", sourceLocation: sourceLocation)
        }
    }

    func closed(_ from: Date, _ to: Date) throws {
        try store.startCycle(at: from)
        try store.stopCycle(at: to)
    }

    // MARK: markDay ("+")

    @Test("MK1: отдельный день становится периодом в один день")
    func markIsolatedDay() throws {
        try store.markDay(d(9, 10, hour: 15))
        try expectDays([(d(9, 10), d(9, 10))])
    }

    @Test("MK2: день сразу после периода продлевает его")
    func markDayAfterPeriod() throws {
        try closed(d(9, 1), d(9, 5, hour: 20))
        try store.markDay(d(9, 6))
        try expectDays([(d(9, 1), d(9, 6))])
    }

    @Test("MK3: день сразу перед периодом переносит начало")
    func markDayBeforePeriod() throws {
        try closed(d(9, 2), d(9, 5, hour: 20))
        try store.markDay(d(9, 1))
        try expectDays([(d(9, 1), d(9, 5))])
    }

    @Test("MK4: день-промежуток между двумя периодами склеивает их")
    func markGapDayJoins() throws {
        try closed(d(9, 1), d(9, 4, hour: 20))
        try closed(d(9, 6), d(9, 9, hour: 20))
        try store.markDay(d(9, 5))
        try expectDays([(d(9, 1), d(9, 9))])
    }

    @Test("MK5: уже отмеченный день — без изменений")
    func markAlreadyMarked() throws {
        try closed(d(9, 1), d(9, 5, hour: 20))
        let before = try store.events().count
        try store.markDay(d(9, 3))
        #expect(try store.events().count == before)
    }

    @Test("MK6: будущий день — ошибка")
    func markFutureDay() throws {
        #expect(throws: CycleError.dateInFuture) { try store.markDay(d(9, 29)) }
        #expect(try store.events().isEmpty)
    }

    @Test("MK7: сегодня после периода, закончившегося вчера, — период продлевается до сегодня")
    func markTodayAfterYesterday() throws {
        try closed(d(9, 24), d(9, 27, hour: 20))
        try store.markDay(d(9, 28))
        try expectDays([(d(9, 24), d(9, 28))])
    }

    @Test("MK8: отмена после «+» убирает всю правку целиком")
    func undoMark() throws {
        try store.markDay(d(9, 10))
        #expect(try store.events().count == 2)
        try store.undoLast()
        #expect(try store.events().isEmpty)
    }

    // MARK: unmarkDay ("×")

    @Test("UM1: день в середине делит период на два")
    func unmarkMiddle() throws {
        try closed(d(9, 1), d(9, 5, hour: 20))
        try store.unmarkDay(d(9, 3))
        try expectDays([(d(9, 1), d(9, 2)), (d(9, 4), d(9, 5))])
    }

    @Test("UM2: первый день — начало сдвигается на день позже")
    func unmarkFirst() throws {
        try closed(d(9, 1), d(9, 5, hour: 20))
        try store.unmarkDay(d(9, 1))
        try expectDays([(d(9, 2), d(9, 5))])
    }

    @Test("UM3: последний день — окончание сдвигается на день раньше")
    func unmarkLast() throws {
        try closed(d(9, 1), d(9, 5, hour: 20))
        try store.unmarkDay(d(9, 5))
        try expectDays([(d(9, 1), d(9, 4))])
    }

    @Test("UM4: единственный день периода — период исчезает")
    func unmarkOnlyDay() throws {
        try store.markDay(d(9, 10))
        try store.unmarkDay(d(9, 10))
        try expectDays([])
    }

    @Test("UM5: сегодня в идущем периоде — период заканчивается вчера")
    func unmarkTodayInActive() throws {
        try store.startCycle(at: d(9, 25))
        try store.unmarkDay(d(9, 28))
        try expectDays([(d(9, 25), d(9, 27))])
    }

    @Test("UM6: день в середине идущего периода — вторая часть остаётся идущей")
    func unmarkMiddleOfActive() throws {
        try store.startCycle(at: d(9, 24))
        try store.unmarkDay(d(9, 26))
        try expectDays([(d(9, 24), d(9, 25)), (d(9, 27), nil)])
    }

    @Test("UM7: неотмеченный день — ошибка")
    func unmarkNotMarked() throws {
        try closed(d(9, 1), d(9, 5, hour: 20))
        #expect(throws: CycleError.dayNotMarked) { try store.unmarkDay(d(9, 7)) }
    }

    @Test("UM8: «короткий вариант» стопа в этот же день тоже убирается")
    func unmarkRemovesShorterVariant() throws {
        try closed(d(9, 1), d(9, 3, hour: 20))
        try store.stopCycle(at: d(9, 6, hour: 20))   // длинный вариант: 1–6
        try store.unmarkDay(d(9, 3))
        try expectDays([(d(9, 1), d(9, 2)), (d(9, 4), d(9, 6))])
    }

    @Test("UM9: после «×» и «+» на том же дне период восстанавливается")
    func unmarkThenMark() throws {
        try closed(d(9, 1), d(9, 5, hour: 20))
        try store.unmarkDay(d(9, 3))
        try store.markDay(d(9, 3))
        try expectDays([(d(9, 1), d(9, 5))])
    }
}
