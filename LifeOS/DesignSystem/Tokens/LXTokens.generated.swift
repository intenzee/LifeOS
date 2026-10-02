// GENERATED FILE — DO NOT EDIT.
// Source: design/tokens/*.json · Generator: design/tools/gen_tokens.py
// Regenerate with: python3 design/tools/gen_tokens.py

import SwiftUI

/// The three Phase 1 visual directions. The owner picks one at gate D1;
/// all three stay selectable in the Direction Lab until then.
enum LXDirection: String, CaseIterable, Codable, Identifiable, Sendable {
    case obsidian
    case porcelain
    case aurora

    nonisolated var id: String { rawValue }

    nonisolated var displayName: String {
        switch self {
        case .obsidian: return "Obsidian & Champagne"
        case .porcelain: return "Porcelain"
        case .aurora: return "Aurora Glass"
        }
    }

    nonisolated var mood: String {
        switch self {
        case .obsidian: return "A private members' club at night. Near-black, warm metallic accents, serif numerals."
        case .porcelain: return "A luxury editorial magazine in daylight. Warm ivory, ink, one deep emerald."
        case .aurora: return "Deep space and light. Today's mint and violet, made luminous and rare."
        }
    }

    /// Font design for numbers and display type.
    nonisolated var numericDesign: Font.Design {
        switch self {
        case .obsidian: return .serif
        case .porcelain: return .serif
        case .aurora: return .rounded
        }
    }

    nonisolated var displayDesign: Font.Design {
        switch self {
        case .obsidian: return .serif
        case .porcelain: return .serif
        case .aurora: return .rounded
        }
    }

    /// Multiplier on spring bounce: 0 = weighty and precise, 1 = lightly springy.
    nonisolated var motionBounceScale: Double {
        switch self {
        case .obsidian: return 0.0
        case .porcelain: return 0.5
        case .aurora: return 1.0
        }
    }

    /// Where Liquid Glass is allowed: controls only, the tab bar, or every floating layer.
    nonisolated var glassUsage: LXGlassUsage {
        switch self {
        case .obsidian: return .controls
        case .porcelain: return .tabBar
        case .aurora: return .everywhere
        }
    }
}

enum LXGlassUsage: String, Sendable { case controls, tabBar, everywhere }

/// Semantic colour roles (Phase 2 §3). Feature code names a role, never a hex value.
enum LXColorRole: String, CaseIterable, Sendable {
    case background
    case surface
    case surfaceRaised
    case textPrimary
    case textSecondary
    case textTertiary
    case separator
    case accentPrimary
    case accentSecondary
    case onAccent
    case heroGlowA
    case heroGlowB
    case dataEnergy
    case dataActivity
    case dataProtein
    case dataCarbs
    case dataFat
    case dataWater
    case dataSleep
    case dataWeight
    case statusOnTrack
    case statusAttention
    case statusOver
    case statusCritical
    case statusInfo
}

enum LXTokens {
    /// sRGB hex values for one role: (dark, light).
    struct Pair: Sendable, Equatable { let dark: UInt32; let light: UInt32 }

