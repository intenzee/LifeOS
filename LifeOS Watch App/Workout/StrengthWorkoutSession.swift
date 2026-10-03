import Foundation
import Combine
import HealthKit
import LifeOSCore
import os

/// A real Apple Health strength workout recorded on the watch (WCH-12/13).
///
/// While it runs, watchOS keeps the app alive with the wrist down
/// (`workout-processing` background mode), so `AutoSetTracker` keeps counting.
/// It shows live heart rate and active energy. Ending saves an `HKWorkout` that
/// reaches the phone through Health like any other workout (doc 02 §3.5). Sets
/// become marker events, so the phone can merge them (WCH-06/14).
@MainActor
final class StrengthWorkoutSession: NSObject, ObservableObject {
    static let shared = StrengthWorkoutSession()

    enum State: Equatable {
        case idle, starting, running, ending
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var heartRate: Double?
    @Published private(set) var activeKcal: Double = 0
    @Published private(set) var startDate: Date?
    @Published private(set) var setsRecorded = 0

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    private static let heartRate = HKQuantityType(.heartRate)
    private static let activeEnergy = HKQuantityType(.activeEnergyBurned)

    var isActive: Bool { state == .running || state == .starting }

    // MARK: Lifecycle

    func start() async {
        guard state == .idle || isFailed else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            state = .failed("Health isn't available.")
            return
        }
        state = .starting
        do {
            try await store.requestAuthorization(toShare: [HKObjectType.workoutType()],
                                                 read: [Self.heartRate, Self.activeEnergy])
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            try begin(HKWorkoutSession(healthStore: store, configuration: configuration), configuration: configuration)
        } catch {
            fail(error)
        }
    }

    /// Re-attaches to a session that survived an app crash or relaunch.
    func recover() async {
        do {
            guard let recovered = try await store.recoverActiveWorkoutSession() else { return }
            try begin(recovered, configuration: recovered.workoutConfiguration, resume: true)
        } catch {
            fail(error)
        }
    }

    func end() async {
        guard let session, let builder, state == .running else { return }
        state = .ending
        let start = startDate ?? Date()
        session.end()
        do {
            try await builder.endCollection(at: Date())
            try await builder.addMetadata(["LifeOSSetCount": setsRecorded, HKMetadataKeyIndoorWorkout: true])
            _ = try await builder.finishWorkout()
            Log.watch.notice("Strength workout saved (\(self.setsRecorded) sets)")
            WatchSessionManager.shared.workoutEnded(on: DayKey.make(for: start))
            reset()
        } catch {
            fail(error)
        }
    }

    /// A set finished (auto-tracked or manual). Stored as a marker event so the
    /// phone knows when each set happened.
    func recordSet(exercise: String, setNumber: Int, at date: Date = Date()) {
        guard state == .running, let builder else { return }
        setsRecorded += 1
        let event = HKWorkoutEvent(type: .marker, dateInterval: DateInterval(start: date, duration: 0),
                                   metadata: ["LifeOSExercise": exercise, "LifeOSSetNumber": setNumber])
        builder.addWorkoutEvents([event]) { _, error in
            if let error { Log.watch.error("Set marker failed: \(error.localizedDescription, privacy: .public)") }
        }
    }

    // MARK: Private

    private var isFailed: Bool { if case .failed = state { return true } else { return false } }

    private func begin(_ session: HKWorkoutSession, configuration: HKWorkoutConfiguration, resume: Bool = false) throws {
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
        session.delegate = self
        builder.delegate = self
        self.session = session
        self.builder = builder
        if resume {
            startDate = builder.startDate ?? session.startDate
            state = .running
            return
        }
        let start = Date()
        startDate = start
        session.startActivity(with: start)
        builder.beginCollection(withStart: start) { [weak self] success, error in
            Task { @MainActor in
                guard let self else { return }
                if success { self.state = .running } else { self.fail(error) }
            }
        }
    }

    private func fail(_ error: Error?) {
        let message = error?.localizedDescription ?? "The workout couldn't start."
        Log.watch.error("Workout session error: \(message, privacy: .public)")
        session?.end()
        reset()
        state = .failed(message)
    }

    private func reset() {
        session = nil
        builder = nil
        state = .idle
        heartRate = nil
        activeKcal = 0
        startDate = nil
        setsRecorded = 0
    }

    fileprivate func update(from builder: HKLiveWorkoutBuilder) {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        heartRate = builder.statistics(for: Self.heartRate)?.mostRecentQuantity()?.doubleValue(for: bpm)
        activeKcal = builder.statistics(for: Self.activeEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
    }
}

extension StrengthWorkoutSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in self.fail(error) }
    }
}

extension StrengthWorkoutSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in self.update(from: workoutBuilder) }
    }
}
