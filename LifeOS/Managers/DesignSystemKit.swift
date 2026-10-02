import SwiftUI

// MARK: - Radius scale
//
// One corner-radius scale for the whole app so every card, tile, pill and button
// share the same rounding language instead of ad-hoc 12/18/26/28/32 values.
extension DesignSystem {
    enum Radius {
        static let sm: CGFloat = 12    // chips, small inputs
        static let md: CGFloat = 16    // tiles
        static let lg: CGFloat = 22    // cards
        static let xl: CGFloat = 28    // hero cards / sheets
        static let pill: CGFloat = 999
    }
}

// MARK: - Semantic status colors
//
// Theme-aware status colors so screens stop hardcoding `.orange` / `.blue` / `.white`.
// These read against both the dark aurora and light grouped backgrounds.
extension ThemePalette {
    var success: Color { primaryAccent }
    var warning: Color { colorScheme == .dark ? Color(red: 1.0, green: 0.72, blue: 0.35) : Color(red: 0.90, green: 0.55, blue: 0.10) }
    var info: Color { colorScheme == .dark ? Color(red: 0.55, green: 0.66, blue: 0.99) : Color(red: 0.28, green: 0.42, blue: 0.92) }
    var danger: Color { colorScheme == .dark ? Color(red: 1.0, green: 0.45, blue: 0.45) : Color(red: 0.85, green: 0.25, blue: 0.25) }

    /// Neutral track behind progress rings/bars.
    var track: Color { colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08) }

    /// Signature accent gradient used on primary actions and highlights.
    var accentGradient: LinearGradient {
        LinearGradient(colors: [ThemePalette.accent, ThemePalette.accentSecondary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Palette via Environment
//
// Avoids re-instantiating `ThemePalette(colorScheme:)` in every view and gives a
// single source of truth. Views can read `@Environment(\.palette)`.
private struct PaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette(colorScheme: .dark)
}

extension EnvironmentValues {
    var palette: ThemePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

extension View {
    /// Injects a palette derived from the current color scheme into the environment.
    func providePalette(_ colorScheme: ColorScheme) -> some View {
        environment(\.palette, ThemePalette(colorScheme: colorScheme))
    }
}

// MARK: - Reusable components

/// A consistent section heading used above card groups.
struct SectionHeader: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }
    let title: String
    var action: (() -> Void)?
    var actionLabel: String?

    init(_ title: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.headline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            if let action, let actionLabel {
                Button(actionLabel, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.primaryAccent)
            }
        }
    }
}

/// A circular progress gauge. Replaces the several bespoke rings across the app.
struct RingGauge<Center: View>: View {
    var progress: Double
    var lineWidth: CGFloat = 12
    var color: Color
    var track: Color
    var glow: Bool = true
    @ViewBuilder var center: () -> Center

    var body: some View {
        let clamped = progress.isFinite ? min(max(progress, 0), 1) : 0
        ZStack {
            Circle().stroke(track, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: glow ? color.opacity(0.45) : .clear, radius: glow ? 10 : 0)
                .animation(.easeOut(duration: 0.4), value: clamped)
            center()
        }
    }
}

/// A thin, rounded progress bar with a track — used inside tiles.
struct LinearProgress: View {
    var value: Double
    var tint: Color
    var track: Color
    var height: CGFloat = 6

    var body: some View {
        let clamped = value.isFinite ? min(max(value, 0), 1) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(tint)
                    .frame(width: max(0, geo.size.width * clamped))
                    .animation(.easeOut(duration: 0.35), value: clamped)
            }
        }
        .frame(height: height)
    }
}

/// The unified metric tile (icon + label + value, optional progress). Replaces the
/// per-screen mini-card implementations so every tile matches.
struct MetricTile: View {
    @Environment(\.colorScheme) private var colorScheme
    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }
    let icon: String
    let title: String
    let value: String
    var tint: Color
    var progress: Double? = nil
    var elevation: CGFloat = 0.4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tint)
                Text(title)
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.system(.headline, design: .rounded))
                .foregroundColor(palette.textPrimary)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: false, vertical: true)

            if let progress {
                LinearProgress(value: progress, tint: tint, track: palette.track, height: 5)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .glassCard(cornerRadius: DesignSystem.Radius.md, elevation: elevation)
    }
}

// MARK: - Button styles

/// Primary call-to-action: accent gradient, press-scale, legible on-accent text.
/// (ButtonStyle isn't a View, so `@Environment` won't resolve here — the accent
/// gradient is theme-independent, so we use the static accent directly.)
struct PrimaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.bold))
            .foregroundColor(.black.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                LinearGradient(colors: [ThemePalette.accent, ThemePalette.accentSecondary],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Secondary action: translucent glass fill; `.primary` adapts to light/dark.
struct SecondaryActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial,
                        in: RoundedRectangle(cornerRadius: DesignSystem.Radius.md, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryActionButtonStyle {
    static var primaryAction: PrimaryActionButtonStyle { .init() }
}
extension ButtonStyle where Self == SecondaryActionButtonStyle {
    static var secondaryAction: SecondaryActionButtonStyle { .init() }
}
