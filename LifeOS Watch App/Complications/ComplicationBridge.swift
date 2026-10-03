import Combine
import Foundation
import LifeOSConnectivity
import LifeOSCore
import os
import WidgetKit

/// Feeds the complications and Smart Stack widgets (WCH-15).
///
/// After each phone snapshot, and when a LifeOS workout starts or stops, it
/// writes a `ComplicationSnapshot` to the watch's App Group and reloads the
/// timelines, but only when something a widget shows has changed: watchOS
/// gives background reloads a daily budget.
@MainActor
final class ComplicationBridge {
    static let shared = ComplicationBridge()

    private static let log = Logger(subsystem: "com.tanmay.LifeOS.watchkitapp", category: "complications")
    private var cancellables = Set<AnyCancellable>()
    private var lastWritten: ComplicationSnapshot?

    private init() {}

    func start() {
        guard cancellables.isEmpty else { return }
        lastWritten = ComplicationStore.read()
        let session = WatchSessionManager.shared
        session.$snapshot
            .combineLatest(session.$hasReceivedData,
                           StrengthWorkoutSession.shared.$state.map { $0 == .running || $0 == .starting })
            .removeDuplicates { $0 == $1 }
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] snapshot, received, workoutActive in
                guard received else { return }
                self?.publish(snapshot, workoutActive: workoutActive)
            }
            .store(in: &cancellables)
    }

    private func publish(_ snapshot: WatchSnapshot, workoutActive: Bool) {
        let next = ComplicationSnapshot(snapshot, workoutActive: workoutActive, now: Date())
        guard next.differsVisibly(from: lastWritten) else { return }
        guard ComplicationStore.write(next) else {
            Self.log.error("No App Group container; complications keep their last data")
            return
        }
        lastWritten = next
        WidgetCenter.shared.reloadAllTimelines()
    }
}

extension ComplicationSnapshot {
    /// From the phone's snapshot as the watch holds it. Values are copied, never derived.
    init(_ watch: WatchSnapshot, workoutActive: Bool, now: Date) {
        let trained = !watch.workoutsToday.isEmpty || watch.exercises.contains { $0.setsCompleted > 0 }
        self.init(day: DayKey(watch.date) ?? .today(),
                  budgetKcal: watch.calorieLimit,
                  eatenKcal: watch.caloriesConsumed,
                  earnedKcal: watch.earnedKcal ?? 0,
                  proteinG: watch.proteinG,
                  proteinTargetG: watch.proteinTargetG,
                  waterGlasses: watch.waterCount,
                  waterTarget: watch.waterTarget,
                  streak: watch.perfectStreak,
                  trainedToday: trained || workoutActive,
                  workoutActive: workoutActive,
                  trainingWindow: watch.trainingWindow,
                  preset: watch.presets.first.map { Preset(name: $0.name, kcal: $0.kcal) },
                  updatedAt: now)
    }
}
