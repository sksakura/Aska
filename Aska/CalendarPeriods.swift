import Foundation

/// Whether a date shown on screen was entered by the user or predicted.
enum Certainty: Equatable {
    case fact
    case forecast
}

/// A period as shown in a month view. Dates are calendar days (start of day), `end` is inclusive.
/// A recorded period is fact/fact, an ongoing one is fact/forecast, a predicted one forecast/forecast.
struct CalendarPeriod: Equatable {
    var start: Date
    var end: Date
    var startCertainty: Certainty
    var endCertainty: Certainty

    var isForecast: Bool { startCertainty == .forecast }
}

enum CalendarPeriods {
    /// Periods that overlap the calendar month containing `date`: recorded ones plus forecasts.
    ///
    /// Forecast rules:
    /// - next start = last period end + `cycleLength` days;
    /// - its end = last period end + `cycleLength` + `periodLength` days;
    /// - later forecasts repeat the same rule from the previous forecast's end;
    /// - an ongoing period keeps its real start, its end is forecast as start + `periodLength`,
    ///   but never earlier than `today` (the period has not ended yet).
    static func forMonth(containing date: Date,
                         periods: [Period],
                         cycleLength: Int,
                         periodLength: Int,
                         today: Date,
                         calendar: Calendar = .current) -> [CalendarPeriod] {
        guard let month = calendar.dateInterval(of: .month, for: date) else { return [] }
        let monthStart = month.start
        let monthEnd = month.end  // first moment of the next month
        func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }
        func adding(_ days: Int, to date: Date) -> Date {
            calendar.date(byAdding: .day, value: days, to: date) ?? date
        }

        var result: [CalendarPeriod] = []
        var lastEnd: Date?

        for period in periods {
            if let end = period.end {
                result.append(CalendarPeriod(start: day(period.start), end: day(end),
                                             startCertainty: .fact, endCertainty: .fact))
                lastEnd = day(end)
            } else {
                let start = day(period.start)
                let end = max(adding(periodLength, to: start), day(today))
                result.append(CalendarPeriod(start: start, end: end,
                                             startCertainty: .fact, endCertainty: .forecast))
                lastEnd = end
            }
        }

        if var base = lastEnd {
            while true {
                let start = adding(cycleLength, to: base)
                guard start < monthEnd else { break }
                let end = adding(cycleLength + periodLength, to: base)
                result.append(CalendarPeriod(start: start, end: end,
                                             startCertainty: .forecast, endCertainty: .forecast))
                base = end
            }
        }

        return result.filter { $0.start < monthEnd && $0.end >= monthStart }
    }

    /// The first forecast period starting after the last recorded or ongoing one.
    static func nextForecast(periods: [Period], cycleLength: Int, periodLength: Int,
                             today: Date, calendar: Calendar = .current) -> CalendarPeriod? {
        var month = today
        // Forecasts are at most cycleLength + periodLength days apart, so a few months is enough.
        for _ in 0..<4 {
            let found = forMonth(containing: month, periods: periods, cycleLength: cycleLength,
                                 periodLength: periodLength, today: today, calendar: calendar)
                .first { $0.isForecast }
            if let found { return found }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return nil
    }
}
