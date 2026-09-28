import SwiftUI
import SwiftData

/// "Сегодня": the cycle ring, undo and the start/stop button.
/// Long press on the droplet opens "yesterday / the day before"; swipe right opens the calendar.
struct TodayView: View {
    let settings: UserSettings
    var onNavigate: (AppScreen) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.modelContext) private var context
    @Query(sort: \CycleEvent.date) private var events: [CycleEvent]
    @State private var showBackdate = false
    @State private var errorMessage: String?

    private var store: CycleStore { CycleStore(context: context) }
    private var periods: [Period] { Period.derive(from: events.map { (kind: $0.kind, date: $0.date) }) }
    private var latest: Period? { periods.last }
    private var isPeriodActive: Bool { latest?.isActive == true }
    private var summary: CycleSummary {
        CycleSummary.make(periods: periods, cycleLength: settings.cycleLength,
                          periodLength: settings.periodLength, today: .now)
    }
    /// Period segment on the ring: the real length of a finished period, the usual one otherwise.
    private var periodDays: Int {
        guard let latest, let end = latest.end else { return settings.periodLength }
        return Calendar.current.dayNumber(from: latest.start, to: end)
    }

    // Vertical positions from the prototype: 28 top padding + 18 margin, 272 ring, 40 gap.
    private var ringTop: CGFloat { 46 }
    private var controlsTop: CGFloat { 46 + 272 + 40 }

    var body: some View {
        ZStack(alignment: .top) {
            theme.bg.ignoresSafeArea()

            CycleRing(day: summary.dayOfCycle, cycleLength: settings.cycleLength,
                      periodDays: periodDays, isPeriodActive: isPeriodActive)
                .padding(.top, ringTop)

            if showBackdate {
                // Tapping anywhere else closes the backdate buttons.
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture { showBackdate = false }
            }

            VStack(spacing: 0) {
                Spacer().frame(height: controlsTop)
                controls
                Spacer()
                TabBar(selected: .today, onSelect: onNavigate)
            }
            .padding(.horizontal, 24)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 20).onEnded { value in
                let dx = value.translation.width, dy = value.translation.height
                if dx > 60 && abs(dy) < 40 { onNavigate(.calendar) }
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

    private var controls: some View {
        HStack(spacing: 18) {
            Button { perform { try store.undoLast() } } label: {
                UndoIcon(color: theme.inkFaint)
                    .frame(width: 48, height: 48)
                    .background(theme.chipBg, in: Circle())
            }
            .buttonStyle(CircleButtonStyle())
            .disabled(events.isEmpty)
            .opacity(events.isEmpty ? 0.35 : 1)
            .accessibilityLabel("Отменить")

            if isPeriodActive {
                Button { perform { try store.stopCycle(at: .now) } } label: {
                    StopIcon(color: theme.accent)
                        .frame(width: 76, height: 76)
                        .background(theme.actionButtonBg, in: Circle())
                }
                .buttonStyle(CircleButtonStyle())
                .accessibilityLabel("Закончились месячные")
            } else {
                startButton
            }

            Color.clear.frame(width: 48, height: 48)
        }
        .frame(maxWidth: .infinity)
    }

    private var startButton: some View {
        Icons.droplet
            .fill(theme.accent)
            .frame(width: 26, height: 26)
            .frame(width: 76, height: 76)
            .background(theme.actionButtonBg, in: Circle())
            .contentShape(Circle())
            .onTapGesture { start(daysAgo: 0) }
            .onLongPressGesture(minimumDuration: 0.45) { showBackdate = true }
            .overlay(alignment: .trailing) {
                if showBackdate {
                    HStack(spacing: 8) {
                        backdateButton(daysAgo: 2, title: "Позавчера", size: 52, iconSize: 17, labelSize: 9)
                        backdateButton(daysAgo: 1, title: "Вчера", size: 58, iconSize: 19, labelSize: 10)
                    }
                    .fixedSize()
                    .offset(x: -88)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Начались месячные")
            .accessibilityHint("Удерживайте, чтобы отметить вчера или позавчера")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { start(daysAgo: 0) }
            .accessibilityAction(named: "Начались вчера") { start(daysAgo: 1) }
            .accessibilityAction(named: "Начались позавчера") { start(daysAgo: 2) }
    }

    private func backdateButton(daysAgo: Int, title: String, size: CGFloat,
                                iconSize: CGFloat, labelSize: CGFloat) -> some View {
        Button { start(daysAgo: daysAgo) } label: {
            VStack(spacing: 1) {
                ZStack {
                    Circle().stroke(theme.ink, lineWidth: 1.6 * iconSize / 16)
                        .frame(width: iconSize * 13 / 16, height: iconSize * 13 / 16)
                    Text("-\(daysAgo)")
                        .font(.system(size: iconSize * 0.5))
                        .foregroundStyle(theme.ink)
                }
                .frame(width: iconSize, height: iconSize)
                Text(title)
                    .font(.system(size: labelSize))
                    .foregroundStyle(theme.inkMuted)
            }
            .frame(width: size, height: size)
            .background(theme.cardBg, in: Circle())
            .shadow(color: theme.shadow, radius: 6, y: 4)
        }
        .buttonStyle(CircleButtonStyle())
    }

    private func start(daysAgo: Int) {
        showBackdate = false
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now) ?? .now
        let date = CycleStore.eventDate(for: .start, onDay: day, now: .now)
        perform { try store.startCycle(at: date) }
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
