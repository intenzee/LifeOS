import Foundation
import Combine
import CoreMotion
import WatchKit

/// Counts sets and reps of a strength exercise from wrist motion.
///
/// This is the orchestration layer: it owns the sensors and the workout session
/// and publishes UI state. The actual rep maths lives in `RepDetector`, and the
/// sample pipeline runs off the main thread in `MotionPipeline`.
///
/// ## What makes this accurate (and what still needs you)
/// - **Right sensor.** On Series 8+/Ultra (watchOS 10+) it uses
///   `CMBatchedSensorManager` device motion at ~200 Hz — Apple's purpose-built,
///   workout-only, batched high-rate stream — instead of the old 50 Hz
///   `CMMotionManager`. Older watches fall back to `CMMotionManager` at 100 Hz.
/// - **Sensors stay alive.** Counting auto-starts an `HKWorkoutSession`
///   (`StrengthWorkoutSession`), so watchOS keeps delivering motion with your
///   wrist *down* mid-set. Batched updates also *require* an active session.
/// - **No per-sample main-thread hops.** Samples are conditioned on the sensor
///   thread; the UI is updated once per batch (~1/s), not 200×/s.
/// - **Calibration.** An optional 3–5 rep calibration teaches the detector your
///   cadence and swing size before the first real set.
///
/// Rep counting is heuristic: these defaults are sensible, but dialling in the
/// last few percent of accuracy for a given lifter/exercise needs real lifting
/// data. The Digital Crown correction in the UI is the safety net and also the
/// signal we'd learn from.
@MainActor
final class AutoSetTracker: ObservableObject {

    enum Phase: Equatable { case idle, active, resting, calibrating }

    @Published private(set) var isRunning = false
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var reps: Int = 0
    @Published private(set) var setsCompleted: Int = 0
    @Published private(set) var lastSetReps: Int = 0
    @Published private(set) var motionLevel: Double = 0     // 0…1 live meter
    @Published private(set) var isCalibrating = false
    @Published private(set) var calibrationReps = 0
    /// True when the high-rate batched sensor is in use (vs the fallback).
    @Published private(set) var usingHighRate = false

    /// Target reps collected during calibration before it auto-completes.
    let calibrationTarget = 4

    var onSetFinalized: ((_ setsCompleted: Int, _ reps: Int) -> Void)?

    private let pipeline = MotionPipeline()
    private var startingSets = 0

    // MARK: - Lifecycle

    func start(initialSets: Int) {
        guard !isRunning else { return }
        startingSets = initialSets
        setsCompleted = initialSets
        reps = 0
        lastSetReps = 0
        isCalibrating = false
        calibrationReps = 0
        phase = .resting
        isRunning = true
        ensureWorkoutSession()
        beginPipeline(calibrating: false)
    }

    /// Starts a short calibration set. The detector learns cadence/amplitude from
    /// `calibrationTarget` reps, then tracking continues normally.
    func startCalibration(initialSets: Int) {
        guard !isRunning else { return }
        startingSets = initialSets
        setsCompleted = initialSets
        reps = 0
        lastSetReps = 0
        isCalibrating = true
        calibrationReps = 0
        phase = .calibrating
        isRunning = true
        ensureWorkoutSession()
        beginPipeline(calibrating: true)
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        phase = .idle
        motionLevel = 0
        isCalibrating = false
        pipeline.stop()
    }

    /// Manual "Log set" fallback.
    func manualAddSet() {
        setsCompleted += 1
        lastSetReps = reps
        reps = 0
        pipeline.resetForNextSet()
        WKInterfaceDevice.current().play(.success)
        onSetFinalized?(setsCompleted, lastSetReps)
    }

    /// Digital Crown / stepper correction of the live rep count. Never goes below 0.
    func adjustReps(by delta: Int) {
        let newValue = max(0, reps + delta)
        guard newValue != reps else { return }
        reps = newValue
        pipeline.overrideReps(newValue)
        WKInterfaceDevice.current().play(.click)
    }

    // MARK: - Workout session

