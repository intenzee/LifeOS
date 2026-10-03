import Foundation

/// Joins a manual LifeOS gym log to the Apple Watch workout that recorded the
/// same session (WCH-06, doc 02 §3.3), and decides which energy counts.
///
/// The merge is **derived**: it is recomputed from scratch for a whole day on
/// every sync, so editing or deleting a workout in Health un-merges cleanly.
public enum WorkoutMerge {
    /// Padding around a manual log's set times (doc 02 §3.3: ± 15 min).
    public static let manualPadding: TimeInterval = 15 * 60
    /// Minimum overlap, as a share of the shorter interval.
    public static let minimumOverlap = 0.5

    /// The day's manual gym log as the merge sees it.
    public struct ManualLog: Sendable, Equatable {
        public var dayKey: DayKey
        public var exerciseIDs: [UUID]
        /// First to last set time, when known. Legacy logs have no set times.
        public var window: DateInterval?

        public init(dayKey: DayKey, exerciseIDs: [UUID], window: DateInterval? = nil) {
            self.dayKey = dayKey
            self.exerciseIDs = exerciseIDs
            self.window = window
        }

        public var isEmpty: Bool { exerciseIDs.isEmpty }
    }

    /// Overlap of `a` and `b` as a share of the shorter one (0…1).
    public static func overlapFraction(_ a: DateInterval, _ b: DateInterval) -> Double {
        guard let shared = a.intersection(with: b) else { return 0 }
        let shorter = min(a.duration, b.duration)
        guard shorter > 0 else { return shared.duration >= 0 && a.start == b.start ? 1 : 0 }
        return shared.duration / shorter
    }

    /// Returns the day's sessions with `mergedExerciseIDs` set on at most one of them.
    ///
    /// The manual log merges into a session only when exactly one compatible
    /// (strength/HIIT) session matches:
    /// - with set times: the padded window overlaps the session by ≥ 50% of the shorter;
    /// - without set times: it is the only compatible session that day.
    /// Zero or several matches mean no merge. Guessing would hide a workout.
    public static func attach(manual: ManualLog?, to sessions: [WorkoutSession]) -> [WorkoutSession] {
        var result = sessions.map { session -> WorkoutSession in
            var copy = session
            copy.mergedExerciseIDs = []
            return copy
        }
        guard let manual, !manual.isEmpty else { return result }

        let compatible = result.indices.filter {
            result[$0].dayKey == manual.dayKey && result[$0].kind.mergesWithGymLog
        }
        let matches: [Int]
        if let window = manual.window {
            let padded = DateInterval(start: window.start.addingTimeInterval(-manualPadding),
                                      end: window.end.addingTimeInterval(manualPadding))
            matches = compatible.filter {
                overlapFraction(padded, DateInterval(start: result[$0].start, end: max(result[$0].end, result[$0].start)))
                    >= minimumOverlap
            }
        } else {
            matches = compatible
        }
        if matches.count == 1 {
            result[matches[0]].mergedExerciseIDs = manual.exerciseIDs
        }
        return result
    }

    /// Workout energy for a day without double counting: when sessions overlap
    /// by ≥ 50% (the same run recorded by Strava and the Workout app), only the
    /// larger one counts.
    public static func dedupedWorkoutEnergy(_ sessions: [WorkoutSession]) -> Double {
        var kept: [WorkoutSession] = []
        let byEnergy = sessions
            .filter { ($0.activeEnergyKcal ?? 0) > 0 }
            .sorted { ($0.activeEnergyKcal ?? 0) > ($1.activeEnergyKcal ?? 0) }
        for session in byEnergy {
            let interval = DateInterval(start: session.start, end: max(session.end, session.start))
            let duplicate = kept.contains {
                overlapFraction(interval, DateInterval(start: $0.start, end: max($0.end, $0.start))) >= minimumOverlap
            }
            if !duplicate { kept.append(session) }
        }
        return kept.reduce(0) { $0 + ($1.activeEnergyKcal ?? 0) }
    }

    /// Exercise energy for estimated mode (no Watch): measured workout energy
    /// beats the MET estimate, which counts only when no workout absorbed the log.
    public static func estimatedSessionKcal(sessions: [WorkoutSession], manualMETKcal: Double) -> Double {
        let merged = sessions.contains { !$0.mergedExerciseIDs.isEmpty }
        return dedupedWorkoutEnergy(sessions) + (merged ? 0 : max(manualMETKcal, 0))
    }
}
