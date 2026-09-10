import Foundation
import Combine
import CoreMotion
import WatchKit

/// Automatically counts sets and reps of a strength exercise from wrist motion.
///
/// ## Why this counts reps correctly
/// A single rep produces *several* acceleration bursts (accelerate out, decelerate,
/// accelerate back, decelerate), so counting acceleration peaks over-counts. A rep is
/// really **one full motion cycle** — out and back. We detect that directly:
///
/// 1. **Velocity, not position.** Double-integrating acceleration to position drifts
///    badly (bias integrated twice → runaway error in ~1 s). Instead we integrate once
///    to *velocity* with a leaky (high-pass) integrator, which oscillates cleanly per
///    rep and self-zeroes at rest, with almost no drift.
/// 2. **Dominant-axis projection.** We track the axis the wrist is actually travelling
///    along and project velocity onto it, collapsing the 3-D swing into a clean 1-D
///    signal `s` that self-calibrates to any exercise (curl, press, row…).
/// 3. **One rep per full oscillation.** `s` swings positive (out) then negative (back);
///    each out-and-back is one rep — exactly the "to and fro = 1 rep" model — gated by
///    an amplitude threshold relative to the signal's own running level and a cadence
///    (refractory) limit so noise and rest never register.
///
/// Set boundaries use a separate sliding-RMS envelope that learns your rest noise
/// floor, so "working vs resting" adapts to you. A manual "Log Set" fallback remains.
@MainActor
final class AutoSetTracker: ObservableObject {

    enum Phase: Equatable { case idle, active, resting }

    @Published private(set) var isRunning = false
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var reps: Int = 0
    @Published private(set) var setsCompleted: Int = 0
    @Published private(set) var lastSetReps: Int = 0
    @Published private(set) var motionLevel: Double = 0 // 0...1, live UI meter

    var onSetFinalized: ((_ setsCompleted: Int, _ reps: Int) -> Void)?

    // MARK: - Tuning

    private let sampleRate = 50.0
    private var dt: Double { 1.0 / sampleRate }
    private let gyroWeight = 0.12

    // Set envelope
    private let envWindow = 25
    private let restToFinalize = 2.5
    private let minRepsPerSet = 1
    private let enterActiveMultiple = 2.6
    private let exitActiveMultiple = 1.7
    private let minEnterEnv = 0.030
    private let minExitEnv = 0.018

    // Velocity high-pass + rep oscillation
    private let velDecay = 0.985       // leaky integrator: high-passes out drift/bias
    private let axisAlpha = 0.04       // dominant-axis EMA rate
    private let repThresholdK = 0.55   // rep threshold as a fraction of the running |s|
    private let minSignalAmp = 0.004   // absolute floor (g·s) so still/noise never counts
    private let minRepPeriod = 0.40    // s — max ~2.5 reps/s
    private let lobeResetPeriod = 5.0  // s — if a half-cycle stalls, forget it

    private let motionManager = CMMotionManager()
    private let motionQueue = OperationQueue()

    // MARK: - Detector state

    // Envelope
    private var envBuffer = [Double]()
    private var envSumSq = 0.0
    private var envIndex = 0
    private var envFilled = false
    private var restFloor = 0.0
    private var restFloorSeeded = false

    // Velocity (leaky-integrated) and dominant axis
    private var vx = 0.0, vy = 0.0, vz = 0.0
    private var dx = 0.0, dy = 0.0, dz = 1.0
    private var axisSeeded = false
    private var sAmp = 0.0             // running level of the projected signal |s|

    // Rep oscillation state
    private var sawPositive = false
    private var sawNegative = false
    private var lastRepTime: TimeInterval = 0
    private var lastLobeTime: TimeInterval = 0

    // Set machine
    private var restAccumulator = 0.0
    private var startingSets = 0

