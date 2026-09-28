import Foundation
import Testing
@testable import Aska

struct ThemeTests {
    func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.01 }

    @Test("TH1: OKLCH → sRGB: белый, чёрный и чистый красный")
    func referenceColors() {
        let white = oklchToSRGB(1, 0, 0)
        #expect(close(white.red, 1) && close(white.green, 1) && close(white.blue, 1))
        let black = oklchToSRGB(0, 0, 0)
        #expect(close(black.red, 0) && close(black.green, 0) && close(black.blue, 0))
        let red = oklchToSRGB(0.62796, 0.25768, 29.2339)
        #expect(close(red.red, 1) && close(red.green, 0) && close(red.blue, 0))
    }

    @Test("TH2: цвета вне охвата sRGB обрезаются в 0…1")
    func clipping() {
        let rgb = oklchToSRGB(0.9, 0.4, 145)
        for component in [rgb.red, rgb.green, rgb.blue] {
            #expect(component >= 0 && component <= 1)
        }
    }

    @Test("TH3: кольцо — прошедшая доля цикла закрашена акцентом, дальше приглушённый цвет")
    func ringStops() {
        let locations = Theme(isDark: false).ringStops(progress: 0.5).map { $0.location }
        #expect(locations == [0, 0.5, 0.5 + 8.0 / 360, 1])
        let full = Theme(isDark: false).ringStops(progress: 1.4)
        #expect(full[1].location == 1)
    }
}

struct RemindersTests {
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    func d(_ month: Int, _ day: Int, hour: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    @Test("RM1: напоминание — в 9:00 накануне прогнозного начала")
    func dayBeforeAtNine() {
        #expect(Reminders.fireDate(forecastStart: d(10, 5, hour: 0), now: d(9, 28), calendar: calendar) == d(10, 4, hour: 9))
    }

    @Test("RM2: если момент уже прошёл — напоминания нет")
    func passed() {
        #expect(Reminders.fireDate(forecastStart: d(10, 5), now: d(10, 4, hour: 10), calendar: calendar) == nil)
    }

    @Test("RM3: берётся ближайший прогноз, напоминание о котором ещё впереди")
    func nextReminder() {
        let settings = UserSettings(birthDate: birthday(1995), menarcheYear: 2008, cycleLength: 28, periodLength: 5)
        let periods = [Period(start: d(9, 1), end: d(9, 5))]
        // прогноз 29 сент → напоминание 28 сент 9:00; сейчас 28 сент 10:00 → следующий прогноз 27 окт
        let fire = Reminders.nextReminder(periods: periods, settings: settings, now: d(9, 28, hour: 10), calendar: calendar)
        #expect(fire == d(10, 26, hour: 9))
    }
}
