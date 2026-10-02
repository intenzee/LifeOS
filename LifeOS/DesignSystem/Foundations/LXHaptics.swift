import SwiftUI

/// Haptics mapped to meaning (Phase 2 §8.4). No haptic without a visible change.
enum LXHaptic: CaseIterable, Sendable {
    case logged          // food, water, weight saved — once per save
    case selection       // picker / chip
    case increase        // stepper up
    case decrease        // stepper down
    case orbTouch        // touching the orb (caller rate-limits to 300 ms)
    case workoutArrived  // Watch workout raised the budget
    case firstOverBudget // once per day
    case destructive     // destructive confirm

    var feedback: SensoryFeedback {
        switch self {
        case .logged: return .success
        case .selection: return .selection
        case .increase: return .increase
        case .decrease: return .decrease
        case .orbTouch: return .impact(weight: .light)
        case .workoutArrived: return .impact(weight: .medium)
        case .firstOverBudget: return .warning
        case .destructive: return .impact(weight: .heavy)
        }
    }
}

extension View {
    /// Plays the haptic for `event` whenever `trigger` changes.
    func lxHaptic<T: Equatable>(_ event: LXHaptic, trigger: T) -> some View {
        sensoryFeedback(event.feedback, trigger: trigger)
    }
}
