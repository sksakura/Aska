import Foundation
import SwiftData

/// One period: from `start` until `end`. `end == nil` means the period is ongoing.
/// All properties have defaults, as CloudKit sync requires.
@Model
final class Cycle {
    var id: UUID = UUID()
    var start: Date = Date.now
    var end: Date? = nil

    init(start: Date, end: Date? = nil) {
        self.start = start
        self.end = end
    }

    var isActive: Bool { end == nil }
}

extension Calendar {
    /// 1-based day number of `date` counted from `start` (the start day is day 1).
    func dayNumber(from start: Date, to date: Date) -> Int {
        let days = dateComponents([.day], from: startOfDay(for: start), to: startOfDay(for: date)).day ?? 0
        return days + 1
    }
}
