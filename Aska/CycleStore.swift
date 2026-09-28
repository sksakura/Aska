import Foundation
import SwiftData

enum CycleError: LocalizedError, Equatable {
    case dateInFuture
    case noStartBefore
    case nothingToUndo
    case noStopOnDay
    case noStartOnDay
    case dayNotMarked

    var errorDescription: String? {
        switch self {
        case .dateInFuture: "Дата не может быть в будущем."
        case .noStartBefore: "До этой даты нет отметки о начале периода."
        case .nothingToUndo: "Отменять нечего."
        case .noStopOnDay: "В этот день нет отметки об окончании."
        case .noStartOnDay: "В этот день нет отметки о начале."
        case .dayNotMarked: "Этот день не отмечен как день менструации."
        }
    }
}

/// The app's cycle "API" on top of SwiftData. Only events are stored;
/// periods are derived with `Period.derive` whenever they are needed.
@MainActor
struct CycleStore {
    let context: ModelContext
    var now: () -> Date = { Date.now }
    var calendar: Calendar = .current

    func events() throws -> [CycleEvent] {
        try context.fetch(FetchDescriptor<CycleEvent>(sortBy: [SortDescriptor(\.date)]))
    }

    func periods() throws -> [Period] {
        let all = try events()
        return Period.derive(from: all.map { (kind: $0.kind, date: $0.date) })
    }

    /// Periods overlapping the calendar month that contains `date`: recorded ones (fact)
    /// and predicted ones (forecast); see `CalendarPeriods.forMonth` for the forecast rules.
    func periods(inMonthOf date: Date, settings: UserSettings) throws -> [CalendarPeriod] {
        let recorded = try periods()
        return CalendarPeriods.forMonth(containing: date, periods: recorded,
                                        cycleLength: settings.cycleLength,
                                        periodLength: settings.periodLength,
                                        today: now(), calendar: calendar)
    }

    /// Data for the main screen: cycle and period lengths, today's day of the cycle and percentages.
    func summary(settings: UserSettings) throws -> CycleSummary {
        let recorded = try periods()
        return CycleSummary.make(periods: recorded, cycleLength: settings.cycleLength,
                                 periodLength: settings.periodLength, today: now(), calendar: calendar)
    }

