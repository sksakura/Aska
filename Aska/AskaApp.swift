import SwiftUI
import SwiftData

@main
struct AskaApp: App {
    @State private var settingsStore: SettingsStore
    private let container: ModelContainer
    /// Set only in Debug builds launched with `-demo <scenario>` (screenshots).
    private let demo = DemoScenario.current

    init() {
        if let demo = DemoScenario.current {
            _settingsStore = State(initialValue: demo.makeSettingsStore())
            container = demo.makeContainer()
        } else {
            _settingsStore = State(initialValue: SettingsStore())
            // Default configuration syncs through the iCloud container from the entitlements
            // when the app is signed with it, and stays local otherwise.
            do {
                container = try ModelContainer(for: CycleEvent.self)
            } catch {
                fatalError("Cannot open the data store: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ThemedRoot {
                RootView(initialScreen: demo?.screen ?? .today, schedulesReminders: demo == nil)
            }
            .environment(settingsStore)
        }
        .modelContainer(container)
    }
}

struct RootView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.theme) private var theme
    @Query(sort: \CycleEvent.date) private var events: [CycleEvent]
    /// On a fresh install iCloud settings may arrive a moment after launch;
    /// wait briefly before asking the user to set everything up again.
    @State private var waitedForCloud = false
    @State private var screen: AppScreen
    private let schedulesReminders: Bool

    init(initialScreen: AppScreen = .today, schedulesReminders: Bool = true) {
        _screen = State(initialValue: initialScreen)
        self.schedulesReminders = schedulesReminders
    }

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
            guard schedulesReminders, let settings = settingsStore.settings else { return }
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
