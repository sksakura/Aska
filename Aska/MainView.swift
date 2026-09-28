import SwiftUI
import SwiftData

extension EventKind: Identifiable {
    var id: Self { self }
}

struct MainView: View {
    let settings: UserSettings

    @Environment(\.modelContext) private var context
    @Query(sort: \CycleEvent.date) private var events: [CycleEvent]
    @State private var showSettings = false
    @State private var confirmUndo = false
    @State private var errorMessage: String?
    /// Which mark the quick "today / yesterday / …" dialog is for.
    @State private var quickPickKind: EventKind?
    /// Which mark the calendar sheet is for.
    @State private var calendarKind: EventKind?
    @State private var pickedDay = Date.now

    private var store: CycleStore { CycleStore(context: context) }
    private var periods: [Period] { Period.derive(from: events.map { (kind: $0.kind, date: $0.date) }) }
    private var latest: Period? { periods.last }
    private var lastEntered: CycleEvent? { events.max { $0.createdAt < $1.createdAt } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    StatusView(periods: periods, settings: settings)
                    actionButton
                    if let lastEntered {
                        Button(undoTitle(for: lastEntered), role: .destructive) { confirmUndo = true }
                    }
                }
                if !periods.isEmpty {
                    Section {
                        ForEach(periods.reversed(), id: \.start) { period in
                            PeriodRow(period: period)
                                .swipeActions {
                                    Button("Удалить начало", role: .destructive) {
                                        perform { try store.deleteStart(onDay: period.start) }
                                    }
                                    if let end = period.end {
                                        Button("Удалить окончание") {
                                            perform { try store.deleteStop(onDay: end) }
                                        }
                                        .tint(.orange)
                                    }
                                }
                        }
                    } header: {
                        Text("История")
                    } footer: {
                        Text("Смахните период влево, чтобы удалить отметку начала или окончания.")
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
            .confirmationDialog(lastEntered.map { undoTitle(for: $0) } ?? "", isPresented: $confirmUndo,
                                titleVisibility: .visible) {
                if let lastEntered {
                    Button(undoTitle(for: lastEntered), role: .destructive) {
                        perform { try store.undoLast() }
                    }
                }
            } message: {
                Text(lastEntered?.kind == .stop
                     ? "Отметка окончания будет удалена."
                     : "Отметка начала будет удалена.")
            }
            .confirmationDialog(quickPickKind == .stop ? "Когда закончился период?" : "Когда начался период?",
                                isPresented: Binding(
                                    get: { quickPickKind != nil },
                                    set: { if !$0 { quickPickKind = nil } }
                                ),
                                titleVisibility: .visible,
                                presenting: quickPickKind) { kind in
                ForEach(quickDays(for: kind), id: \.offset) { option in
                    Button(option.title) { add(kind, onDay: option.day) }
                }
                Button("Выбрать дату…") {
                    pickedDay = .now
                    calendarKind = kind
                }
            }
            .sheet(item: $calendarKind) { kind in
                DayPickerSheet(kind: kind, day: $pickedDay, range: dayRange(for: kind)) {
                    calendarKind = nil
                    add(kind, onDay: pickedDay)
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
            Button("Период закончился") { quickPickKind = .stop }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        } else {
            Button("Период начался") { quickPickKind = .start }
                .buttonStyle(.borderedProminent)
                .tint(.pink)
                .frame(maxWidth: .infinity)
        }
    }

    /// A stop can't be earlier than the start of the ongoing period; a start has no lower limit.
    private func earliestDay(for kind: EventKind) -> Date? {
        kind == .stop ? latest?.start : nil
    }

    private func dayRange(for kind: EventKind) -> ClosedRange<Date> {
        (earliestDay(for: kind) ?? .distantPast)...Date.now
    }

    /// Today / yesterday / the day before, minus days outside the allowed range.
    private func quickDays(for kind: EventKind) -> [(offset: Int, title: String, day: Date)] {
        let calendar = Calendar.current
        var options: [(offset: Int, title: String, day: Date)] = []
        for (offset, title) in ["Сегодня", "Вчера", "Позавчера"].enumerated() {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: .now) else { continue }
            if let earliest = earliestDay(for: kind),
               calendar.startOfDay(for: day) < calendar.startOfDay(for: earliest) {
                continue
            }
            options.append((offset: offset, title: title, day: day))
        }
        return options
    }

    private func add(_ kind: EventKind, onDay day: Date) {
        let date = CycleStore.eventDate(for: kind, onDay: day, now: .now)
        perform {
            switch kind {
            case .start: try store.startCycle(at: date)
            case .stop: try store.stopCycle(at: date)
            }
        }
    }

    private func undoTitle(for event: CycleEvent) -> String {
        let day = event.date.formatted(.dateTime.day().month())
        return event.kind == .stop ? "Отменить окончание \(day)" : "Отменить начало \(day)"
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DayPickerSheet: View {
    let kind: EventKind
    @Binding var day: Date
    let range: ClosedRange<Date>
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(kind == .stop ? "День окончания" : "День начала",
                       selection: $day, in: range, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(kind == .stop ? "Окончание периода" : "Начало периода")
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
    let periods: [Period]
    let settings: UserSettings

    private var latest: Period? { periods.last }

    var body: some View {
        VStack(spacing: 8) {
            if let latest {
                let day = Calendar.current.dayNumber(from: latest.start, to: .now)
                if latest.isActive {
                    Text("🩸").font(.system(size: 56))
                    Text("Период идёт: день \(day)").font(.title2.bold())
                    Text("Обычно длится \(settings.periodLength) дн.").foregroundStyle(.secondary)
                } else {
                    Text("😊").font(.system(size: 56))
                    Text("День цикла: \(day)").font(.title2.bold())
                    if let next = CalendarPeriods.nextForecast(periods: periods,
                                                               cycleLength: settings.cycleLength,
                                                               periodLength: settings.periodLength,
                                                               today: .now) {
                        Text("Следующий период ≈ \(next.start.formatted(.dateTime.day().month()))")
                            .foregroundStyle(.secondary)
                    }
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

private struct PeriodRow: View {
    let period: Period

    var body: some View {
        HStack {
            Text(period.start.formatted(.dateTime.day().month()))
            Text("–")
            if let end = period.end {
                Text(end.formatted(.dateTime.day().month()))
                Spacer()
                Text("\(Calendar.current.dayNumber(from: period.start, to: end)) дн.")
                    .foregroundStyle(.secondary)
            } else {
                Text("сейчас")
                Spacer()
            }
        }
    }
}
