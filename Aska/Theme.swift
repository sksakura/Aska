import SwiftUI

/// Converts an OKLCH colour (the design hand-off's colour space) to sRGB components 0…1.
/// `hue` is in degrees. Out-of-gamut values are clipped.
func oklchToSRGB(_ lightness: Double, _ chroma: Double, _ hue: Double) -> (red: Double, green: Double, blue: Double) {
    let h = hue * .pi / 180
    let a = chroma * cos(h)
    let b = chroma * sin(h)

    let l = pow(lightness + 0.3963377774 * a + 0.2158037573 * b, 3)
    let m = pow(lightness - 0.1055613458 * a - 0.0638541728 * b, 3)
    let s = pow(lightness - 0.0894841775 * a - 1.2914855480 * b, 3)

    let linear = (
        4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
        -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
        -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    )
    func encode(_ x: Double) -> Double {
        let clipped = min(max(x, 0), 1)
        return clipped <= 0.0031308 ? 12.92 * clipped : 1.055 * pow(clipped, 1 / 2.4) - 0.055
    }
    return (encode(linear.0), encode(linear.1), encode(linear.2))
}

extension Color {
    init(oklch lightness: Double, _ chroma: Double, _ hue: Double, opacity: Double = 1) {
        let rgb = oklchToSRGB(lightness, chroma, hue)
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue, opacity: opacity)
    }
}

/// Design tokens from the hand-off (`design_handoff_cycle_tracker`), built from one hue.
/// The "warm" palette (hue 40) is the default; light and dark follow the system appearance.
struct Theme {
    var isDark: Bool
    var hue: Double = 40

    /// The warm palette uses a slightly redder hue for its light-theme accent.
    private var lightAccentHue: Double { hue == 40 ? 25 : hue }

    var bg: Color { isDark ? Color(oklch: 0.17, 0.045, hue) : Color(oklch: 0.975, 0.012, hue) }
    var cardBg: Color { isDark ? Color(oklch: 0.24, 0.05, hue) : Color(oklch: 0.99, 0.005, hue) }
    var chipBg: Color { isDark ? Color(oklch: 0.3, 0.05, hue) : Color(oklch: 0.94, 0.01, hue) }
    var divider: Color { isDark ? Color(oklch: 0.32, 0.045, hue) : Color(oklch: 0.93, 0.01, hue) }
    var shadow: Color { isDark ? Color(oklch: 0.05, 0.01, hue, opacity: 0.6) : Color(oklch: 0.85, 0.02, hue, opacity: 0.4) }
    var ink: Color { isDark ? Color(oklch: 0.94, 0.01, hue) : Color(oklch: 0.3, 0.02, hue) }
    var inkMuted: Color { isDark ? Color(oklch: 0.65, 0.02, hue) : Color(oklch: 0.62, 0.02, hue) }
    var inkFaint: Color { isDark ? Color(oklch: 0.55, 0.02, hue) : Color(oklch: 0.7, 0.02, hue) }

    /// Main accent: filled calendar days, the droplet, the stop icon, the reminders switch.
    var accent: Color { isDark ? Color(oklch: 0.75, 0.19, hue) : Color(oklch: 0.72, 0.15, lightAccentHue) }
    /// The not-yet-passed part of the cycle ring.
    var ringDim: Color { isDark ? Color(oklch: 0.26, 0.02, hue) : Color(oklch: 0.9, 0.02, hue) }
    /// Background of the big start/stop button.
    var actionButtonBg: Color { isDark ? Color(oklch: 0.28, 0.03, hue) : Color(oklch: 0.94, 0.03, hue) }
    /// Text on a filled (fact) calendar day.
    var onAccent: Color { isDark ? Color(oklch: 0.15, 0.02, 0) : .white }
    var deleteMark: Color { Color(oklch: 0.55, 0.18, 25) }
    var switchOff: Color { isDark ? Color(oklch: 0.35, 0.01, 45) : Color(oklch: 0.88, 0.01, 45) }

    /// Period segment over the ring: bright while the period is going, pale otherwise.
    func periodOverlay(active: Bool) -> Color {
        if active { return Color(oklch: 0.6, 0.2, hue) }
        return isDark ? Color(oklch: 0.4, 0.05, hue) : Color(oklch: 0.9, 0.05, hue)
    }
    var periodGlow: Color { Color(oklch: 0.6, 0.2, hue, opacity: 0.7) }

    /// Gradient stops for the ring, clockwise from the top; `progress` is the passed share 0…1.
    /// Dark theme: a multi-colour shimmer over the passed part.
    func ringStops(progress: Double) -> [Gradient.Stop] {
        let p = min(max(progress, 0), 1)
        let fade = min(1, p + 8.0 / 360)
        if isDark {
            return [
                .init(color: Color(oklch: 0.75, 0.19, hue), location: 0),
                .init(color: Color(oklch: 0.78, 0.2, hue + 40), location: p * 0.4),
                .init(color: Color(oklch: 0.72, 0.2, hue - 40), location: p * 0.8),
                .init(color: Color(oklch: 0.75, 0.19, hue), location: p),
                .init(color: ringDim, location: fade),
                .init(color: ringDim, location: 1),
            ]
        }
        return [
            .init(color: accent, location: 0),
            .init(color: accent, location: p),
            .init(color: ringDim, location: fade),
            .init(color: ringDim, location: 1),
        ]
    }

    var glowOpacity: Double { isDark ? 0.85 : 0.55 }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(isDark: false)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Picks the theme from the system appearance.
struct ThemedRoot<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        content.environment(\.theme, Theme(isDark: colorScheme == .dark))
    }
}