    // MARK: - Lifecycle

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
        envSumSq = 0; envIndex = 0; envFilled = false
        restFloor = 0; restFloorSeeded = false
        vx = 0; vy = 0; vz = 0
        dx = 0; dy = 0; dz = 1; axisSeeded = false
        sAmp = 0
        sawPositive = false; sawNegative = false
        lastRepTime = 0; lastLobeTime = 0
        restAccumulator = 0
        motionLevel = 0
    }

    // MARK: - Motion

    private func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        motionManager.deviceMotionUpdateInterval = dt
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let a = motion.userAcceleration
            let r = motion.rotationRate
            let gyroMag = sqrt(r.x * r.x + r.y * r.y + r.z * r.z)
            let t = motion.timestamp
            Task { @MainActor in
                self.process(ax: a.x, ay: a.y, az: a.z, gyroMag: gyroMag, timestamp: t)
            }
        }
    }

    private func process(ax: Double, ay: Double, az: Double, gyroMag: Double, timestamp: TimeInterval) {
        guard isRunning else { return }

        let accelMag = sqrt(ax * ax + ay * ay + az * az)

        // --- Set envelope (sliding RMS of accel + a little gyro) ---
        let move = accelMag + gyroWeight * gyroMag
        let old = envBuffer[envIndex]
        envBuffer[envIndex] = move
        envSumSq += move * move - old * old
        envIndex = (envIndex + 1) % envWindow
        if envIndex == 0 { envFilled = true }
        let count = envFilled ? Double(envWindow) : Double(max(envIndex, 1))
        let envRms = sqrt(max(envSumSq, 0) / count)

        if !restFloorSeeded { restFloor = envRms; restFloorSeeded = true }
        if phase != .active {
            restFloor += (envRms - restFloor) * (dt / 0.60)
        }
        let enterThresh = max(minEnterEnv, restFloor * enterActiveMultiple)
        let exitThresh = max(minExitEnv, restFloor * exitActiveMultiple)
        motionLevel = min(envRms / max(enterThresh, 0.0001), 1.0)

        // --- Velocity (leaky integration → high-pass, kills drift) ---
        vx = vx * velDecay + ax * dt
        vy = vy * velDecay + ay * dt
        vz = vz * velDecay + az * dt
        let vMag = sqrt(vx * vx + vy * vy + vz * vz)

        // --- Dominant motion axis (EMA, sign-aligned) ---
        if vMag > 0.002 {
            var ux = vx / vMag, uy = vy / vMag, uz = vz / vMag
            if !axisSeeded {
                dx = ux; dy = uy; dz = uz; axisSeeded = true
            } else {
                // Keep the axis stable across the +/- halves of a rep.
                if ux * dx + uy * dy + uz * dz < 0 { ux = -ux; uy = -uy; uz = -uz }
                dx += (ux - dx) * axisAlpha
                dy += (uy - dy) * axisAlpha
                dz += (uz - dz) * axisAlpha
                let dm = sqrt(dx * dx + dy * dy + dz * dz)
                if dm > 0 { dx /= dm; dy /= dm; dz /= dm }
            }
        }

        // --- Projected 1-D rep signal and its running amplitude ---
        let s = vx * dx + vy * dy + vz * dz
        sAmp += (abs(s) - sAmp) * (dt / 0.50)

        // --- Set state machine ---
        switch phase {
        case .idle, .resting:
            if envRms > enterThresh {
                phase = .active
                restAccumulator = 0
                sawPositive = false; sawNegative = false
                lastLobeTime = timestamp
            }
        case .active:
            countRepOscillation(signal: s, timestamp: timestamp)
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

    /// Counts one rep per full out-and-back oscillation of the projected velocity.
    private func countRepOscillation(signal s: Double, timestamp: TimeInterval) {
        let thr = max(repThresholdK * sAmp, minSignalAmp)

        // Forget a stalled half-cycle so a pause mid-rep doesn't create a phantom rep.
        if timestamp - lastLobeTime > lobeResetPeriod {
            sawPositive = false; sawNegative = false
        }

        if s > thr {
            if !sawPositive { sawPositive = true; lastLobeTime = timestamp }
        } else if s < -thr {
            if !sawNegative { sawNegative = true; lastLobeTime = timestamp }
        }

        // A rep = one positive lobe AND one negative lobe (out and back).
        if sawPositive && sawNegative, timestamp - lastRepTime > minRepPeriod {
            reps += 1
            lastRepTime = timestamp
            sawPositive = false
            sawNegative = false
            WKInterfaceDevice.current().play(.click)
        }
    }

    private func finalizeSet() {
        sawPositive = false; sawNegative = false
        guard reps >= minRepsPerSet else { reps = 0; return }
        setsCompleted += 1
        lastSetReps = reps
        reps = 0
        WKInterfaceDevice.current().play(.success)
        onSetFinalized?(setsCompleted, lastSetReps)
    }
}
