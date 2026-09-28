import Foundation
import SwiftData

enum CycleError: LocalizedError, Equatable {
    case dateInFuture
    case noStartBefore
    case nothingToUndo
    case noStopOnDay
    case noStartOnDay

    var errorDescription: String? {
        switch self {
        case .dateInFuture: "Дата не может быть в будущем."
        case .noStartBefore: "До этой даты нет отметки о начале периода."
        case .nothingToUndo: "Отменять нечего."
        case .noStopOnDay: "В этот день нет отметки об окончании."
        case .noStartOnDay: "В этот день нет отметки о начале."
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

    /// Removes the most recently entered event, whatever its date.
    /// Undoing a stop makes the period ongoing again; undoing a start removes it.
    @discardableResult
    func undoLast() throws -> EventKind {
        var descriptor = FetchDescriptor<CycleEvent>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let last = try context.fetch(descriptor).first else { throw CycleError.nothingToUndo }
        let kind = last.kind
        context.delete(last)
        try context.save()
        return kind
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
