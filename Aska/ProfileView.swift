import SwiftUI

/// The settings form from the "Профиль" screen, reused by the first-launch setup.
struct ProfileForm: View {
    @Environment(\.theme) private var theme
    @Binding var settings: UserSettings

    private var birthYear: Int { settings.birthYear() }
    private var birthDateRange: ClosedRange<Date> {
        let years = UserSettings.birthYearRange()
        let calendar = Calendar.current
        let lower = calendar.date(from: DateComponents(year: years.lowerBound, month: 1, day: 1)) ?? .distantPast
        let upper = calendar.date(from: DateComponents(year: years.upperBound, month: 12, day: 31)) ?? .now
        return lower...upper
    }

    var body: some View {
        VStack(spacing: 18) {
            CardGroup {
                CardRow(title: "Дата рождения") {
                    DatePicker("Дата рождения", selection: birthDate, in: birthDateRange, displayedComponents: .date)
                        .labelsHidden()
                        .environment(\.locale, Locale(identifier: "ru_RU"))
                }
                CardDivider()
                CardRow(title: "Год начала менструаций") {
                    RoundStepper(value: settings.menarcheYear,
                                 range: UserSettings.menarcheYearRange(birthYear: birthYear),
                                 valueWidth: 44) { settings.menarcheYear = $0 }
                }
            }

            CardGroup {
                CardRow(title: "Длительность цикла") {
                    RoundStepper(value: settings.cycleLength, range: UserSettings.cycleLengthRange) {
                        settings.cycleLength = $0
                    }
                }
                CardDivider()
                CardRow(title: "Длительность менструации") {
                    RoundStepper(value: settings.periodLength, range: UserSettings.periodLengthRange) {
                        settings.periodLength = $0
                    }
                }
            }

            CardGroup {
                CardRow(title: "Напоминания") {
                    PillSwitch(isOn: settings.remindersOn) { settings.remindersOn.toggle() }
                        .accessibilityLabel("Напоминания")
                }
            }
        }
    }

    /// Changing the birth date keeps the first-period year within 8–18 years after it.
    private var birthDate: Binding<Date> {
        Binding {
            settings.birthDate
        } set: { newValue in
            var updated = settings
            updated.birthDate = newValue
            let range = UserSettings.menarcheYearRange(birthYear: updated.birthYear())
            updated.menarcheYear = min(max(updated.menarcheYear, range.lowerBound), range.upperBound)
            settings = updated
        }
    }
}

/// "Профиль": every change is saved right away, as in the prototype.
struct ProfileView: View {
    let settings: UserSettings
    var onNavigate: (AppScreen) -> Void

    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Профиль")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 4)
                .padding(.bottom, 20)

            ScrollView {
                ProfileForm(settings: Binding(
                    get: { settings },
                    set: { if $0.isValid() { settingsStore.save($0) } }
                ))
            }
            .scrollBounceBehavior(.basedOnSize)

            TabBar(selected: .profile, onSelect: onNavigate)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 28)
        .padding(.horizontal, 20)
        .background(theme.bg.ignoresSafeArea())
    }
}

/// First launch: the same form plus a "Продолжить" button.
struct OnboardingView: View {
    @Environment(\.theme) private var theme
    @Environment(SettingsStore.self) private var settingsStore
    @State private var draft = UserSettings.default

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Добро пожаловать")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.5)
                .foregroundStyle(theme.ink)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)
            Text("Расскажите немного о себе. Всё можно поменять потом в профиле.")
                .font(.system(size: 15))
                .foregroundStyle(theme.inkMuted)
                .padding(.horizontal, 4)
                .padding(.bottom, 20)

            ScrollView {
                ProfileForm(settings: $draft)
            }
            .scrollBounceBehavior(.basedOnSize)

            Button {
                settingsStore.save(draft)
            } label: {
                Text("Продолжить")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(theme.accent, in: Capsule())
            }
            .buttonStyle(CircleButtonStyle())
            .disabled(!draft.isValid())
            .padding(.bottom, 14)
        }
        .padding(.top, 28)
        .padding(.horizontal, 20)
        .background(theme.bg.ignoresSafeArea())
    }
}
