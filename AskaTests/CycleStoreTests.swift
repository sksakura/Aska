import Foundation
import SwiftData
import Testing
@testable import Aska

// MARK: - Сборка периодов из событий (чистая функция)

struct PeriodDerivationTests {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    let day: TimeInterval = 86_400

    func d(_ n: Int) -> Date { t0 + Double(n) * day }

    @Test("PR1: нет событий — нет периодов")
    func empty() {
        #expect(Period.derive(from: []).isEmpty)
    }

    @Test("PR2: только старт — идущий период")
    func onlyStart() {
        #expect(Period.derive(from: [(.start, d(0))]) == [Period(start: d(0), end: nil)])
    }

    @Test("PR3: старт и стоп — закрытый период")
    func startStop() {
        #expect(Period.derive(from: [(.start, d(0)), (.stop, d(4))]) == [Period(start: d(0), end: d(4))])
    }

    @Test("PR4: два цикла подряд — два периода")
    func twoPeriods() {
        let events: [(kind: EventKind, date: Date)] = [(.start, d(0)), (.stop, d(4)), (.start, d(28)), (.stop, d(33))]
        #expect(Period.derive(from: events) == [Period(start: d(0), end: d(4)), Period(start: d(28), end: d(33))])
    }

    @Test("PR5: два старта подряд — длинный перекрывает короткий (берётся ранний)")
    func twoStartsMerge() {
        let events: [(kind: EventKind, date: Date)] = [(.start, d(2)), (.start, d(0)), (.stop, d(5))]
        #expect(Period.derive(from: events) == [Period(start: d(0), end: d(5))])
    }

    @Test("PR6: два стопа подряд — длинный перекрывает короткий (берётся поздний)")
    func twoStopsMerge() {
        let events: [(kind: EventKind, date: Date)] = [(.start, d(0)), (.stop, d(3)), (.stop, d(6))]
        #expect(Period.derive(from: events) == [Period(start: d(0), end: d(6))])
    }

    @Test("PR7: два старта и два стопа — один период по крайним датам")
    func nestedPeriods() {
        let events: [(kind: EventKind, date: Date)] = [(.start, d(0)), (.start, d(1)), (.stop, d(3)), (.stop, d(5))]
        #expect(Period.derive(from: events) == [Period(start: d(0), end: d(5))])
    }

    @Test("PR8: стоп без старта перед ним игнорируется")
    func orphanStop() {
        let events: [(kind: EventKind, date: Date)] = [(.stop, d(0)), (.start, d(2)), (.stop, d(5))]
        #expect(Period.derive(from: events) == [Period(start: d(2), end: d(5))])
    }

    @Test("PR9: старт и стоп в один момент — старт идёт первым, период нулевой длины")
    func sameMoment() {
        let events: [(kind: EventKind, date: Date)] = [(.stop, d(0)), (.start, d(0))]
        #expect(Period.derive(from: events) == [Period(start: d(0), end: d(0))])
    }

    @Test("PR10: порядок входных событий не важен")
    func unsortedInput() {
        let events: [(kind: EventKind, date: Date)] = [(.stop, d(33)), (.start, d(28)), (.stop, d(4)), (.start, d(0))]
        #expect(Period.derive(from: events).count == 2)
        #expect(Period.derive(from: events).last == Period(start: d(28), end: d(33)))
    }
}

// MARK: - API

