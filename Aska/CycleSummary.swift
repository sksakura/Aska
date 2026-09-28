import Foundation

/// Data for the main screen: the cycle, the period inside it and where today is.
struct CycleSummary: Equatable {
    /// Cycle length in days, from settings (e.g. 28).
    var cycleLength: Int
    /// Period length in days, from settings (e.g. 4).
    var periodLength: Int
    /// Today's day of the cycle, 1-based (the day the last period started is day 1).
    /// `nil` when no period has been recorded yet.
    var dayOfCycle: Int?
    /// Share of the cycle taken by the period, 0…100 (4 of 28 → 14.29).
    var periodPercent: Double
    /// Share of the cycle already passed including today, 0…100 (day 14 of 28 → 50).
    /// Capped at 100 when the cycle runs longer than expected; `nil` without history.
    var todayPercent: Double?

    /// True when today is past the expected cycle length and a new period hasn't been marked.
    var isLate: Bool { (dayOfCycle ?? 0) > cycleLength }

    static func make(periods: [Period], cycleLength: Int, periodLength: Int,
                     today: Date, calendar: Calendar = .current) -> CycleSummary {
        let dayOfCycle = periods.last.map { calendar.dayNumber(from: $0.start, to: today) }
        let todayPercent = dayOfCycle.map { min(percent($0, of: cycleLength), 100) }
        return CycleSummary(cycleLength: cycleLength,
                            periodLength: periodLength,
                            dayOfCycle: dayOfCycle,
                            periodPercent: percent(periodLength, of: cycleLength),
                            todayPercent: todayPercent)
    }

    private static func percent(_ part: Int, of whole: Int) -> Double {
        whole > 0 ? Double(part) / Double(whole) * 100 : 0
    }
}