    /// Turns a calendar day picked in the UI ("today", "yesterday", a date picker) into an event time.
    /// Today means the current moment; for a past day a start is its first moment
    /// and a stop is its last, so that day is fully inside the period.
    static func eventDate(for kind: EventKind, onDay day: Date, now: Date,
                          calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) {
            return now
        }
        let dayStart = calendar.startOfDay(for: day)
        switch kind {
        case .start:
            return dayStart
        case .stop:
            let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
            return nextDay.addingTimeInterval(-1)
        }
    }

    @discardableResult
    func startCycle(at date: Date) throws -> CycleEvent {
        guard date <= now() else { throw CycleError.dateInFuture }
        return try insert(.start, at: date)
    }

    @discardableResult
    func stopCycle(at date: Date) throws -> CycleEvent {
        guard date <= now() else { throw CycleError.dateInFuture }
        guard try events().contains(where: { $0.kind == .start && $0.date <= date }) else {
            throw CycleError.noStartBefore
        }
        return try insert(.stop, at: date)
    }

    /// Removes the most recently entered change, whatever its date: a single event from the
    /// start/stop buttons, or all events added together by one calendar edit.
    /// Undoing a stop makes the period ongoing again; undoing a start removes it.
    /// Returns the kind of the (last) removed event.
    @discardableResult
    func undoLast() throws -> EventKind {
        var descriptor = FetchDescriptor<CycleEvent>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let last = try context.fetch(descriptor).first else { throw CycleError.nothingToUndo }
        let stamp = last.createdAt
        let batch = try context.fetch(FetchDescriptor<CycleEvent>(predicate: #Predicate<CycleEvent> { $0.createdAt == stamp }))
        let kind = last.kind
        for event in batch {
            context.delete(event)
        }
        try context.save()
        return kind
    }

    // MARK: - Calendar edits (single days)

    /// Marks one calendar day as a period day (the calendar's "+").
    /// A day right after a recorded period extends it, a day right before moves its start,
    /// a day between two periods joins them, any other day becomes a one-day period.
    /// Already marked days are left as they are.
    func markDay(_ day: Date) throws {
        let target = calendar.startOfDay(for: day)
        guard target <= calendar.startOfDay(for: now()) else { throw CycleError.dateInFuture }
        let spans = try factSpans()
        guard !spans.contains(where: { $0.days.contains(target) }) else { return }
        let previous = spans.first { $0.days.upperBound == addingDays(-1, to: target) }
        let next = spans.first { $0.days.lowerBound == addingDays(1, to: target) }
        let stamp = Date.now

        switch (previous, next) {
        case let (previous?, next?):
            // Filling the gap joins the periods: drop the first one's stops and the second one's starts.
            try removeEvents(.stop, inDays: previous.days)
            try removeEvents(.start, inDays: next.days)
        case (_?, nil):
            insert(.stop, at: endOfDay(target), stamp: stamp)
        case (nil, _?):
            insert(.start, at: target, stamp: stamp)
        case (nil, nil):
            insert(.start, at: target, stamp: stamp)
            insert(.stop, at: endOfDay(target), stamp: stamp)
        }
        try context.save()
    }

    /// Removes one calendar day from a recorded period (the calendar's "×").
    /// Removing the first or last day shortens the period, a day in the middle splits it in two,
    /// the only day of a one-day period removes the period.
    func unmarkDay(_ day: Date) throws {
        let target = calendar.startOfDay(for: day)
        guard let span = try factSpans().first(where: { $0.days.contains(target) }) else {
            throw CycleError.dayNotMarked
        }
        let stamp = Date.now
        // Marks on the day itself go (including shorter variants of the same period).
        try removeEvents(nil, inDays: target...target)
        if target > span.days.lowerBound {
            insert(.stop, at: endOfDay(addingDays(-1, to: target)), stamp: stamp)
        }
        if target < span.days.upperBound {
            insert(.start, at: addingDays(1, to: target), stamp: stamp)
        }
        try context.save()
    }

    /// Recorded periods as ranges of day starts; an ongoing period runs until today.
    private func factSpans() throws -> [(days: ClosedRange<Date>, isActive: Bool)] {
        let today = calendar.startOfDay(for: now())
        return try periods().map { period in
            let start = calendar.startOfDay(for: period.start)
            let end = period.end.map { calendar.startOfDay(for: $0) } ?? today
            return (days: start...max(start, end), isActive: period.isActive)
        }
    }

    private func removeEvents(_ kind: EventKind?, inDays days: ClosedRange<Date>) throws {
        for event in try events() where kind == nil || event.kind == kind {
            if days.contains(calendar.startOfDay(for: event.date)) {
                context.delete(event)
            }
        }
    }

    private func addingDays(_ days: Int, to date: Date) -> Date {
        calendar.date(byAdding: .day, value: days, to: date) ?? date
    }

    /// Last moment of the day, or now when the day is today.
    private func endOfDay(_ day: Date) -> Date {
        CycleStore.eventDate(for: .stop, onDay: day, now: now(), calendar: calendar)
    }

    private func insert(_ kind: EventKind, at date: Date, stamp: Date) {
        context.insert(CycleEvent(kind: kind, date: date, createdAt: stamp))
    }

    /// Deletes every stop mark on the given calendar day. Returns how many were deleted.
    @discardableResult
    func deleteStop(onDay day: Date) throws -> Int {
        try delete(.stop, onDay: day, orThrow: .noStopOnDay)
    }

    /// Deletes every start mark on the given calendar day. Returns how many were deleted.
    /// Stops left without a start before them are kept but ignored when periods are derived.
    @discardableResult
    func deleteStart(onDay day: Date) throws -> Int {
        try delete(.start, onDay: day, orThrow: .noStartOnDay)
    }

    private func delete(_ kind: EventKind, onDay day: Date, orThrow error: CycleError) throws -> Int {
        let matching = try events().filter { $0.kind == kind && calendar.isDate($0.date, inSameDayAs: day) }
        guard !matching.isEmpty else { throw error }
        for event in matching {
            context.delete(event)
        }
        try context.save()
        return matching.count
    }

    private func insert(_ kind: EventKind, at date: Date) throws -> CycleEvent {
        let event = CycleEvent(kind: kind, date: date)
        context.insert(event)
        try context.save()
        return event
    }
}
