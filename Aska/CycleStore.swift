import Foundation
import SwiftData

enum CycleError: LocalizedError, Equatable {
    case alreadyActive
    case noActiveCycle
    case nothingToUndo
    case dateInFuture
    case startBeforePreviousEnd
    case endBeforeStart

    var errorDescription: String? {
        switch self {
        case .alreadyActive: "Период уже идёт — сначала отметьте его окончание."
        case .noActiveCycle: "Сейчас нет начатого периода."
        case .nothingToUndo: "Отменять нечего."
        case .dateInFuture: "Дата не может быть в будущем."
        case .startBeforePreviousEnd: "Начало не может быть раньше окончания прошлого периода."
        case .endBeforeStart: "Окончание не может быть раньше начала."
        }
    }
}

enum UndoResult: Equatable {
    /// The last action was a stop: the end was removed and the period is ongoing again.
    case reopened
    /// The last action was a start: the whole record was deleted.
    case deleted
}

/// The app's cycle "API": start, stop and undo on top of SwiftData.
/// The latest cycle (by start date) defines the current state, so the last action
/// is always derivable from data: open latest cycle = start, closed = stop.
@MainActor
struct CycleStore {
    let context: ModelContext
    var now: () -> Date = { Date.now }

    func latest() throws -> Cycle? {
        var descriptor = FetchDescriptor<Cycle>(sortBy: [SortDescriptor(\.start, order: .reverse)])
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// Earliest moment a new period may start: the end of the previous one (nil = no limit).
    func earliestStart() throws -> Date? {
        try latest()?.end
    }

    /// Turns a calendar day picked in the UI ("today", "yesterday", a date picker) into a start time.
    /// Today means the current moment, a past day means its first moment. When the picked day is the
    /// day the previous period ended, the start is moved to that end so the two don't overlap.
    static func startDate(forDay day: Date, now: Date, notBefore minimum: Date?,
                          calendar: Calendar = .current) -> Date {
        var date = calendar.isDate(day, inSameDayAs: now) ? now : calendar.startOfDay(for: day)
        if let minimum, date < minimum, calendar.isDate(date, inSameDayAs: minimum) {
            date = minimum
        }
        return date
    }

    @discardableResult
    func startCycle(at date: Date) throws -> Cycle {
        guard date <= now() else { throw CycleError.dateInFuture }
        if let last = try latest() {
            guard let lastEnd = last.end else { throw CycleError.alreadyActive }
            guard date >= lastEnd else { throw CycleError.startBeforePreviousEnd }
        }
        let cycle = Cycle(start: date)
        context.insert(cycle)
        try context.save()
        return cycle
    }

    func stopCycle(at date: Date? = nil) throws {
        let date = date ?? now()
        guard date <= now() else { throw CycleError.dateInFuture }
        guard let last = try latest(), last.isActive else { throw CycleError.noActiveCycle }
        guard date >= last.start else { throw CycleError.endBeforeStart }
        last.end = date
        try context.save()
    }

    @discardableResult
    func undoLast() throws -> UndoResult {
        guard let last = try latest() else { throw CycleError.nothingToUndo }
        if last.isActive {
            context.delete(last)
            try context.save()
            return .deleted
        }
        last.end = nil
        try context.save()
        return .reopened
    }
}
