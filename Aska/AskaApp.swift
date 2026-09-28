import SwiftUI
import SwiftData

@main
struct AskaApp: App {
    @State private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(settingsStore)
        }
        // Default configuration syncs through the iCloud container from the entitlements
        // when the app is signed with it, and stays local otherwise.
        .modelContainer(for: Cycle.self)
    }
}

struct RootView: View {
    @Environment(SettingsStore.self) private var settingsStore
    /// On a fresh install iCloud settings may arrive a moment after launch;
    /// wait briefly before asking the user to set everything up again.
    @State private var waitedForCloud = false

    var body: some View {
        if let settings = settingsStore.settings {
            MainView(settings: settings)
        } else if !waitedForCloud {
            ProgressView()
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    waitedForCloud = true
                }
        } else {
            OnboardingView()
        }
    }
}
