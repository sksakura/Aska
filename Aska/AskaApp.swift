import SwiftUI
import SwiftData

@main
struct AskaApp: App {
    @State private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ThemedRoot {
                RootView()
            }
            .environment(settingsStore)
        }
        // Default configuration syncs through the iCloud container from the entitlements
        // when the app is signed with it, and stays local otherwise.
        .modelContainer(for: CycleEvent.self)
    }
}

struct RootView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.theme) private var theme
    @Query(sort: \CycleEvent.date) private var events: [CycleEvent]
    /// On a fresh install iCloud settings may arrive a moment after launch;
    /// wait briefly before asking the user to set everything up again.
    @State private var waitedForCloud = false
    @State private var screen: AppScreen = .today

    var body: some View {
        Group {
            if let settings = settingsStore.settings {
                switch screen {
                case .today: TodayView(settings: settings) { screen = $0 }
                case .calendar: CalendarView(settings: settings) { screen = $0 }
                case .profile: ProfileView(settings: settings) { screen = $0 }
                }
            } else if !waitedForCloud {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.bg.ignoresSafeArea())
                    .task {
                        try? await Task.sleep(for: .seconds(2))
                        waitedForCloud = true
                    }
            } else {
                OnboardingView()
            }
        }
        .task(id: reminderKey) {
            guard let settings = settingsStore.settings else { return }
            let periods = Period.derive(from: events.map { (kind: $0.kind, date: $0.date) })
            await Reminders.update(settings: settings, periods: periods)
        }
    }

    /// Changes whenever the reminder might need rescheduling.
    private var reminderKey: String {
        let settings = settingsStore.settings
        return "\(settings?.remindersOn ?? false)|\(settings?.cycleLength ?? 0)|\(settings?.periodLength ?? 0)|"
            + events.map { "\($0.kindRaw)\($0.date.timeIntervalSince1970)" }.joined(separator: ",")
    }
}