    nonisolated static func pair(_ role: LXColorRole, _ direction: LXDirection) -> Pair {
        switch direction {
        case .obsidian:
            switch role {
            case .background: return Pair(dark: 0x0B0B0D, light: 0xF5F2EC)
            case .surface: return Pair(dark: 0x16161A, light: 0xFFFFFF)
            case .surfaceRaised: return Pair(dark: 0x1F1F24, light: 0xFBF9F5)
            case .textPrimary: return Pair(dark: 0xF4F1EA, light: 0x16140F)
            case .textSecondary: return Pair(dark: 0xA7A29A, light: 0x5F5A52)
            case .textTertiary: return Pair(dark: 0x77726A, light: 0x8A847A)
            case .separator: return Pair(dark: 0x2C2B30, light: 0xE2DDD3)
            case .accentPrimary: return Pair(dark: 0xD8C3A5, light: 0x7A5F33)
            case .accentSecondary: return Pair(dark: 0xB89A6A, light: 0x8C6D3F)
            case .onAccent: return Pair(dark: 0x0B0B0D, light: 0xFFFFFF)
            case .heroGlowA: return Pair(dark: 0x3A2F20, light: 0xEFE3CC)
            case .heroGlowB: return Pair(dark: 0x1A1714, light: 0xF7F1E6)
            case .dataEnergy: return Pair(dark: 0xF2A65A, light: 0xA0560B)
            case .dataActivity: return Pair(dark: 0x5FD6C2, light: 0x0F7468)
            case .dataProtein: return Pair(dark: 0xF08A8A, light: 0xB03B48)
            case .dataCarbs: return Pair(dark: 0xE3D3A8, light: 0x7F6227)
            case .dataFat: return Pair(dark: 0xB67CDE, light: 0x541F7A)
            case .dataWater: return Pair(dark: 0x8BD6EE, light: 0x1750A1)
            case .dataSleep: return Pair(dark: 0x7C86F7, light: 0x4A4FC4)
            case .dataWeight: return Pair(dark: 0xB4AEA7, light: 0x322F2A)
            case .statusOnTrack: return Pair(dark: 0x8CC9A8, light: 0x2B7350)
            case .statusAttention: return Pair(dark: 0xE6B566, light: 0x8F5E0E)
            case .statusOver: return Pair(dark: 0xD98C5F, light: 0xA0491F)
            case .statusCritical: return Pair(dark: 0xF0716A, light: 0xBF3328)
            case .statusInfo: return Pair(dark: 0x8FB3D9, light: 0x2B5F91)
            }
        case .porcelain:
            switch role {
            case .background: return Pair(dark: 0x12110F, light: 0xF6F3EE)
            case .surface: return Pair(dark: 0x1C1B18, light: 0xFFFFFF)
            case .surfaceRaised: return Pair(dark: 0x262420, light: 0xFFFFFF)
            case .textPrimary: return Pair(dark: 0xF3EFE7, light: 0x15140F)
            case .textSecondary: return Pair(dark: 0xABA59B, light: 0x6E6A63)
            case .textTertiary: return Pair(dark: 0x7A756C, light: 0x8F8A82)
            case .separator: return Pair(dark: 0x302E2A, light: 0xE4DFD6)
            case .accentPrimary: return Pair(dark: 0x6FC2A6, light: 0x0F5C4A)
            case .accentSecondary: return Pair(dark: 0xC9A66B, light: 0x8C6D3F)
            case .onAccent: return Pair(dark: 0x0B1A15, light: 0xFFFFFF)
            case .heroGlowA: return Pair(dark: 0x1E2A25, light: 0xE7EFE9)
            case .heroGlowB: return Pair(dark: 0x171512, light: 0xFBF8F2)
            case .dataEnergy: return Pair(dark: 0xF2A65A, light: 0xA0560B)
            case .dataActivity: return Pair(dark: 0x5FD6C2, light: 0x0F7468)
            case .dataProtein: return Pair(dark: 0xF08A8A, light: 0xB03B48)
            case .dataCarbs: return Pair(dark: 0xE3D3A8, light: 0x7F6227)
            case .dataFat: return Pair(dark: 0xB67CDE, light: 0x541F7A)
            case .dataWater: return Pair(dark: 0x8BD6EE, light: 0x1750A1)
            case .dataSleep: return Pair(dark: 0x7C86F7, light: 0x4A4FC4)
            case .dataWeight: return Pair(dark: 0xB4AEA7, light: 0x322F2A)
            case .statusOnTrack: return Pair(dark: 0x8CC9A8, light: 0x2B7350)
            case .statusAttention: return Pair(dark: 0xE6B566, light: 0x8F5E0E)
            case .statusOver: return Pair(dark: 0xD98C5F, light: 0xA0491F)
            case .statusCritical: return Pair(dark: 0xF0716A, light: 0xBF3328)
            case .statusInfo: return Pair(dark: 0x8FB3D9, light: 0x2B5F91)
            }
        case .aurora:
            switch role {
            case .background: return Pair(dark: 0x07090F, light: 0xF2F4F9)
            case .surface: return Pair(dark: 0x10141E, light: 0xFFFFFF)
            case .surfaceRaised: return Pair(dark: 0x182030, light: 0xFFFFFF)
            case .textPrimary: return Pair(dark: 0xEEF2FF, light: 0x0E1220)
            case .textSecondary: return Pair(dark: 0x9AA3B5, light: 0x535B6E)
            case .textTertiary: return Pair(dark: 0x687185, light: 0x80889A)
            case .separator: return Pair(dark: 0x1E2433, light: 0xDCE0EA)
            case .accentPrimary: return Pair(dark: 0x70EDC6, light: 0x0B7A5E)
            case .accentSecondary: return Pair(dark: 0x8C99FA, light: 0x4B55C9)
            case .onAccent: return Pair(dark: 0x04140F, light: 0xFFFFFF)
            case .heroGlowA: return Pair(dark: 0x0F3A33, light: 0xDDF5EE)
            case .heroGlowB: return Pair(dark: 0x1C1F4A, light: 0xE3E6FB)
            case .dataEnergy: return Pair(dark: 0xF2A65A, light: 0xA0560B)
            case .dataActivity: return Pair(dark: 0x5FD6C2, light: 0x0F7468)
            case .dataProtein: return Pair(dark: 0xF08A8A, light: 0xB03B48)
            case .dataCarbs: return Pair(dark: 0xE3D3A8, light: 0x7F6227)
            case .dataFat: return Pair(dark: 0xB67CDE, light: 0x541F7A)
            case .dataWater: return Pair(dark: 0x8BD6EE, light: 0x1750A1)
            case .dataSleep: return Pair(dark: 0x7C86F7, light: 0x4A4FC4)
            case .dataWeight: return Pair(dark: 0xB4AEA7, light: 0x322F2A)
            case .statusOnTrack: return Pair(dark: 0x8CC9A8, light: 0x2B7350)
            case .statusAttention: return Pair(dark: 0xE6B566, light: 0x8F5E0E)
            case .statusOver: return Pair(dark: 0xD98C5F, light: 0xA0491F)
            case .statusCritical: return Pair(dark: 0xF0716A, light: 0xBF3328)
            case .statusInfo: return Pair(dark: 0x8FB3D9, light: 0x2B5F91)
            }
        }
    }

