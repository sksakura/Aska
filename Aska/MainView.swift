import SwiftUI
import SwiftData

struct MainView: View {
    let settings: UserSettings

    @Environment(\.modelContext) private var context
    @Query(sort: \Cycle.start, order: .reverse) private var cycles: [Cycle]
    @State private var showSettings = false
    @State private var confirmUndo = false
    @State private var errorMessage: String?
    @State private var chooseStartDay = false
    @State private var showDatePicker = false
    @State private var pickedDay = Date.now

    private var store: CycleStore { CycleStore(context: context) }
    private var latest: Cycle? { cycles.first }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatusView(latest: latest, settings: settings)
                    actionButton
                    if latest != nil {
                        Button(undoTitle, role: .destructive) { confirmUndo = true }
                    }
                }
                if !cycles.isEmpty {
                    Section("История") {
                        ForEach(cycles) { CycleRow(cycle: $0) }
                    }
                }
            }
            .navigationTitle("Aska")
            .toolbar {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Настройки")
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(settings: settings)
            }
            .confirmationDialog(undoTitle, isPresented: $confirmUndo, titleVisibility: .visible) {
                Button(undoTitle, role: .destructive) { perform { try store.undoLast() } }
            } message: {
                Text(latest?.isActive == true
                     ? "Запись о начале периода будет удалена."
                     : "Период снова будет считаться идущим.")
            }
            .confirmationDialog("Когда начался период?", isPresented: $chooseStartDay, titleVisibility: .visible) {
                ForEach(quickStartDays, id: \.offset) { option in
                    Button(option.title) { start(onDay: option.day) }
                }
                Button("Выбрать дату…") {
                    pickedDay = .now
                    showDatePicker = true
                }
            }
            .sheet(isPresented: $showDatePicker) {
                StartDatePicker(day: $pickedDay, range: startDayRange) {
                    showDatePicker = false
                    start(onDay: pickedDay)
                }
            }
            .alert("Не получилось", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if latest?.isActive == true {
            Button("Период закончился") { perform { try store.stopCycle() } }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        } else {
            Button("Период начался") { chooseStartDay = true }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .frame(maxWidth: .infinity)
        }
    }

    /// Earliest allowed start: the end of the previous period.
    private var previousEnd: Date? { latest?.end }

    private var startDayRange: ClosedRange<Date> {
        (previousEnd ?? .distantPast)...Date.now
    }

    /// Today / yesterday / the day before, minus days before the previous period ended.
    private var quickStartDays: [(offset: Int, title: String, day: Date)] {
        let calendar = Calendar.current
        var options: [(offset: Int, title: String, day: Date)] = []
        for (offset, title) in ["Сегодня", "Вчера", "Позавчера"].enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
            if let previousEnd, calendar.startOfDay(for: day) < calendar.startOfDay(for: previousEnd) {
                continue
            }
            options.append((offset: offset, title: title, day: day))
        }
        return options
    }

    private func start(onDay day: Date) {
        let date = CycleStore.startDate(forDay: day, now: .now, notBefore: previousEnd)
        perform { try store.startCycle(at: date) }
    }

    private var undoTitle: String {
        latest?.isActive == true ? "Отменить начало" : "Отменить окончание"
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct StartDatePicker: View {
    @Binding var day: Date
    let range: ClosedRange<Date>
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker("День начала", selection: $day, in: range, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Начало периода")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Готово", action: onDone)
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct StatusView: View {
    let latest: Cycle?
    let settings: UserSettings

    var body: some View {
        VStack(spacing: 8) {
            if let latest {
                let day = Calendar.current.dayNumber(from: latest.start, to: .now)
                if latest.isActive {
                    Text("🩸").font(.system(size: 56))
                    Text("Период идёт: день \(day)").font(.title2.bold())
                    Text("Обычно длится \(settings.periodLength) дн.").foregroundStyle(.secondary)
                } else {
                    let next = Calendar.current.date(byAdding: .day, value: settings.cycleLength, to: latest.start) ?? .now
                    Text("😊").font(.system(size: 56))
                    Text("День цикла: \(day)").font(.title2.bold())
                    Text("Следующий период ≈ \(next.formatted(.dateTime.day().month()))")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("😊").font(.system(size: 56))
                Text("Отметьте начало периода, когда он начнётся")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}

private struct CycleRow: View {
    let cycle: Cycle

    var body: some View {
        HStack {
            Text(cycle.start.formatted(.dateTime.day().month()))
            Text("–")
            if let end = cycle.end {
                Text(end.formatted(.dateTime.day().month()))
                Spacer()
                Text("\(Calendar.current.dayNumber(from: cycle.start, to: end)) дн.")
                    .foregroundStyle(.secondary)
            } else {
                Text("сейчас")
                Spacer()
            }
        }
    }
}
