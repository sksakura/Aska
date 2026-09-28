import SwiftUI

struct SettingsForm: View {
    @Binding var settings: UserSettings

    var body: some View {
        Section("О вас") {
            Picker("Год рождения", selection: $settings.birthYear) {
                ForEach(UserSettings.birthYearRange().reversed(), id: \.self) { year in
                    Text(String(year)).tag(year)
                }
            }
            Stepper("Первая менструация в \(settings.menarcheAge) лет",
                    value: $settings.menarcheAge, in: UserSettings.menarcheAgeRange)
        }
        Section {
            Stepper("Длина цикла: \(settings.cycleLength) дн.",
                    value: $settings.cycleLength, in: UserSettings.cycleLengthRange)
            Stepper("Длина периода: \(settings.periodLength) дн.",
                    value: $settings.periodLength, in: UserSettings.periodLengthRange)
        } header: {
            Text("Цикл")
        } footer: {
            if !settings.isValid() {
                Text("Первая менструация не может быть позже текущего года — проверьте год рождения и возраст.")
                    .foregroundStyle(.red)
            }
        }
    }
}

struct OnboardingView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @State private var draft = UserSettings.default

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("😊")
                        .font(.system(size: 64))
                        .frame(maxWidth: .infinity)
                    Text("Расскажите немного о себе. Всё можно будет поменять в настройках.")
                }
                SettingsForm(settings: $draft)
                Section {
                    Button("Продолжить") { settingsStore.save(draft) }
                        .frame(maxWidth: .infinity)
                        .disabled(!draft.isValid())
                }
            }
            .navigationTitle("Добро пожаловать")
        }
    }
}

struct SettingsView: View {
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(\.dismiss) private var dismiss
    @State private var draft: UserSettings

    init(settings: UserSettings) {
        _draft = State(initialValue: settings)
    }

    var body: some View {
        NavigationStack {
            Form {
                SettingsForm(settings: $draft)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        settingsStore.save(draft)
                        dismiss()
                    }
                    .disabled(!draft.isValid())
                }
            }
        }
    }
}
