import SwiftUI
import Testing
@testable import LifeOSDesign

/// Phase 2 §3 rules, enforced on the generated tokens for every direction and mode.
@Suite struct TokenContrastTests {
    nonisolated static let cases: [(LXDirection, ColorScheme)] = LXDirection.allCases.flatMap { d in [(d, .dark), (d, .light)] }

    func ratio(_ a: LXColorRole, _ b: LXColorRole, _ theme: LXTheme) -> Double {
        LXRGB(hex: theme.hex(a)).contrast(with: LXRGB(hex: theme.hex(b)))
    }

    @Test(arguments: cases)
    func textAndAccentContrast(direction: LXDirection, scheme: ColorScheme) {
        let t = LXTheme(direction: direction, colorScheme: scheme)
        #expect(ratio(.textPrimary, .background, t) >= 7)
        #expect(ratio(.textSecondary, .surface, t) >= 4.5)
        #expect(ratio(.textSecondary, .background, t) >= 4.5)
        #expect(ratio(.textTertiary, .background, t) >= 3)
        #expect(ratio(.accentPrimary, .background, t) >= 4.5, "A11: accent must be usable as text")
        #expect(ratio(.onAccent, .accentPrimary, t) >= 4.5)
    }

    @Test(arguments: cases)
    func dataAndStatusColoursReadAsText(direction: LXDirection, scheme: ColorScheme) {
        let t = LXTheme(direction: direction, colorScheme: scheme)
        for role in LXColorRole.allCases where role.rawValue.hasPrefix("data") || role.rawValue.hasPrefix("status") {
            for bg in [LXColorRole.background, .surface, .surfaceRaised] {
                #expect(ratio(role, bg, t) >= 4.5, "\(role) on \(bg)")
            }
        }
    }

    @Test func increaseContrastPromotesSecondaryText() {
        let normal = LXTheme(direction: .porcelain, colorScheme: .light)
        var boosted = normal
        boosted.increasedContrast = true
        #expect(ratio(.textSecondary, .background, boosted) > ratio(.textSecondary, .background, normal))
    }

    @Test func mintIsNotUsedAsLightModeAccent() {
        // The old #70EDC6 mint is 1.4:1 on white (audit A11).
        #expect(LXTheme(direction: .aurora, colorScheme: .light).hex(.accentPrimary) != 0x70EDC6)
    }

    @Test func statusOverIsNeverAlarmRed() {
        for d in LXDirection.allCases {
            let over = LXRGB(hex: LXTokens.pair(.statusOver, d).dark)
            let critical = LXRGB(hex: LXTokens.pair(.statusCritical, d).dark)
            #expect(over != critical)
            #expect(over.g > critical.g * 0.9, "over budget should be amber/copper, not red")
        }
    }
}

@Suite struct MotionTests {
    @Test func reduceMotionSwapsEveryToken() {
        for m in LXMotion.allCases {
            #expect(m.animation(reduceMotion: true) == .easeInOut(duration: LXTokens.Motion.reducedDuration))
        }
    }

    @Test func staggerCapsAtSixItems() {
        #expect(LXMotion.staggerDelay(index: 0) == 0)
        #expect(LXMotion.staggerDelay(index: 6) == LXMotion.staggerDelay(index: 40))
    }
}

@Suite struct LayoutTokenTests {
    @Test func spacingIsOnTheFourPointGrid() {
        for v in [LX.Space.s100, LX.Space.s200, LX.Space.s300, LX.Space.s400, LX.Space.s500, LX.Space.s600, LX.Space.s700, LX.Space.s800, LX.Space.s900] {
            #expect(v.truncatingRemainder(dividingBy: 4) == 0)
        }
    }

    @Test func radiusScaleMatchesExistingKit() {
        #expect([LX.Radius.chip, LX.Radius.tile, LX.Radius.card, LX.Radius.sheet] == [12, 16, 22, 28])
    }
}