    /// Auto-starts the Health strength workout if it isn't already running, so
    /// the app keeps getting motion with the wrist down and the batched sensor
    /// has an active session to attach to.
    private func ensureWorkoutSession() {
        let session = StrengthWorkoutSession.shared
        guard !session.isActive else { return }
        Task { await session.start() }
    }

    // MARK: - Pipeline wiring

    private func beginPipeline(calibrating: Bool) {
        pipeline.onEvent = { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
        usingHighRate = pipeline.start(calibrating: calibrating,
                                       calibrationTarget: calibrationTarget)
    }

    private func handle(_ event: MotionPipeline.Event) {
        guard isRunning else { return }
        switch event {
        case .update(let snapshot):
            motionLevel = snapshot.motionLevel
            if !isCalibrating { reps = snapshot.reps }
            phase = snapshot.isWorking ? (isCalibrating ? .calibrating : .active) : (isCalibrating ? .calibrating : .resting)

        case .rep(let total):
            if isCalibrating {
                calibrationReps = total
                WKInterfaceDevice.current().play(.click)
            } else {
                reps = total
                WKInterfaceDevice.current().play(.click)
            }

        case .calibrationDone:
            isCalibrating = false
            phase = .resting
            reps = 0
            WKInterfaceDevice.current().play(.notification)

        case .sensorFellBack:
            usingHighRate = false

        case .setFinalized(let setReps):
            setsCompleted += 1
            lastSetReps = setReps
            reps = 0
            phase = .resting
            WKInterfaceDevice.current().play(.success)
            onSetFinalized?(setsCompleted, lastSetReps)
        }
    }
}

// MARK: - Motion pipeline (off-main sensor handling)

/// Owns CoreMotion and the `RepDetector`, processes samples on the sensor
/// callback thread, and emits coalesced events. `@unchecked Sendable` because all
/// mutable state is guarded by `lock` and only touched inside it.
final class MotionPipeline: @unchecked Sendable {

    struct Snapshot: Sendable {
        var reps: Int
        var motionLevel: Double
        var isWorking: Bool
    }

    enum Event: Sendable {
        case update(Snapshot)
        case rep(total: Int)
        case setFinalized(reps: Int)
        case calibrationDone
        /// The batched stream delivered nothing, so counting moved to the 100 Hz fallback.
        case sensorFellBack
    }

    /// Called from a background thread; the receiver hops to the main actor.
    var onEvent: (@Sendable (Event) -> Void)?

    // Tuning for set boundaries.
    private let restToFinalize = 2.5   // seconds of rest that ends a set
    private let minRepsPerSet = 1
    private let uiThrottle = 0.08      // seconds between UI updates (fallback path)
    /// Batches arrive about once a second. Silence this long means the stream
    /// isn't coming (Health denied, or the workout session failed to start).
    private let batchedWatchdog = 5.0

    private let lock = NSLock()
    private let detector = RepDetector()

    // Sensors
    private let batched: CMBatchedSensorManager? = {
        CMBatchedSensorManager.isDeviceMotionSupported ? CMBatchedSensorManager() : nil
    }()
    private let fallback = CMMotionManager()
    private let fallbackQueue = OperationQueue()
    private var usingBatched = false
    private var receivedSample = false
    private var generation = 0

    // State (guarded by lock)
    private var running = false
    private var calibrating = false
    private var calibrationTarget = 4
    private var lastTimestamp = 0.0
    private var lastUIEmit = 0.0
    private var restAccumulator = 0.0
    private var wasWorking = false

