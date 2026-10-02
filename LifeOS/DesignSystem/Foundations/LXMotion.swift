import SwiftUI

/// Named motion tokens (Phase 2 §8.1). The direction scales spring bounce
/// (Obsidian: none, Porcelain: half, Aurora: full), and Reduce Motion swaps
/// every token for a short cross-fade.
enum LXMotion: CaseIterable, Sendable {
    case instant, snappy, smooth, gentle, celebrate

    nonisolated func animation(direction: LXDirection = .aurora, reduceMotion: Bool = false) -> Animation {
        if reduceMotion { return .easeInOut(duration: LXTokens.Motion.reducedDuration) }
        let k = direction.motionBounceScale
        switch self {
        case .instant:
            return .easeOut(duration: LXTokens.Motion.instantDuration)
        case .snappy:
            return .spring(duration: LXTokens.Motion.snappyDuration, bounce: 0.15 * k)
        case .smooth:
            return .spring(duration: LXTokens.Motion.smoothDuration, bounce: 0)
        case .gentle:
            return .spring(duration: LXTokens.Motion.gentleDuration, bounce: LXTokens.Motion.gentleBounce * k)
        case .celebrate:
            return .spring(duration: LXTokens.Motion.celebrateDuration, bounce: LXTokens.Motion.celebrateBounce * max(k, 0.4))
        }
    }

    /// Exits run at ~70% of the enter duration (choreography rule 4).
    nonisolated func exit(direction: LXDirection = .aurora, reduceMotion: Bool = false) -> Animation {
        animation(direction: direction, reduceMotion: reduceMotion).speed(1 / LXTokens.Motion.exitScale)
    }

    /// Delay for the n-th item of a staggered list (rule 3: 35 ms, max 6 items).
    nonisolated static func staggerDelay(index: Int) -> Double {
        Double(min(index, Int(LXTokens.Motion.staggerMaxItems))) * LXTokens.Motion.staggerPerItem
    }
}

private struct LXAnimationModifier<V: Equatable>: ViewModifier {
    let motion: LXMotion
    let value: V
    @Environment(\.lxDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(motion.animation(direction: direction, reduceMotion: reduceMotion), value: value)
    }
}

private struct LXNumberRoll: ViewModifier {
    let value: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if reduceMotion {
            content // Reduce Motion: numbers change instantly (Phase 2 §8.3).
        } else {
            content.contentTransition(.numericText(value: value))
        }
    }
}

extension View {
    /// Animates changes to `value` with a named motion token, honouring direction and Reduce Motion.
    func lxAnimation<V: Equatable>(_ motion: LXMotion, value: V) -> some View {
        modifier(LXAnimationModifier(motion: motion, value: value))
    }

    /// `motion.number`: numbers roll to new values, never jump.
    func lxNumberRoll(_ value: Double) -> some View {
        modifier(LXNumberRoll(value: value))
    }
}