    struct OrbPalette: Sendable { let liquidTop: UInt32; let liquidBottom: UInt32; let rim: UInt32; let shell: String }

    nonisolated static func orb(_ direction: LXDirection) -> OrbPalette {
        switch direction {
        case .obsidian: return OrbPalette(liquidTop: 0xE9D4A8, liquidBottom: 0x9C7B45, rim: 0xF3E3C0, shell: "smoked")
        case .porcelain: return OrbPalette(liquidTop: 0x2E8C70, liquidBottom: 0x0F5C4A, rim: 0xCFE8DD, shell: "frosted")
        case .aurora: return OrbPalette(liquidTop: 0x70EDC6, liquidBottom: 0x8C99FA, rim: 0xC9F7EA, shell: "clear")
        }
    }

    enum Space {
        nonisolated static let s100: CGFloat = 4
        nonisolated static let s200: CGFloat = 8
        nonisolated static let s300: CGFloat = 12
        nonisolated static let s400: CGFloat = 16
        nonisolated static let s500: CGFloat = 20
        nonisolated static let s600: CGFloat = 24
        nonisolated static let s700: CGFloat = 32
        nonisolated static let s800: CGFloat = 40
        nonisolated static let s900: CGFloat = 56
        nonisolated static let screenMargin: CGFloat = 20
        nonisolated static let screenMarginCompact: CGFloat = 16
        nonisolated static let cardGap: CGFloat = 12
        nonisolated static let minTouchTarget: CGFloat = 44
    }

    enum Radius {
        nonisolated static let chip: CGFloat = 12
        nonisolated static let tile: CGFloat = 16
        nonisolated static let card: CGFloat = 22
        nonisolated static let sheet: CGFloat = 28
        nonisolated static let hero: CGFloat = 28
    }

    struct TypeSpec: Sendable { let size: CGFloat; let lineHeight: CGFloat; let weight: Font.Weight; let relativeTo: Font.TextStyle; let isDisplay: Bool }

    enum TypeRamp {
        nonisolated static let displayHero = TypeSpec(size: 64, lineHeight: 68, weight: .semibold, relativeTo: .largeTitle, isDisplay: true)
        nonisolated static let displayL = TypeSpec(size: 40, lineHeight: 44, weight: .semibold, relativeTo: .largeTitle, isDisplay: true)
        nonisolated static let titleLarge = TypeSpec(size: 34, lineHeight: 41, weight: .bold, relativeTo: .largeTitle, isDisplay: true)
        nonisolated static let title1 = TypeSpec(size: 28, lineHeight: 34, weight: .semibold, relativeTo: .title, isDisplay: false)
        nonisolated static let title2 = TypeSpec(size: 22, lineHeight: 28, weight: .semibold, relativeTo: .title2, isDisplay: false)
        nonisolated static let title3 = TypeSpec(size: 20, lineHeight: 25, weight: .semibold, relativeTo: .title3, isDisplay: false)
        nonisolated static let headline = TypeSpec(size: 17, lineHeight: 22, weight: .semibold, relativeTo: .headline, isDisplay: false)
        nonisolated static let body = TypeSpec(size: 17, lineHeight: 22, weight: .regular, relativeTo: .body, isDisplay: false)
        nonisolated static let callout = TypeSpec(size: 16, lineHeight: 21, weight: .regular, relativeTo: .callout, isDisplay: false)
        nonisolated static let subhead = TypeSpec(size: 15, lineHeight: 20, weight: .regular, relativeTo: .subheadline, isDisplay: false)
        nonisolated static let footnote = TypeSpec(size: 13, lineHeight: 18, weight: .regular, relativeTo: .footnote, isDisplay: false)
        nonisolated static let caption = TypeSpec(size: 12, lineHeight: 16, weight: .medium, relativeTo: .caption, isDisplay: false)
    }

    enum Motion {
        nonisolated static let instantDuration: Double = 0.12
        nonisolated static let snappyDuration: Double = 0.3
        nonisolated static let smoothDuration: Double = 0.45
        nonisolated static let gentleDuration: Double = 0.6
        nonisolated static let gentleBounce: Double = 0.1
        nonisolated static let celebrateDuration: Double = 0.7
        nonisolated static let celebrateBounce: Double = 0.25
        nonisolated static let reducedDuration: Double = 0.2
        nonisolated static let staggerPerItem: Double = 0.035
        nonisolated static let staggerMaxItems: Double = 6
        nonisolated static let exitScale: Double = 0.7
    }

    enum Orb {
        nonisolated static let heroSize: CGFloat = 240
        nonisolated static let headerSize: CGFloat = 120
        nonisolated static let glyphSize: CGFloat = 44
        nonisolated static let breathScale: CGFloat = 1.015
        nonisolated static let breathPeriod: CGFloat = 4.0
        nonisolated static let maxFill: CGFloat = 1.2
    }
}