@MainActor
struct CycleStoreTests {
    let container: ModelContainer
    let context: ModelContext
    let store: CycleStore
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let day: TimeInterval = 86_400

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: CycleEvent.self, configurations: config)
        context = container.mainContext
        let fixedNow = now
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        store = CycleStore(context: context, now: { fixedNow }, calendar: calendar)
    }

    func periods() throws -> [Period] { try store.periods() }

    // MARK: startCycle

    @Test("S1: старт сохраняет событие с переданной датой")
    func startStoresDate() throws {
        try store.startCycle(at: now - 3 * day - 123)
        let events = try store.events()
        #expect(events.count == 1)
        #expect(events[0].kind == .start)
        #expect(events[0].date == now - 3 * day - 123)
        #expect(try periods() == [Period(start: now - 3 * day - 123, end: nil)])
    }

    @Test("S2: граница — старт ровно «сейчас» допустим, на секунду позже — нет")
    func startFutureBoundary() throws {
        #expect(throws: CycleError.dateInFuture) { try store.startCycle(at: now + 1) }
        #expect(try store.events().isEmpty)
        try store.startCycle(at: now)
        #expect(try store.events().count == 1)
    }

    @Test("S3: старт при идущем периоде разрешён — ранний старт удлиняет период")
    func startWhileActiveExtends() throws {
        try store.startCycle(at: now - 2 * day)
        try store.startCycle(at: now - 4 * day)
        #expect(try periods() == [Period(start: now - 4 * day, end: nil)])
    }

    @Test("S4: старт внутри закрытого периода не создаёт новый период")
    func startInsideClosedPeriod() throws {
        try store.startCycle(at: now - 10 * day)
        try store.stopCycle(at: now - 5 * day)
        try store.startCycle(at: now - 8 * day)
        #expect(try periods() == [Period(start: now - 10 * day, end: now - 5 * day)])
    }

    @Test("S5: старт после закрытого периода — новый период")
    func startAfterClosed() throws {
        try store.startCycle(at: now - 30 * day)
        try store.stopCycle(at: now - 25 * day)
        try store.startCycle(at: now - day)
        #expect(try periods() == [Period(start: now - 30 * day, end: now - 25 * day), Period(start: now - day, end: nil)])
    }

    // MARK: stopCycle

    @Test("P1: стоп закрывает идущий период")
    func stopActive() throws {
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - day)
        #expect(try periods() == [Period(start: now - 5 * day, end: now - day)])
    }

    @Test("P2: граница — стоп в момент старта допустим")
    func stopAtStart() throws {
        try store.startCycle(at: now - day)
        try store.stopCycle(at: now - day)
        #expect(try periods() == [Period(start: now - day, end: now - day)])
    }

    @Test("P3: граница — стоп на секунду раньше единственного старта запрещён")
    func stopBeforeStart() throws {
        try store.startCycle(at: now - day)
        #expect(throws: CycleError.noStartBefore) { try store.stopCycle(at: now - day - 1) }
        #expect(try store.events().count == 1)
    }

    @Test("P4: стоп на пустой истории — ошибка")
    func stopOnEmpty() throws {
        #expect(throws: CycleError.noStartBefore) { try store.stopCycle(at: now) }
    }

    @Test("P5: стоп в будущем — ошибка")
    func stopInFuture() throws {
        try store.startCycle(at: now - day)
        #expect(throws: CycleError.dateInFuture) { try store.stopCycle(at: now + 1) }
        #expect(try periods().last?.isActive == true)
    }

    @Test("P6: второй, более поздний стоп удлиняет период")
    func laterStopExtends() throws {
        try store.startCycle(at: now - 10 * day)
        try store.stopCycle(at: now - 7 * day)
        try store.stopCycle(at: now - 4 * day)
        #expect(try periods() == [Period(start: now - 10 * day, end: now - 4 * day)])
    }

    @Test("P7: второй, более ранний стоп не укорачивает период")
    func earlierStopKeepsLonger() throws {
        try store.startCycle(at: now - 10 * day)
        try store.stopCycle(at: now - 4 * day)
        try store.stopCycle(at: now - 7 * day)
        #expect(try periods() == [Period(start: now - 10 * day, end: now - 4 * day)])
    }

    // MARK: undoLast

    @Test("U1: отмена на пустой истории — ошибка")
    func undoOnEmpty() throws {
        #expect(throws: CycleError.nothingToUndo) { try store.undoLast() }
    }

    @Test("U2: отмена после старта удаляет старт")
    func undoStart() throws {
        try store.startCycle(at: now - day)
        #expect(try store.undoLast() == .start)
        #expect(try periods().isEmpty)
    }

    @Test("U3: отмена после стопа снимает стоп — период снова идёт")
    func undoStop() throws {
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - day)
        #expect(try store.undoLast() == .stop)
        #expect(try periods() == [Period(start: now - 5 * day, end: nil)])
    }

    @Test("U4: отменяется последнее введённое событие, а не самое позднее по дате")
    func undoByEntryOrder() throws {
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - day)
        try store.startCycle(at: now - 8 * day)   // введено последним, но раньше по дате
        #expect(try store.undoLast() == .start)
        #expect(try periods() == [Period(start: now - 5 * day, end: now - day)])
    }

    @Test("U5: цепочка отмен откатывает историю до пустой")
    func undoChainToEmpty() throws {
        try store.startCycle(at: now - 40 * day)
        try store.stopCycle(at: now - 35 * day)
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - day)
        let results = try (0..<4).map { _ in try store.undoLast() }
        #expect(results == [.stop, .start, .stop, .start])
        #expect(try store.events().isEmpty)
    }

    // MARK: deleteStop

    @Test("DS1: удаление лишнего длинного стопа снова показывает короткий период")
    func deleteLongStopRestoresShort() throws {
        try store.startCycle(at: now - 10 * day)
        try store.stopCycle(at: now - 7 * day)
        try store.stopCycle(at: now - 4 * day)
        #expect(try store.deleteStop(onDay: now - 4 * day) == 1)
        #expect(try periods() == [Period(start: now - 10 * day, end: now - 7 * day)])
    }

    @Test("DS2: удаление единственного стопа — период снова идёт")
    func deleteOnlyStop() throws {
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - day)
        try store.deleteStop(onDay: now - day)
        #expect(try periods() == [Period(start: now - 5 * day, end: nil)])
    }

    @Test("DS3: в выбранный день нет стопа — ошибка, данные не меняются")
    func deleteStopMissingDay() throws {
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - day)
        #expect(throws: CycleError.noStopOnDay) { try store.deleteStop(onDay: now - 2 * day) }
        #expect(try store.events().count == 2)
    }

    @Test("DS4: удаляются только стопы, старт в тот же день остаётся")
    func deleteStopKeepsStartSameDay() throws {
        try store.startCycle(at: now - day)
        try store.stopCycle(at: now - day + 3600)
        try store.deleteStop(onDay: now - day)
        let events = try store.events()
        #expect(events.map(\.kind) == [.start])
    }

    @Test("DS5: день сравнивается по календарю — подходит любое время внутри дня")
    func deleteStopByCalendarDay() throws {
        let dayStart = store.calendar.startOfDay(for: now - 3 * day)
        try store.startCycle(at: dayStart - 5 * day)
        try store.stopCycle(at: dayStart + 23 * 3600 + 59 * 60)
        #expect(try store.deleteStop(onDay: dayStart + 60) == 1)
    }

    @Test("DS6: несколько стопов в один день удаляются все")
    func deleteAllStopsOfDay() throws {
        let dayStart = store.calendar.startOfDay(for: now - 3 * day)
        try store.startCycle(at: dayStart - 5 * day)
        try store.stopCycle(at: dayStart + 3600)
        try store.stopCycle(at: dayStart + 7200)
        #expect(try store.deleteStop(onDay: dayStart) == 2)
        #expect(try periods().last?.isActive == true)
    }

    @Test("DS7: удаление стопа между двумя периодами объединяет их в один")
    func deleteStopBetweenPeriods() throws {
        try store.startCycle(at: now - 40 * day)
        try store.stopCycle(at: now - 35 * day)
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - day)
        try store.deleteStop(onDay: now - 35 * day)
        #expect(try periods() == [Period(start: now - 40 * day, end: now - day)])
    }

    // MARK: - Дата события из выбранного дня (сегодня / вчера / позавчера / календарь)

    @Test("M1: «сегодня» — текущий момент для старта и стопа")
    func eventDateToday() {
        #expect(CycleStore.eventDate(for: .start, onDay: now, now: now, calendar: store.calendar) == now)
        #expect(CycleStore.eventDate(for: .stop, onDay: now, now: now, calendar: store.calendar) == now)
    }

    @Test("M2: прошлый день — старт в 00:00, стоп в 23:59:59")
    func eventDatePastDay() {
        let calendar = store.calendar
        for offset in [1, 2, 10] {
            let picked = calendar.date(byAdding: .day, value: -offset, to: now)!
            let dayStart = calendar.startOfDay(for: picked)
            #expect(CycleStore.eventDate(for: .start, onDay: picked, now: now, calendar: calendar) == dayStart)
            #expect(CycleStore.eventDate(for: .stop, onDay: picked, now: now, calendar: calendar)
                    == dayStart + day - 1)
        }
    }

    @Test("M3: старт и стоп в один прошлый день — период покрывает весь день")
    func eventDateSameDay() throws {
        let picked = now - 3 * day
        try store.startCycle(at: CycleStore.eventDate(for: .start, onDay: picked, now: now, calendar: store.calendar))
        try store.stopCycle(at: CycleStore.eventDate(for: .stop, onDay: picked, now: now, calendar: store.calendar))
        let period = try #require(try periods().first)
        #expect(store.calendar.dayNumber(from: period.start, to: period.end!) == 1)
    }

    @Test("M4: завтрашний день — API отклоняет как будущее")
    func eventDateTomorrow() {
        let date = CycleStore.eventDate(for: .start, onDay: now + day, now: now, calendar: store.calendar)
        #expect(throws: CycleError.dateInFuture) { try store.startCycle(at: date) }
    }

    // MARK: - Подсчёт дней

    @Test("D1: день начала — день 1, переход через полночь — день 2")
    func dayNumberAcrossMidnight() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1, hour: 23, minute: 59))!
        #expect(calendar.dayNumber(from: start, to: start) == 1)
        #expect(calendar.dayNumber(from: start, to: start + 120) == 2)
    }

    @Test("D2: переход на летнее время не сбивает счёт дней")
    func dayNumberAcrossDST() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 3, day: 28, hour: 12))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 3, day: 30, hour: 12))!
        #expect(calendar.dayNumber(from: start, to: end) == 3)
    }
}
