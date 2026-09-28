import Foundation
import UserNotifications

/// "Напоминания" in the profile: one local notification the day before the next forecast period.
enum Reminders {
    static let identifier = "aska.next-period"

    /// 9:00 on the day before `forecastStart`; nil when that moment has already passed.
    static func fireDate(forecastStart: Date, now: Date, calendar: Calendar = .current) -> Date? {
        let startDay = calendar.startOfDay(for: forecastStart)
        guard let dayBefore = calendar.date(byAdding: .day, value: -1, to: startDay),
              let fire = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: dayBefore),
              fire > now else { return nil }
        return fire
    }

    /// The first forecast period whose reminder is still ahead.
    static func nextReminder(periods: [Period], settings: UserSettings, now: Date,
                             calendar: Calendar = .current) -> Date? {
        var month = now
        for _ in 0..<3 {
            let forecasts = CalendarPeriods.forMonth(containing: month, periods: periods,
                                                     cycleLength: settings.cycleLength,
                                                     periodLength: settings.periodLength,
                                                     today: now, calendar: calendar)
                .filter(\.isForecast)
            for forecast in forecasts {
                if let fire = fireDate(forecastStart: forecast.start, now: now, calendar: calendar) {
                    return fire
                }
            }
            guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
            month = next
        }
        return nil
    }

    /// Replaces the pending reminder according to the current settings and history.
    @MainActor
    static func update(settings: UserSettings, periods: [Period]) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard settings.remindersOn,
              let fire = nextReminder(periods: periods, settings: settings, now: .now) else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Aska"
        content.body = "Завтра, вероятно, начнутся месячные."
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }
}