    /// Returns true if the high-rate batched sensor is being used.
    func start(calibrating: Bool, calibrationTarget: Int) -> Bool {
        lock.lock()
        running = true
        self.calibrating = calibrating
        self.calibrationTarget = calibrationTarget
        detector.reset()
        lastTimestamp = 0; lastUIEmit = 0; restAccumulator = 0; wasWorking = false
        receivedSample = false
        generation += 1
        let gen = generation
        usingBatched = batched != nil
        lock.unlock()

        guard let batched else {
            startFallback()
            return false
        }
        batched.startDeviceMotionUpdates { [weak self] batch, error in
            guard let self else { return }
            if let batch, !batch.isEmpty { self.ingest(batch) }
            else if error != nil { self.fallBack(from: gen) }
        }
        // The batched stream needs an active workout session and Health access.
        // Without them it is silent, not failing, so watch for the silence.
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + batchedWatchdog) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let silent = self.running && self.usingBatched && self.generation == gen && !self.receivedSample
            self.lock.unlock()
            if silent { self.fallBack(from: gen) }
        }
        return true
    }

    func stop() {
        lock.lock()
        running = false
        let wasBatched = usingBatched
        lock.unlock()
        if wasBatched { batched?.stopDeviceMotionUpdates() }
        else { fallback.stopDeviceMotionUpdates() }
    }

    private func startFallback() {
        guard fallback.isDeviceMotionAvailable else { return }
        fallbackQueue.maxConcurrentOperationCount = 1
        fallback.deviceMotionUpdateInterval = 1.0 / 100.0
        fallback.startDeviceMotionUpdates(to: fallbackQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.ingest([motion])
        }
    }

    /// Swaps the silent batched stream for `CMMotionManager`, once per start.
    private func fallBack(from gen: Int) {
        lock.lock()
        guard running, usingBatched, generation == gen else { lock.unlock(); return }
        usingBatched = false
        lastTimestamp = 0 // the fallback's clock restarts the dt chain
        lock.unlock()
        batched?.stopDeviceMotionUpdates()
        startFallback()
        onEvent?(.sensorFellBack)
    }

    func resetForNextSet() {
        lock.lock(); detector.resetForNextSet(); restAccumulator = 0; wasWorking = false; lock.unlock()
    }

    func overrideReps(_ value: Int) {
        lock.lock(); detector.setReps(value); lock.unlock()
    }

    // MARK: - Sample ingestion (background thread)

    private func ingest(_ batch: [CMDeviceMotion]) {
        var events: [Event] = []
        lock.lock()
        guard running else { lock.unlock(); return }
        receivedSample = true

        for m in batch {
            let t = m.timestamp
            let dt = lastTimestamp > 0 ? t - lastTimestamp : 1.0 / 100.0
            lastTimestamp = t
            guard dt > 0 else { continue }

            let a = m.userAcceleration
            let w = m.rotationRate
            let sample = MotionSample(ax: a.x, ay: a.y, az: a.z, wx: w.x, wy: w.y, wz: w.z, t: t)
            let countedRep = detector.process(sample, dt: dt)

            if countedRep {
                if calibrating {
                    events.append(.rep(total: detector.reps))
                    if detector.reps >= calibrationTarget {
                        // Lock in what we learned, then hand off to live tracking.
                        detector.calibrate(period: detector.learnedPeriod, amplitude: detector.amplitude)
                        detector.resetForNextSet()
                        calibrating = false
                        restAccumulator = 0; wasWorking = false
                        events.append(.calibrationDone)
                    }
                } else {
                    events.append(.rep(total: detector.reps))
                }
            }

            // Set boundary tracking (skip during calibration).
            if !calibrating {
                let working = detector.isWorking
                if working {
                    restAccumulator = 0
                } else if wasWorking || restAccumulator > 0 {
                    restAccumulator += dt
                    if restAccumulator >= restToFinalize {
                        let reps = detector.reps
                        if reps >= minRepsPerSet {
                            events.append(.setFinalized(reps: reps))
                        }
                        detector.resetForNextSet()
                        restAccumulator = 0
                    }
                }
                wasWorking = working
            }

            // Coalesced UI update.
            if t - lastUIEmit >= uiThrottle {
                lastUIEmit = t
                events.append(.update(Snapshot(reps: detector.reps,
                                               motionLevel: detector.motionLevel,
                                               isWorking: detector.isWorking)))
            }
        }
        lock.unlock()

        guard let onEvent else { return }
        for e in events { onEvent(e) }
    }
}
