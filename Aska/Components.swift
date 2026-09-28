import SwiftUI

// MARK: - Icons (paths from the hand-off SVGs, drawn in their own viewBox)

/// A shape drawn in a square `viewBox` and scaled to the frame.
struct ViewBoxShape: Shape {
    var viewBox: CGFloat
    var draw: @Sendable (inout Path) -> Void

    func path(in rect: CGRect) -> Path {
        var path = Path()
        draw(&path)
        let scale = min(rect.width, rect.height) / viewBox
        return path.applying(CGAffineTransform(scaleX: scale, y: scale))
            .offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

enum Icons {
    /// Undo arrow, viewBox 20.
    static let undoHead = ViewBoxShape(viewBox: 20) { p in
        p.move(to: .init(x: 6, y: 4)); p.addLine(to: .init(x: 2, y: 8)); p.addLine(to: .init(x: 6, y: 12))
    }
    static let undoTail = ViewBoxShape(viewBox: 20) { p in
        p.move(to: .init(x: 2, y: 8)); p.addLine(to: .init(x: 12, y: 8))
        p.addCurve(to: .init(x: 17, y: 13), control1: .init(x: 15, y: 8), control2: .init(x: 17, y: 10))
        p.addCurve(to: .init(x: 14, y: 17), control1: .init(x: 17, y: 15), control2: .init(x: 15.5, y: 16.5))
    }
    /// Droplet, viewBox 26.
    static let droplet = ViewBoxShape(viewBox: 26) { p in
        p.move(to: .init(x: 13, y: 2))
        p.addCurve(to: .init(x: 5, y: 17.5), control1: .init(x: 13, y: 2), control2: .init(x: 5, y: 12.5))
        p.addCurve(to: .init(x: 13, y: 24.5), control1: .init(x: 5, y: 22), control2: .init(x: 8.5, y: 24.5))
        p.addCurve(to: .init(x: 21, y: 17.5), control1: .init(x: 17.5, y: 24.5), control2: .init(x: 21, y: 22))
        p.addCurve(to: .init(x: 13, y: 2), control1: .init(x: 21, y: 12.5), control2: .init(x: 13, y: 2))
        p.closeSubpath()
    }
    /// Chevrons, viewBox 14.
    static let chevronLeft = ViewBoxShape(viewBox: 14) { p in
        p.move(to: .init(x: 9, y: 2)); p.addLine(to: .init(x: 3, y: 7)); p.addLine(to: .init(x: 9, y: 12))
    }
    static let chevronRight = ViewBoxShape(viewBox: 14) { p in
        p.move(to: .init(x: 5, y: 2)); p.addLine(to: .init(x: 11, y: 7)); p.addLine(to: .init(x: 5, y: 12))
    }
    /// Cross and plus, viewBox 18.
    static let cross = ViewBoxShape(viewBox: 18) { p in
        p.move(to: .init(x: 4, y: 4)); p.addLine(to: .init(x: 14, y: 14))
        p.move(to: .init(x: 14, y: 4)); p.addLine(to: .init(x: 4, y: 14))
    }
    static let plus = ViewBoxShape(viewBox: 18) { p in
        p.move(to: .init(x: 9, y: 3)); p.addLine(to: .init(x: 9, y: 15))
        p.move(to: .init(x: 3, y: 9)); p.addLine(to: .init(x: 15, y: 9))
    }
    /// Person silhouette for the profile tab, viewBox 26.
    static let personHead = ViewBoxShape(viewBox: 26) { p in
        p.addEllipse(in: CGRect(x: 8.5, y: 4.5, width: 9, height: 9))
    }
    static let personBody = ViewBoxShape(viewBox: 26) { p in
        p.move(to: .init(x: 4, y: 22))
        p.addCurve(to: .init(x: 13, y: 14), control1: .init(x: 4, y: 17), control2: .init(x: 8, y: 14))
        p.addCurve(to: .init(x: 22, y: 22), control1: .init(x: 18, y: 14), control2: .init(x: 22, y: 17))
    }
}

private let roundStroke = StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)

struct UndoIcon: View {
    var color: Color
    var body: some View {
        ZStack {
            Icons.undoHead.stroke(color, style: roundStroke)
            Icons.undoTail.stroke(color, style: roundStroke)
        }
        .frame(width: 20, height: 20)
    }
}

struct StopIcon: View {
    var color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).stroke(color, lineWidth: 2.2).frame(width: 18, height: 18)
            RoundedRectangle(cornerRadius: 1.5).fill(color).frame(width: 8, height: 8)
        }
        .frame(width: 26, height: 26)
    }
}

// MARK: - Buttons

/// Round button without the system highlight, as in the prototype.
struct CircleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Circle())
    }
}

// MARK: - Tab bar

enum AppScreen {
    case today, calendar, profile
}

struct TabBar: View {
    @Environment(\.theme) private var theme
    var selected: AppScreen
    var onSelect: (AppScreen) -> Void

    var body: some View {
        HStack(spacing: 56) {
            Button { onSelect(.today) } label: {
                Circle()
                    .stroke(selected == .profile ? theme.inkFaint : theme.ink, lineWidth: 2.4)
                    .frame(width: 20, height: 20)
                    .frame(width: 26, height: 26)
            }
            .accessibilityLabel("Сегодня")
            Button { onSelect(.profile) } label: {
                let color = selected == .profile ? theme.ink : theme.inkFaint
                ZStack {
                    Icons.personHead.stroke(color, lineWidth: 2.2)
                    Icons.personBody.stroke(color, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
                .frame(width: 26, height: 26)
            }
            .accessibilityLabel("Профиль")
        }
        .buttonStyle(CircleButtonStyle())
        .padding(.bottom, 14)
    }
}

// MARK: - Profile controls

/// "– 28 +" stepper with 30 pt round buttons.
struct RoundStepper: View {
    @Environment(\.theme) private var theme
    var value: Int
    var range: ClosedRange<Int>
    var valueWidth: CGFloat = 20
    var onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 14) {
            stepButton("–", enabled: value > range.lowerBound) { onChange(value - 1) }
                .accessibilityLabel("Меньше")
            Text(String(value))
                .font(.system(size: 17))
                .monospacedDigit()
                .foregroundStyle(theme.ink)
                .frame(width: valueWidth)
            stepButton("+", enabled: value < range.upperBound) { onChange(value + 1) }
                .accessibilityLabel("Больше")
        }
    }

    private func stepButton(_ title: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18))
                .foregroundStyle(theme.ink)
                .frame(width: 30, height: 30)
                .background(theme.chipBg, in: Circle())
        }
        .buttonStyle(CircleButtonStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

/// 48×28 pill switch in the accent colour.
struct PillSwitch: View {
    @Environment(\.theme) private var theme
    var isOn: Bool
    var onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? theme.accent : theme.switchOff)
                Circle()
                    .fill(.white)
                    .frame(width: 24, height: 24)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .padding(2)
            }
            .frame(width: 48, height: 28)
            .animation(.easeInOut(duration: 0.15), value: isOn)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Rounded card with 1 pt dividers between rows.
struct CardGroup<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(theme.cardBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct CardRow<Trailing: View>: View {
    @Environment(\.theme) private var theme
    var title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(theme.ink)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
    }
}

struct CardDivider: View {
    @Environment(\.theme) private var theme
    var body: some View {
        theme.divider.frame(height: 1).padding(.horizontal, 18)
    }
}
