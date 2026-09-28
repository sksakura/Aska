import Foundation
import SwiftData

enum EventKind: String, Codable {
    case start
    case stop
}

/// One mark entered by the user: "period started" or "period stopped" at `date`.
/// Periods are not stored; they are derived from events (see `Period.derive`).
/// All properties have defaults, as CloudKit sync requires.
@Model
final class CycleEvent {
    var id: UUID = UUID()
    /// Stored as a raw string: plain values are the safest choice for CloudKit.
    var kindRaw: String = EventKind.start.rawValue
    var date: Date = Date.now
    /// When the event was entered; defines "the last action" for undo.
    var createdAt: Date = Date.now

    init(kind: EventKind, date: Date, createdAt: Date = .now) {
        self.kindRaw = kind.rawValue
        self.date = date
        self.createdAt = createdAt
    }

    var kind: EventKind { EventKind(rawValue: kindRaw) ?? .start }
}

/// A period as shown on screen, derived from events. `end == nil` means ongoing.
struct Period: Equatable {
    var start: Date
    var end: Date?

    var isActive: Bool { end == nil }

    /// Builds periods from events in chronological order:
    /// - several starts in a row form one period from the earliest of them;
    /// - several stops in a row close it at the latest of them;
    /// - a stop with no start before it is ignored.
    /// So a longer period covers a shorter one entered for the same time, and when the extra
    /// event is deleted, the shorter period shows up again.
    /// On equal dates a start goes before a stop.
    static func derive(from events: [(kind: EventKind, date: Date)]) -> [Period] {
        let sorted = events.sorted { lhs, rhs in
            lhs.date != rhs.date ? lhs.date < rhs.date : (lhs.kind == .start && rhs.kind == .stop)
        }
        var periods: [Period] = []
        var current: Period?
        for event in sorted {
            switch event.kind {
            case .start:
                if let closed = current, closed.end != nil {
                    periods.append(closed)
                    current = Period(start: event.date)
                } else if current == nil {
                    current = Period(start: event.date)
                }
            case .stop:
                if current != nil {
                    current?.end = event.date
                }
            }
        }
        if let current {
            periods.append(current)
        }
        return periods
    }
}

extension Calendar {
    /// 1-based day number of `date` counted from `start` (the start day is day 1).
    func dayNumber(from start: Date, to date: Date) -> Int {
        let days = dateComponents([.day], from: startOfDay(for: start), to: startOfDay(for: date)).day ?? 0
        return days + 1
    }
}
