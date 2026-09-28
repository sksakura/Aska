import Foundation
import SwiftData

/// Demo data for screenshots: launch a Debug build with `-demo <scenario>`.
/// Uses in-memory history and throw-away settings, so real data is never touched.
enum DemoScenario: String, CaseIterable {
    case onboarding
    case today
    case todayActive = "today-active"
    case calendar
    case profile

    #if DEBUG
    /// The scenario passed on launch (`-demo today` lands in the arguments domain of UserDefaults).
    static var current: DemoScenario? {
        UserDefaults.standard.string(forKey: "demo").flatMap(DemoScenario.init)
    }
    #else
    static var current: DemoScenario? { nil }
    #endif

    var screen: AppScreen {
        switch self {
        case .onboarding, .today, .todayActive: .today
        case .calendar: .calendar
        case .profile: .profile
        }
    }

    static let settings: UserSettings = {
        let birthDate = Calendar.current.date(from: DateComponents(year: 1995, month: 6, day: 15)) ?? .now
        return UserSettings(birthDate: birthDate, menarcheYear: 2008, cycleLength: 28, periodLength: 5)
    }()

    @MainActor
    func makeSettingsStore() -> SettingsStore {
        let suite = "aska.demo"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        let store = SettingsStore(local: defaults, cloud: nil)
        if self != .onboarding {
            store.save(Self.settings)
        }
        return store
    }

    /// Two finished periods (today is day 14 of the cycle); `today-active` adds an ongoing one (day 3).
    @MainActor
    func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        // An in-memory container can only fail on a broken model, which the tests would catch.
        let container = try! ModelContainer(for: CycleEvent.self, configurations: config)
        guard self != .onboarding else { return container }

        let calendar = Calendar.current
        let now = Date.now
        func daysAgo(_ days: Int, hour: Int) -> Date {
            let day = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: now)) ?? now
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day) ?? day
        }
        let context = container.mainContext
        let marks: [(EventKind, Date)] = [
            (.start, daysAgo(41, hour: 8)), (.stop, daysAgo(37, hour: 20)),
            (.start, daysAgo(13, hour: 8)), (.stop, daysAgo(9, hour: 20)),
        ]
        for (kind, date) in marks {
            context.insert(CycleEvent(kind: kind, date: date))
        }
        if self == .todayActive {
            context.insert(CycleEvent(kind: .start, date: daysAgo(2, hour: 8)))
        }
        try? context.save()
        return container
    }
}
