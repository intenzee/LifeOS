import ActivityKit
import Foundation

/// Phase 5 §4: one Live Activity for an in-app gym session. While resting it
/// shows the rest countdown, so the session and the rest timer share one
/// activity (and one Dynamic Island slot). Updated by the app on the phone;
/// no push server.
nonisolated struct LifeOSActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        var exercise: String
        /// Sets done and planned for the current exercise.
        var setsDone: Int
        var setsTotal: Int
        var setsToday: Int
        var restEndsAt: Date?
        var restSeconds: Int
        var nextExercise: String?
        var finished: Bool

        func resting(at now: Date = Date()) -> Bool { (restEndsAt ?? .distantPast) > now }
    }

    var startedAt: Date
}
