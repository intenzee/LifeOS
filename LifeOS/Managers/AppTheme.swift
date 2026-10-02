import SwiftUI

// MARK: - App Theme Selection
enum AppTheme: String, CaseIterable, Codable {
    case system
    case light
    case dark

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

// MARK: - Design System
enum DesignSystem {
    // MARK: Spacing
    /// A standardized spacing scale for consistent padding and margins across the app.
    enum Spacing {
        /// 4pt
        static let xxSmall: CGFloat = 4
        /// 8pt
        static let xSmall: CGFloat = 8
        /// 12pt
        static let small: CGFloat = 12
        /// 16pt (Standard default margin)
        static let medium: CGFloat = 16
        /// 24pt
        static let large: CGFloat = 24
        /// 32pt
        static let xLarge: CGFloat = 32
        /// 48pt
        static let xxLarge: CGFloat = 48
    }
    
    // MARK: Typography
    /// Structural typographic scale. Relies on SwiftUI's Dynamic Type for accessibility.
    enum Typography {
        /// Large titles for main screens (Dynamic: .largeTitle rounded)
        static let heroTitle: Font = .system(.largeTitle, design: .rounded).weight(.bold)
        /// Standard H1 (Dynamic: .title)
        static let h1: Font = .title.weight(.bold)
        /// Standard H2 (Dynamic: .title2)
        static let h2: Font = .title2.weight(.semibold)
        /// Standard H3 (Dynamic: .title3)
        static let h3: Font = .title3.weight(.medium)
        /// Standard body copy (Dynamic: .body)
        static let body: Font = .body
        /// Secondary body text (Dynamic: .callout)
        static let callout: Font = .callout
        /// Helper/metadata text (Dynamic: .footnote)
        static let caption: Font = .footnote
    }
}

// MARK: - Colors
struct ThemePalette {
    let colorScheme: ColorScheme

    var screenBackground: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.09, blue: 0.13) : Color(uiColor: .systemGroupedBackground) // #141721
    }

    var surface: Color {
        colorScheme == .dark ? Color(red: 0.13, green: 0.14, blue: 0.18) : Color(uiColor: .secondarySystemBackground) // #21242E
    }

    var elevatedSurface: Color {
        colorScheme == .dark ? Color(red: 0.16, green: 0.18, blue: 0.22) : Color(uiColor: .tertiarySystemBackground) // #292E38
    }

    var textPrimary: Color {
        colorScheme == .dark ? .white : .primary
    }

    var textSecondary: Color {
        colorScheme == .dark ? Color(red: 0.65, green: 0.68, blue: 0.73) : .secondary
    }

    var inputSurface: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.13, blue: 0.16) : Color(uiColor: .secondarySystemBackground)
    }

    var overlay: Color {
        colorScheme == .dark ? Color.black.opacity(0.7) : Color.black.opacity(0.25)
    }

    var primaryAccent: Color {
        Color(red: 0.44, green: 0.93, blue: 0.78) // #70EDC6 Mint Cyan
    }

    /// UIColor equivalent of `primaryAccent` for UIKit components (e.g. tab bar).
    static let primaryAccentUIColor = UIColor(red: 0.44, green: 0.93, blue: 0.78, alpha: 1.0)

    /// Static SwiftUI Color for views that don't have access to a palette instance.
    static let accent = Color(red: 0.44, green: 0.93, blue: 0.78)

    /// Secondary accent used for gradients and 3D depth (soft violet).
    static let accentSecondary = Color(red: 0.55, green: 0.60, blue: 0.98)
}

// MARK: - Liquid Glass Design System
//
// A small set of reusable materials that give the whole app one cohesive look:
// frosted/liquid glass surfaces, soft layered shadows for 3D depth, and a subtle
// top-edge highlight so cards feel lit from above. Everything is theme-aware —
// `.ultraThinMaterial` adapts to light/dark automatically.

/// The signature frosted-glass surface. Layered translucent material + gradient
/// hairline stroke (bright at the top, fading down) + two shadows for real depth.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = 24
    var strokeOpacity: Double = 0.5
    var tint: Color = .clear
    var elevation: CGFloat = 1

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(tint == .clear ? 0 : 0.14))
                    // Soft top-down sheen for a liquid, glossy read.
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.white.opacity(0.12), Color.clear],
                                startPoint: .top,
                                endPoint: .center
                            )
                        )
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.55 * strokeOpacity),
                                Color.white.opacity(0.08 * strokeOpacity),
                                Color.white.opacity(0.02 * strokeOpacity)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: Color.black.opacity(0.30), radius: 18 * elevation, x: 0, y: 12 * elevation)
            .shadow(color: Color.black.opacity(0.12), radius: 3, x: 0, y: 1)
    }
}

/// A vibrant, blurred aurora backdrop that gives glass surfaces something rich to
/// refract. Sits behind screen content and adapts to the color scheme.
struct AuroraBackground: View {
    var colorScheme: ColorScheme

    var body: some View {
        let palette = ThemePalette(colorScheme: colorScheme)
        ZStack {
            palette.screenBackground.ignoresSafeArea()

            Circle()
                .fill(ThemePalette.accent.opacity(colorScheme == .dark ? 0.35 : 0.22))
                .frame(width: 340, height: 340)
                .blur(radius: 120)
                .offset(x: -130, y: -260)

            Circle()
                .fill(ThemePalette.accentSecondary.opacity(colorScheme == .dark ? 0.32 : 0.20))
                .frame(width: 360, height: 360)
                .blur(radius: 130)
                .offset(x: 150, y: 320)

            Circle()
                .fill(ThemePalette.accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
                .frame(width: 260, height: 260)
                .blur(radius: 110)
                .offset(x: 160, y: -120)
        }
        .ignoresSafeArea()
    }
}

extension View {
    /// Wraps the view in the signature liquid-glass surface.
    func glassCard(cornerRadius: CGFloat = 24, tint: Color = .clear, elevation: CGFloat = 1) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, elevation: elevation))
    }

    /// Subtle press-scale for tappable glass — adds tactile, 3D responsiveness.
    func pressableGlass() -> some View {
        buttonStyle(PressableGlassButtonStyle())
    }
}

struct PressableGlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}