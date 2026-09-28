import SwiftUI
import SwiftData

/// Month grid with recorded (filled) and forecast (dashed) period days.
/// Tap a day to get "+" (mark) or "×" (unmark) right on it; swipe left/right to change the month.
struct CalendarView: View {
    let settings: UserSettings
    var onNavigate: (AppScreen) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \CycleEvent.date) private var events: [CycleEvent]
    @State private var monthOffset = 0
    @State private var selectedDay: Date?
    @State private var errorMessage: String?

    private var calendar: Calendar { .current }
    private var weekdays: [String] { ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"] }

    private var store: CycleStore { CycleStore(context: context) }
    private var today: Date { calendar.startOfDay(for: .now) }
    private var monthStart: Date {
        let current = calendar.dateInterval(of: .month, for: today)?.start ?? today
        return calendar.date(byAdding: .month, value: monthOffset, to: current) ?? current
    }
    private var monthPeriods: [CalendarPeriod] {
        let periods = Period.derive(from: events.map { (kind: $0.kind, date: $0.date) })
        return CalendarPeriods.forMonth(containing: monthStart, periods: periods,
                                        cycleLength: settings.cycleLength,
                                        periodLength: settings.periodLength, today: .now)
    }
    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: monthStart)
    }
    /// Weeks of the month, Monday first; nil cells pad the first and last week.
    private var weeks: [[Date?]] {
        let days = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let leading = (calendar.component(.weekday, from: monthStart) + 5) % 7
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for day in 0..<days {
            cells.append(calendar.date(byAdding: .day, value: day, to: monthStart))
        }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    var body: some View {
        let periods = monthPeriods
        VStack(spacing: 0) {
            header
            HStack(spacing: 0) {
                ForEach(weekdays, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.inkFaint)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 6)

            VStack(spacing: 6) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { index in
                            cell(week[index], periods: periods)
                        }
                    }
                    .zIndex(week.contains(where: { $0 != nil && $0 == selectedDay }) ? 1 : 0)
                }
            }

            Spacer(minLength: 0)
            legend.padding(.bottom, 14)
            TabBar(selected: .today, onSelect: onNavigate)
        }
        .padding(.top, 28)
        .padding(.horizontal, 20)
        .background(theme.bg.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { selectedDay = nil }
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                guard abs(dy) <= 40 else { return }
                if dx < -60 { changeMonth(by: 1) } else if dx > 60 { changeMonth(by: -1) }
            }
        )
        .alert("Не получилось", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            monthButton(Icons.chevronLeft, label: "Предыдущий месяц") { changeMonth(by: -1) }
            Spacer()
            Text(monthTitle)
                .font(.system(size: 18, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(theme.ink)
            Spacer()
            monthButton(Icons.chevronRight, label: "Следующий месяц") { changeMonth(by: 1) }
        }
        .padding(.horizontal, 4)
        .padding(.bottom, 18)
    }

    private func monthButton(_ icon: ViewBoxShape, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            icon.stroke(theme.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 14, height: 14)
                .frame(width: 36, height: 36)
                .background(theme.chipBg, in: Circle())
        }
        .buttonStyle(CircleButtonStyle())
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func cell(_ day: Date?, periods: [CalendarPeriod]) -> some View {
        if let day {
            let mark = CalendarPeriods.mark(for: day, in: periods, today: .now)
            let isSelected = day == selectedDay
            DayCell(day: calendar.component(.day, from: day), mark: mark,
                    isToday: day == today)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .contentShape(Rectangle())
                .onTapGesture { tap(day, mark: mark) }
                .overlay {
                    if isSelected { dayMenu(day, isFact: mark == .fact) }
                }
                .zIndex(isSelected ? 1 : 0)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityLabel(day, mark: mark))
                .accessibilityAddTraits(.isButton)
        } else {
            Color.clear.frame(maxWidth: .infinity).frame(height: 40)
        }
    }

    /// The round "+" / "×" button placed right on the tapped day.
    private func dayMenu(_ day: Date, isFact: Bool) -> some View {
        Button {
            selectedDay = nil
            perform {
                if isFact {
                    try store.unmarkDay(day)
                } else {
                    try store.markDay(day)
                }
            }
        } label: {
            Group {
                if isFact {
                    Icons.cross.stroke(theme.deleteMark, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                } else {
                    Icons.plus.stroke(theme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                }
            }
            .frame(width: 20, height: 20)
            .frame(width: 52, height: 52)
            .background(theme.cardBg, in: Circle())
            .shadow(color: theme.shadow, radius: 6, y: 4)
        }
        .buttonStyle(CircleButtonStyle())
        .accessibilityLabel(isFact ? "Убрать отметку" : "Отметить день месячных")
    }

    private var legend: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(theme.accent).frame(width: 10, height: 10)
                Text("Факт").font(.system(size: 12)).foregroundStyle(theme.inkMuted)
            }
            HStack(spacing: 6) {
                Circle()
                    .strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                    .frame(width: 10, height: 10)
                Text("Прогноз").font(.system(size: 12)).foregroundStyle(theme.inkMuted)
            }
        }
    }

    private func tap(_ day: Date, mark: DayMark) {
        if selectedDay != nil {
            selectedDay = nil
            return
        }
        // Future days can't be marked; recorded days can always be unmarked.
        guard mark == .fact || day <= today else { return }
        selectedDay = day
    }

    private func changeMonth(by delta: Int) {
        selectedDay = nil
        monthOffset += delta
    }

    private func accessibilityLabel(_ day: Date, mark: DayMark) -> String {
        let date = day.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "ru_RU")))
        switch mark {
        case .fact: return "\(date), месячные"
        case .forecast: return "\(date), прогноз месячных"
        case .none: return date
        }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct DayCell: View {
    @Environment(\.theme) private var theme
    var day: Int
    var mark: DayMark
    var isToday: Bool

    var body: some View {
        ZStack {
            if mark == .fact {
                Circle().fill(theme.accent)
            } else if mark == .forecast {
                Circle().strokeBorder(theme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
            }
            if isToday {
                Circle().stroke(theme.accent, lineWidth: 2).frame(width: 38, height: 38)
            }
            Text(String(day))
                .font(.system(size: 14))
                .monospacedDigit()
                .foregroundStyle(mark == .fact ? theme.onAccent : theme.ink)
        }
        .frame(width: 34, height: 34)
    }
}
