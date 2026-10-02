import SwiftUI

// MARK: - Elevation (Phase 2 §5: flat, raised, floating — never more than three on screen)

enum LXElevation: Sendable { case flat, raised, floating }

/// Snapshot renders cannot sample the backdrop, so glass is approximated with a
/// translucent raised surface when this flag is set (Direction Lab exports, tests).
private struct LXSnapshotModeKey: EnvironmentKey { nonisolated static let defaultValue = false }

extension EnvironmentValues {
    nonisolated var lxSnapshotMode: Bool {
        get { self[LXSnapshotModeKey.self] }
        set { self[LXSnapshotModeKey.self] = newValue }
    }
}

// MARK: - Card (solid surface, never glass)

private struct LXCardModifier: ViewModifier {
    var radius: CGFloat
    var role: LXColorRole
    var padding: CGFloat?
    @Environment(\.lxTheme) private var theme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        let dark = theme.colorScheme == .dark
        content
            .padding(padding ?? LX.Space.s400)
            .background(shape.fill(.lx(role)))
            .overlay {
                // Obsidian: fine champagne hairline. Others: a quiet separator edge.
                shape.strokeBorder(theme.direction == .obsidian && dark ? theme.color(.accentPrimary).opacity(0.22) : theme.color(.separator).opacity(dark ? 0.9 : 0.7),
                                   lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(dark ? 0.0 : (theme.direction == .porcelain ? 0.06 : 0.05)), radius: 12, x: 0, y: 6)
    }
}

extension View {
    /// Raised content card on a solid surface (Phase 2 §6: cards are never glass).
    func lxCard(radius: CGFloat = LX.Radius.card, role: LXColorRole = .surface, padding: CGFloat? = nil) -> some View {
        modifier(LXCardModifier(radius: radius, role: role, padding: padding))
    }
}

// MARK: - Glass (navigation and controls layer only)

private struct LXGlassModifier<S: Shape>: ViewModifier {
    var shape: S
    var interactive: Bool
    @Environment(\.lxTheme) private var theme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.lxSnapshotMode) private var snapshot

    func body(content: Content) -> some View {
        if reduceTransparency || snapshot {
            // Reduce Transparency → solid raised surface with a hairline (Phase 2 §6).
            content
                .background(shape.fill(.lx(.surfaceRaised).opacity(snapshot && !reduceTransparency ? 0.92 : 1)))
                .overlay(shape.stroke(.lx(.separator), lineWidth: 0.5))
                .shadow(color: .black.opacity(theme.colorScheme == .dark ? 0.35 : 0.10), radius: 16, x: 0, y: 8)
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content
                .background(shape.fill(.ultraThinMaterial))
                .overlay(shape.stroke(.white.opacity(theme.colorScheme == .dark ? 0.14 : 0.5), lineWidth: 0.5))
                .shadow(color: .black.opacity(theme.colorScheme == .dark ? 0.35 : 0.10), radius: 16, x: 0, y: 8)
        }
    }
}

extension View {
    /// Liquid Glass on iOS 26, material before that, solid with Reduce Transparency.
    func lxGlass<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        modifier(LXGlassModifier(shape: shape, interactive: interactive))
    }

    func lxGlass(interactive: Bool = false) -> some View {
        lxGlass(in: Capsule(), interactive: interactive)
    }
}

// MARK: - Screen background

/// One background per screen. Only the hero area may carry a glow (Phase 2 §3.1).
struct LXScreenBackground: View {
    var heroGlow = true
    @Environment(\.lxTheme) private var theme

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(.lx(.background))
            if heroGlow {
                switch theme.direction {
                case .aurora:
                    ZStack {
                        Ellipse().fill(theme.color(.heroGlowA)).frame(width: 380, height: 300).offset(x: -90, y: 60)
                        Ellipse().fill(theme.color(.heroGlowB)).frame(width: 360, height: 280).offset(x: 110, y: 130)
                    }
                    .blur(radius: 80)
                    .opacity(0.9)
                case .obsidian:
                    RadialGradient(colors: [theme.color(.heroGlowA), .clear], center: .top, startRadius: 10, endRadius: 420)
                        .frame(height: 520)
                case .porcelain:
                    LinearGradient(colors: [theme.color(.heroGlowA), theme.color(.background)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 460)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
