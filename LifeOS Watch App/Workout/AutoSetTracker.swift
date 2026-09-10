import Foundation
import Combine
import CoreMotion
import WatchKit

/// Automatically counts sets (and reps) of a strength exercise from wrist motion.
///
/// Accuracy approach (why this beats fixed thresholds):
/// 1. **Sensor fusion** — we combine `userAcceleration` (gravity already removed)
///    with `rotationRate` (gyro). Curls, presses and rows all produce a rotation
///    signature the accelerometer alone misses.
/// 2. **Set boundaries from a sliding-RMS envelope that auto-calibrates.** We keep
///    a short RMS window of the fused signal and compare it against a *rest noise
///    floor* learned live while you're resting. So "working vs resting" adapts to
///    each person and each watch band tightness instead of a hard-coded number.
/// 3. **Reps from adaptive, hysteresis-gated peak detection.** The rep threshold is
///    a multiple of the signal's own running deviation (σ), so slow heavy reps and
///    fast light reps both register. A rep is only counted on a full high→low
///    crossing (hysteresis) after a refractory gap, which kills the double-counting
///    that plagues single-threshold detectors.
///
/// It remains a heuristic — wrist IMUs can't be perfect — but it self-tunes and is
/// markedly more robust than a fixed-threshold counter. A manual "Log Set" fallback
/// is always available, and rep-count events fire haptics so you can feel miscounts.
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

    // MARK: - Tuning constants

    private let sampleRate = 50.0
    private var dt: Double { 1.0 / sampleRate }

    /// Weight applied to gyro magnitude (rad/s) when fusing with accel (g).
    private let gyroWeight = 0.12

    /// Sliding-RMS window length for the activity envelope (samples). ~0.5 s.
    private let envWindow = 25

    /// Rep peak detection (multiples of the running deviation σ of the AC signal).
    private let kHigh = 1.15          // rise above σ·kHigh opens a peak
    private let kLow = 0.40           // fall below σ·kLow closes/counts it
    private let repRefractory = 0.34  // min seconds between counted reps (≈2.9/s cap)
    private let minPeakAccel = 0.045  // absolute g floor so tremor at rest never counts

    /// Set state machine.
    private let restToFinalize = 2.5  // seconds of sustained rest that ends a set
    private let minRepsPerSet = 2     // fewer reps than this = noise, discard
    private let enterActiveMultiple = 2.6   // envRMS > floor·this  → working
    private let exitActiveMultiple = 1.7    // envRMS < floor·this  → resting
    private let minEnterEnv = 0.030   // absolute envelope floor to enter a set
    private let minExitEnv = 0.018

    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()

    // MARK: - Detector state

    // Envelope (sliding RMS of the fused movement signal)
    private var envBuffer = [Double]()
    private var envSumSq = 0.0
    private var envIndex = 0
    private var envFilled = false

    // Learned resting noise floor of the envelope
    private var restFloor = 0.0
    private var restFloorSeeded = false

    // AC signal statistics for rep detection
    private var accelBaseline = 0.0   // slow EMA of accel magnitude (gravity residual / drift)
    private var acVariance = 0.0      // EMA of ac² → σ = sqrt(acVariance)
    private var baselineSeeded = false

    // Rep peak machine
    private var inPeak = false
    private var peakMax = 0.0
    private var lastRepTime: TimeInterval = 0

    // Set machine
    private var restAccumulator = 0.0
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
        resetDetector()
        phase = .resting
        isRunning = true
        startMotionUpdates()
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        phase = .idle
        motionLevel = 0
        motionManager.stopDeviceMotionUpdates()
    }

    /// Records a set manually (fallback if the wearer wants to override).
    func manualAddSet() {
        setsCompleted += 1
        lastSetReps = reps
        reps = 0
        restAccumulator = 0
        WKInterfaceDevice.current().play(.success)
        onSetFinalized?(setsCompleted, lastSetReps)
    }

    private func resetDetector() {
        envBuffer = Array(repeating: 0, count: envWindow)
        envSumSq = 0
        envIndex = 0
        envFilled = false
        restFloor = 0
        restFloorSeeded = false
        accelBaseline = 0
        acVariance = 0
        baselineSeeded = false
        inPeak = false
        peakMax = 0
        lastRepTime = 0
        restAccumulator = 0
        motionLevel = 0
    }

    // MARK: - Motion processing

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = dt
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let a = motion.userAcceleration
            let r = motion.rotationRate
            let accelMag = sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
            let gyroMag = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
            let t = motion.timestamp
            Task { @MainActor in self.process(accelMag: accelMag, gyroMag: gyroMag, timestamp: t) }
        }
    }

    private func process(accelMag: Double, gyroMag: Double, timestamp: TimeInterval) {
        guard isRunning else { return }

        let move = accelMag + gyroWeight * gyroMag

        // --- 1. Sliding-RMS envelope of the fused signal ---
        let old = envBuffer[envIndex]
        envBuffer[envIndex] = move
        envSumSq += move * move - old * old
        envIndex = (envIndex + 1) % envWindow
        if envIndex == 0 { envFilled = true }
        let count = envFilled ? Double(envWindow) : Double(max(envIndex, 1))
        let envRms = sqrt(max(envSumSq, 0) / count)

        // --- 2. Adaptive AC signal + running deviation (σ) for rep peaks ---
        if !baselineSeeded { accelBaseline = accelMag; baselineSeeded = true }
        // Slow baseline (~0.4 s) tracks gravity residual / posture drift.
        accelBaseline += (accelMag - accelBaseline) * (dt / 0.40)
        let ac = accelMag - accelBaseline
        // EMA of ac² (~0.5 s) → deviation of the oscillation.
        acVariance += (ac * ac - acVariance) * (dt / 0.50)
        let sigma = sqrt(max(acVariance, 0))

        // --- 3. Learn the resting noise floor of the envelope ---
        if !restFloorSeeded { restFloor = envRms; restFloorSeeded = true }
        if phase != .active {
            // While resting, ease the floor toward the current ambient RMS so it
            // tracks band tightness / posture. It is held fixed during a set.
            restFloor += (envRms - restFloor) * (dt / 0.60)
        }

        let enterThresh = max(minEnterEnv, restFloor * enterActiveMultiple)
        let exitThresh = max(minExitEnv, restFloor * exitActiveMultiple)

        // Live UI meter (0…1 relative to the enter threshold).
        motionLevel = min(envRms / max(enterThresh, 0.0001), 1.0)

        // --- 4. Set state machine ---
        switch phase {
        case .idle, .resting:
            if envRms > enterThresh {
                phase = .active
                restAccumulator = 0
                inPeak = false
                peakMax = 0
            }
        case .active:
            countReps(ac: ac, sigma: sigma, timestamp: timestamp)

            if envRms < exitThresh {
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

    /// Adaptive, hysteresis-gated, refractory-limited rep peak detection.
    private func countReps(ac: Double, sigma: Double, timestamp: TimeInterval) {
        let highThr = max(sigma * kHigh, minPeakAccel)
        let lowThr = sigma * kLow

        if !inPeak {
            if ac > highThr, timestamp - lastRepTime > repRefractory {
                inPeak = true
                peakMax = ac
            }
        } else {
            peakMax = max(peakMax, ac)
            // Count on the down-crossing (a full up→down excursion = one rep).
            if ac < lowThr {
                inPeak = false
                // Require genuine prominence relative to noise floor.
                if peakMax >= max(minPeakAccel, sigma * kHigh) {
                    reps += 1
                    lastRepTime = timestamp
                    WKInterfaceDevice.current().play(.click)
                }
                peakMax = 0
            }
        }
    }

    private func finalizeSet() {
        // Close any peak in progress.
        inPeak = false
        peakMax = 0
        guard reps >= minRepsPerSet else {
            reps = 0 // discard noise / accidental movement
            return
        }
        setsCompleted += 1
        lastSetReps = reps
        reps = 0
        WKInterfaceDevice.current().play(.success)
        onSetFinalized?(setsCompleted, lastSetReps)
    }
}
