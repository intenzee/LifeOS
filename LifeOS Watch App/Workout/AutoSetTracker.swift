import Foundation
import Combine
import CoreMotion
import WatchKit

/// Automatically counts sets (and reps) of a strength exercise from wrist motion.
///
/// Mechanism:
/// 1. `CMMotionManager` streams device motion at ~50 Hz while the app is in the
///    foreground. (Screen-off / background tracking would require an
///    `HKWorkoutSession`, which needs the HealthKit capability — a paid Apple
///    Developer account. On a free account we track while the app is active.)
/// 2. We take the magnitude of
///    user acceleration (gravity already removed) and low-pass filter it into a
///    smooth "motion energy" signal.
/// 3. A state machine tracks active vs. resting periods. While active, acceleration
///    peaks above a threshold (with a refractory gap) are counted as reps. When
///    motion stays low for `restToFinalize` seconds after a genuine working set
///    (≥ `minRepsPerSet` reps), the set is finalized and the count advances.
///
/// Thresholds are heuristic and tuned for typical resistance-training cadence; they
/// can be refined against real logged sessions.
@MainActor
final class AutoSetTracker: ObservableObject {

    enum Phase: Equatable { case idle, active, resting }

    @Published private(set) var isRunning = false
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var reps: Int = 0          // reps in the set currently in progress
    @Published private(set) var setsCompleted: Int = 0
    @Published private(set) var lastSetReps: Int = 0
    @Published private(set) var motionLevel: Double = 0 // 0...1, for the live UI meter

    /// Called on the main actor each time a set is finalized, with the new total.
    var onSetFinalized: ((_ setsCompleted: Int, _ reps: Int) -> Void)?

    // Tuning constants
    private let sampleRate = 50.0
    private let activeThreshold = 0.18     // motion energy that means "working"
    private let restThreshold = 0.06       // below this counts as rest
    private let repPeakThreshold = 0.30    // acceleration magnitude for a rep peak
    private let repRefractory = 0.33       // min seconds between counted reps
    private let restToFinalize = 3.0       // seconds of rest that ends a set
    private let minRepsPerSet = 3          // fewer reps = noise, not a set

    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()

    // Filter / detector state
    private var energy = 0.0
    private var lastRepTime: TimeInterval = 0
    private var restAccumulator = 0.0
    private var wasAbovePeak = false
    private var startingSets = 0

    // MARK: - Lifecycle

    /// Starts tracking. `initialSets` seeds the counter from the exercise's existing
    /// progress so watch and phone stay consistent.
    func start(initialSets: Int) {
        guard !isRunning else { return }
        startingSets = initialSets
        setsCompleted = initialSets
        reps = 0
        lastSetReps = 0
        energy = 0
        restAccumulator = 0
        wasAbovePeak = false
        phase = .resting
        isRunning = true

        startMotionUpdates()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        phase = .idle
        motionManager.stopDeviceMotionUpdates()
    }

    /// Records a rep/set manually (fallback if the wearer wants to override).
    func manualAddSet() {
        setsCompleted += 1
        lastSetReps = reps
        reps = 0
        WKInterfaceDevice.current().play(.success)
        onSetFinalized?(setsCompleted, lastSetReps)
    }

    // MARK: - Motion processing

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = 1.0 / sampleRate
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let a = motion.userAcceleration
            let magnitude = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let now = motion.timestamp
            Task { @MainActor in self.process(magnitude: magnitude, timestamp: now) }
        }
    }

    private func process(magnitude: Double, timestamp: TimeInterval) {
        guard isRunning else { return }

        // Low-pass filter into a smooth energy signal.
        energy = energy * 0.9 + magnitude * 0.1
        motionLevel = min(energy / activeThreshold, 1.0)

        let dt = 1.0 / sampleRate

        switch phase {
        case .resting, .idle:
            if energy > activeThreshold {
                phase = .active
                restAccumulator = 0
            }
        case .active:
            // Rep detection: rising edge across the peak threshold, rate-limited.
            if magnitude > repPeakThreshold {
                if !wasAbovePeak, timestamp - lastRepTime > repRefractory {
                    reps += 1
                    lastRepTime = timestamp
                    WKInterfaceDevice.current().play(.click)
                }
                wasAbovePeak = true
            } else {
                wasAbovePeak = false
            }

            // Accumulate rest; finalize the set once rest is sustained.
            if energy < restThreshold {
                restAccumulator += dt
                if restAccumulator >= restToFinalize {
                    finalizeSet()
                    phase = .resting
                    restAccumulator = 0
                }
            } else {
                restAccumulator = 0
            }
        }
    }

    private func finalizeSet() {
        guard reps >= minRepsPerSet else {
            reps = 0 // discard noise
            return
        }
        setsCompleted += 1
        lastSetReps = reps
        reps = 0
        WKInterfaceDevice.current().play(.success)
        onSetFinalized?(setsCompleted, lastSetReps)
    }
}
