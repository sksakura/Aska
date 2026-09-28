import SwiftUI

/// The glowing cycle ring from the hand-off: passed days in the accent colour clockwise from the top,
/// the period segment with tick marks over it, and "day/cycle" in the middle.
/// Geometry follows the 272 pt prototype.
struct CycleRing: View {
    @Environment(\.theme) private var theme
    var day: Int?
    var cycleLength: Int
    var periodDays: Int
    var isPeriodActive: Bool

    @State private var shimmer = false

    private var size: CGFloat { 272 }
    private var center: CGFloat { size / 2 }
    private var progress: Double {
        guard let day, cycleLength > 0 else { return 0 }
        return min(1, Double(day) / Double(cycleLength))
    }
    private var periodFraction: Double {
        guard cycleLength > 0 else { return 0 }
        return Double(min(periodDays, cycleLength)) / Double(cycleLength)
    }
    private var gradient: AngularGradient {
        AngularGradient(stops: theme.ringStops(progress: progress), center: .center,
                        startAngle: .degrees(-90), endAngle: .degrees(270))
    }

    var body: some View {
        ZStack {
            // Glow behind the ring; shimmers in the dark theme.
            Circle()
                .fill(gradient)
                .frame(width: size + 28, height: size + 28)
                .mask(Circle().strokeBorder(lineWidth: 37))
                .blur(radius: 22)
                .hueRotation(.degrees(theme.isDark && shimmer ? 28 : 0))
                .opacity(theme.glowOpacity)

            Circle()
                .fill(gradient)
                .frame(width: size, height: size)
                .mask(Circle().strokeBorder(lineWidth: 31))

            // Period segment: the first `periodDays` days of the cycle.
            Circle()
                .trim(from: 0, to: periodFraction)
                .stroke(theme.periodOverlay(active: isPeriodActive), lineWidth: 24)
                .rotationEffect(.degrees(-90))
                .frame(width: 248, height: 248)
                .shadow(color: isPeriodActive ? theme.periodGlow : .clear, radius: 8)

            ticks

            Circle()
                .fill(theme.cardBg)
                .overlay(
                    Circle()
                        .stroke(theme.shadow, lineWidth: 3)
                        .blur(radius: 1.5)
                        .offset(y: 1)
                        .mask(Circle())
                )
                .frame(width: size - 44, height: size - 44)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(day.map(String.init) ?? "–")
                    .font(.system(size: 64, weight: .regular))
                    .tracking(-2)
                    .foregroundStyle(theme.ink)
                Text("/\(cycleLength)")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.inkMuted)
            }
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(day.map { "День цикла \($0) из \(cycleLength)" } ?? "Цикл ещё не отмечен")
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.linear(duration: 3).repeatForever(autoreverses: true)) { shimmer = true }
        }
    }

    /// Short "dial notches" at the end of each period day.
    private var ticks: some View {
        Path { path in
            guard cycleLength > 0 else { return }
            for i in stride(from: 1, through: min(periodDays, cycleLength), by: 1) {
                let angle = Double(i) / Double(cycleLength) * 2 * .pi
                let sinA = CGFloat(sin(angle)), cosA = CGFloat(cos(angle))
                path.move(to: CGPoint(x: center + 111 * sinA, y: center - 111 * cosA))
                path.addLine(to: CGPoint(x: center + 137 * sinA, y: center - 137 * cosA))
            }
        }
        .stroke(theme.cardBg, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        .frame(width: size, height: size)
    }
}
