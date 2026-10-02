import SwiftUI

// MARK: - Direction in the environment
//
// The visual direction (Phase 1) flows through the SwiftUI environment, so a
// subtree can be rendered in any direction (the Direction Lab shows all three
// side by side) and the whole app re-themes live when the owner switches.

private struct LXDirectionKey: EnvironmentKey {
    nonisolated static let defaultValue: LXDirection = .aurora
}

extension EnvironmentValues {
    nonisolated var lxDirection: LXDirection {
        get { self[LXDirectionKey.self] }
        set { self[LXDirectionKey.self] = newValue }
    }

    /// Resolved theme for code that needs a concrete `Color` (shadows, tints, gradients).
    var lxTheme: LXTheme {
        LXTheme(direction: lxDirection, colorScheme: colorScheme, increasedContrast: colorSchemeContrast == .increased)
    }
}

extension View {
    /// Applies a visual direction to this subtree.
    func lxDirection(_ direction: LXDirection) -> some View {
        environment(\.lxDirection, direction)
    }
}

// MARK: - Theme value

struct LXTheme: Equatable, Sendable {
    var direction: LXDirection
    var colorScheme: ColorScheme
    var increasedContrast: Bool = false

    nonisolated func hex(_ role: LXColorRole) -> UInt32 {
        let pair = LXTokens.pair(role, direction)
        if increasedContrast {
            // Increase Contrast: lower-emphasis text steps up one level.
            switch role {
            case .textSecondary: return pick(LXTokens.pair(.textPrimary, direction))
            case .textTertiary: return pick(LXTokens.pair(.textSecondary, direction))
            default: break
            }
        }
        return pick(pair)
    }

    nonisolated func color(_ role: LXColorRole) -> Color {
        Color(lxHex: hex(role))
    }

    var orb: LXTokens.OrbPalette { LXTokens.orb(direction) }

    nonisolated private func pick(_ pair: LXTokens.Pair) -> UInt32 {
        colorScheme == .dark ? pair.dark : pair.light
    }
}

// MARK: - Colour as a ShapeStyle

/// A semantic colour that resolves against the environment (direction, light/dark,
/// Increase Contrast) at render time. Use it anywhere a `ShapeStyle` is accepted:
///
///     Text("640").foregroundStyle(.lx(.textPrimary))
///     RoundedRectangle(cornerRadius: LX.Radius.card).fill(.lx(.surface))
struct LXColor: ShapeStyle, Sendable {
    let role: LXColorRole
    var opacity: Double = 1

    nonisolated func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let theme = LXTheme(
            direction: environment.lxDirection,
            colorScheme: environment.colorScheme,
            increasedContrast: environment.colorSchemeContrast == .increased
        )
        let c = LXRGB(hex: theme.hex(role))
        return Color.Resolved(colorSpace: .sRGB, red: Float(c.r), green: Float(c.g), blue: Float(c.b), opacity: Float(opacity))
    }

    func opacity(_ value: Double) -> LXColor { LXColor(role: role, opacity: opacity * value) }
}

extension ShapeStyle where Self == LXColor {
    static func lx(_ role: LXColorRole) -> LXColor { LXColor(role: role) }
}

// MARK: - Hex helpers

struct LXRGB: Equatable, Sendable {
    let r: Double, g: Double, b: Double

    nonisolated init(hex: UInt32) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
    }

    /// WCAG 2.x relative luminance.
    nonisolated var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    /// WCAG 2.x contrast ratio, 1…21.
    nonisolated func contrast(with other: LXRGB) -> Double {
        let (hi, lo) = luminance > other.luminance ? (luminance, other.luminance) : (other.luminance, luminance)
        return (hi + 0.05) / (lo + 0.05)
    }
}

extension Color {
    nonisolated init(lxHex hex: UInt32, opacity: Double = 1) {
        let c = LXRGB(hex: hex)
        self.init(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: opacity)
    }
}

// MARK: - Namespace for layout tokens

enum LX {
    typealias Space = LXTokens.Space
    typealias Radius = LXTokens.Radius
}
