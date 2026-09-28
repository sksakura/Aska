import Foundation
import SwiftData
import Testing
@testable import Aska

@MainActor
struct CycleStoreTests {
    let container: ModelContainer
    let context: ModelContext
    let store: CycleStore
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let day: TimeInterval = 86_400

    init() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        container = try ModelContainer(for: Cycle.self, configurations: config)
        context = container.mainContext
        let fixedNow = now
        store = CycleStore(context: context, now: { fixedNow })
    }

    func all() throws -> [Cycle] {
        try context.fetch(FetchDescriptor<Cycle>(sortBy: [SortDescriptor(\.start)]))
    }

    // MARK: - startCycle

    @Test("S1: старт на пустой истории создаёт открытый цикл")
    func startOnEmpty() throws {
        try store.startCycle(at: now - day)
        let cycles = try all()
        #expect(cycles.count == 1)
        #expect(cycles[0].start == now - day)
        #expect(cycles[0].end == nil)
    }

    @Test("S2: старт принимает дату и сохраняет её как есть")
    func startStoresGivenDate() throws {
        try store.startCycle(at: now - 3 * day - 123)
        #expect(try all().first?.start == now - 3 * day - 123)
    }

    // MARK: - Выбор дня старта в UI (сегодня / вчера / позавчера / дата)

    var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test("SD1: «сегодня» — текущий момент")
    func pickToday() {
        #expect(CycleStore.startDate(forDay: now, now: now, notBefore: nil, calendar: utc) == now)
    }

    @Test("SD2: «вчера» и «позавчера» — начало того дня")
    func pickPastDays() {
        for offset in [1, 2] {
            let picked = utc.date(byAdding: .day, value: -offset, to: now)!
            let result = CycleStore.startDate(forDay: picked, now: now, notBefore: nil, calendar: utc)
            #expect(result == utc.startOfDay(for: picked))
        }
    }

    @Test("SD3: выбран день окончания прошлого периода — старт сдвигается на момент окончания")
    func pickDayOfPreviousEnd() throws {
        let previousEnd = utc.startOfDay(for: now - 2 * day) + 15 * 3600
        let result = CycleStore.startDate(forDay: previousEnd, now: now, notBefore: previousEnd, calendar: utc)
        #expect(result == previousEnd)
        try store.startCycle(at: now - 10 * day)
        try store.stopCycle(at: previousEnd)
        try store.startCycle(at: result)
        #expect(try all().count == 2)
    }

    @Test("SD4: выбран день раньше окончания прошлого — не сдвигается, API отклоняет")
    func pickDayBeforePreviousEnd() throws {
        let previousEnd = utc.startOfDay(for: now - 2 * day) + 15 * 3600
        try store.startCycle(at: now - 10 * day)
        try store.stopCycle(at: previousEnd)
        let picked = previousEnd - day
        let minimum = try store.earliestStart()
        let result = CycleStore.startDate(forDay: picked, now: now, notBefore: minimum, calendar: utc)
        #expect(result == utc.startOfDay(for: picked))
        #expect(throws: CycleError.startBeforePreviousEnd) { try store.startCycle(at: result) }
    }

    @Test("SD5: выбран завтрашний день — API отклоняет как будущее")
    func pickTomorrow() {
        let result = CycleStore.startDate(forDay: now + day, now: now, notBefore: nil, calendar: utc)
        #expect(throws: CycleError.dateInFuture) { try store.startCycle(at: result) }
    }

    @Test("SD6: earliestStart — нет ограничения на пустой истории и при идущем периоде, иначе конец прошлого")
    func earliestStart() throws {
        #expect(try store.earliestStart() == nil)
        try store.startCycle(at: now - 5 * day)
        #expect(try store.earliestStart() == nil)
        try store.stopCycle(at: now - day)
        #expect(try store.earliestStart() == now - day)
    }

    @Test("S3: старт после закрытого цикла создаёт новый, старый не меняется")
    func startAfterClosed() throws {
        try store.startCycle(at: now - 30 * day)
        try store.stopCycle(at: now - 25 * day)
        try store.startCycle(at: now - day)
        let cycles = try all()
        #expect(cycles.count == 2)
        #expect(cycles[0].end == now - 25 * day)
        #expect(cycles[1].end == nil)
    }

    @Test("S4: граница — старт ровно в момент окончания прошлого допустим")
    func startExactlyAtPreviousEnd() throws {
        try store.startCycle(at: now - 10 * day)
        try store.stopCycle(at: now - 5 * day)
        try store.startCycle(at: now - 5 * day)
        #expect(try all().count == 2)
    }

    @Test("S5: граница — старт на секунду раньше окончания прошлого запрещён")
    func startBeforePreviousEnd() throws {
        try store.startCycle(at: now - 10 * day)
        try store.stopCycle(at: now - 5 * day)
        #expect(throws: CycleError.startBeforePreviousEnd) {
            try store.startCycle(at: now - 5 * day - 1)
        }
        #expect(try all().count == 1)
    }

    @Test("S6: повторный старт при идущем периоде — ошибка, данные не меняются")
    func startWhileActive() throws {
        try store.startCycle(at: now - day)
        #expect(throws: CycleError.alreadyActive) { try store.startCycle(at: now) }
        let cycles = try all()
        #expect(cycles.count == 1)
        #expect(cycles[0].start == now - day)
    }

    @Test("S7: граница — старт ровно «сейчас» допустим, на секунду позже — нет")
    func startFutureBoundary() throws {
        #expect(throws: CycleError.dateInFuture) { try store.startCycle(at: now + 1) }
        #expect(try all().isEmpty)
        try store.startCycle(at: now)
        #expect(try all().count == 1)
    }

    // MARK: - stopCycle

    @Test("P1: стоп закрывает идущий период")
    func stopActive() throws {
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - day)
        #expect(try all().first?.end == now - day)
    }

    @Test("P2: граница — стоп в момент старта допустим")
    func stopAtStart() throws {
        try store.startCycle(at: now - day)
        try store.stopCycle(at: now - day)
        #expect(try all().first?.end == now - day)
    }

    @Test("P3: граница — стоп на секунду раньше старта запрещён")
    func stopBeforeStart() throws {
        try store.startCycle(at: now - day)
        #expect(throws: CycleError.endBeforeStart) { try store.stopCycle(at: now - day - 1) }
        #expect(try all().first?.end == nil)
    }

    @Test("P4: стоп на пустой истории — ошибка")
    func stopOnEmpty() throws {
        #expect(throws: CycleError.noActiveCycle) { try store.stopCycle() }
    }

    @Test("P5: повторный стоп — ошибка, дата окончания не перезаписывается")
    func stopTwice() throws {
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - 2 * day)
        #expect(throws: CycleError.noActiveCycle) { try store.stopCycle(at: now) }
        #expect(try all().first?.end == now - 2 * day)
    }

    @Test("P6: стоп в будущем — ошибка")
    func stopInFuture() throws {
        try store.startCycle(at: now - day)
        #expect(throws: CycleError.dateInFuture) { try store.stopCycle(at: now + 1) }
        #expect(try all().first?.end == nil)
    }

    @Test("P7: стоп меняет только последний цикл")
    func stopTouchesOnlyLatest() throws {
        try store.startCycle(at: now - 40 * day)
        try store.stopCycle(at: now - 35 * day)
        try store.startCycle(at: now - 2 * day)
        try store.stopCycle(at: now)
        let cycles = try all()
        #expect(cycles[0].end == now - 35 * day)
        #expect(cycles[1].end == now)
    }

    // MARK: - undoLast

    @Test("U1: отмена на пустой истории — ошибка")
    func undoOnEmpty() throws {
        #expect(throws: CycleError.nothingToUndo) { try store.undoLast() }
    }

    @Test("U2: отмена после старта удаляет запись")
    func undoStart() throws {
        try store.startCycle(at: now - day)
        #expect(try store.undoLast() == .deleted)
        #expect(try all().isEmpty)
    }

    @Test("U3: отмена после стопа снимает стоп, запись остаётся")
    func undoStop() throws {
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - day)
        #expect(try store.undoLast() == .reopened)
        let cycles = try all()
        #expect(cycles.count == 1)
        #expect(cycles[0].start == now - 5 * day)
        #expect(cycles[0].end == nil)
    }

    @Test("U4: двойная отмена после стопа: сначала снимает стоп, потом удаляет")
    func undoTwiceAfterStop() throws {
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - day)
        #expect(try store.undoLast() == .reopened)
        #expect(try store.undoLast() == .deleted)
        #expect(try all().isEmpty)
        #expect(throws: CycleError.nothingToUndo) { try store.undoLast() }
    }

    @Test("U5: отмена не трогает старые циклы")
    func undoKeepsOlderCycles() throws {
        try store.startCycle(at: now - 40 * day)
        try store.stopCycle(at: now - 35 * day)
        try store.startCycle(at: now - day)
        #expect(try store.undoLast() == .deleted)
        let cycles = try all()
        #expect(cycles.count == 1)
        #expect(cycles[0].end == now - 35 * day)
    }

    @Test("U6: после отмены старта можно снова стартовать")
    func startAgainAfterUndoStart() throws {
        try store.startCycle(at: now - day)
        try store.undoLast()
        try store.startCycle(at: now)
        #expect(try all().map(\.start) == [now])
    }

    @Test("U7: после отмены стопа можно снова остановить другой датой")
    func stopAgainAfterUndoStop() throws {
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - 3 * day)
        try store.undoLast()
        try store.stopCycle(at: now - day)
        #expect(try all().first?.end == now - day)
    }

    @Test("U8: цепочка отмен откатывает историю до пустой")
    func undoChainToEmpty() throws {
        try store.startCycle(at: now - 40 * day)
        try store.stopCycle(at: now - 35 * day)
        try store.startCycle(at: now - 5 * day)
        try store.stopCycle(at: now - day)
        let results = try (0..<4).map { _ in try store.undoLast() }
        #expect(results == [.reopened, .deleted, .reopened, .deleted])
        #expect(try all().isEmpty)
    }

    // MARK: - Порядок и подсчёт дней

    @Test("O1: «последний» цикл определяется по дате начала, а не по порядку вставки")
    func latestIsByStartDate() throws {
        context.insert(Cycle(start: now - 5 * day, end: nil))
        context.insert(Cycle(start: now - 40 * day, end: now - 35 * day))
        try context.save()
        #expect(try store.latest()?.start == now - 5 * day)
        #expect(try store.undoLast() == .deleted)
        #expect(try store.latest()?.start == now - 40 * day)
    }

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
