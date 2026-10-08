import Foundation

// The rep-counting *brain*, kept free of CoreMotion and SwiftUI so it can be
// reasoned about and unit-tested on any platform. `AutoSetTracker` owns the
// sensors and feeds samples in; this file turns raw wrist motion into reps.
//
// ## Why this is more accurate than peak-counting
// A single rep is **one full out-and-back motion**, and it produces several
// acceleration bursts (drive out, decelerate, reverse, decelerate), so naive
// "count the acceleration peaks" over-counts 2–4×. Good trackers condition the
// signal first, then count *cycles*. We do four things, in order:
//
// 1. **Dominant-axis projection (PCA).** The wrist swings along one main line
//    per exercise (curl = vertical-ish, row = horizontal-ish). We track that
//    line continuously with an exponentially-weighted covariance of the
//    gravity-removed acceleration and one power-iteration step per sample, then
//    project onto it. This collapses the 3-D swing into a clean 1-D signal `s`
//    that self-calibrates to any movement — no hard-coded axes.
// 2. **Band-pass filter.** Reps live at ~0.3–2 Hz. A slow high-pass removes
//    gravity leak / orientation drift; a fast low-pass removes jitter. What's
//    left oscillates once per rep.
// 3. **Adaptive peak/valley state machine with hysteresis.** A rep is a strong
//    positive lobe followed by a strong negative lobe (or vice-versa), measured
//    against a decaying amplitude envelope — not a fixed threshold — so light
//    and heavy sets both count.
// 4. **Cadence gating.** Once a few reps are seen we learn the rep period and
//    reject anything far faster than that, which kills bounce and re-grip noise.
//
// All thresholds are relative and documented. They are good defaults; final
// per-user tuning needs real lifting data (see `RepDetector.Config`).

/// One conditioned motion sample. `a*` is user acceleration (gravity already
/// removed) in g; `w*` is rotation rate in rad/s; `t` is a monotonic timestamp
/// in seconds. Gravity is only needed for the work/rest envelope.
struct MotionSample {
    var ax: Double, ay: Double, az: Double
    var wx: Double, wy: Double, wz: Double
    var t: Double
}

final class RepDetector {

    /// Tunable constants. Defaults are conservative, middle-of-the-road values;
    /// `calibrate(period:amplitude:)` adapts the two that matter most per set.
    struct Config {
        /// Covariance memory for the dominant axis (seconds). Long enough to be
        /// stable across a rep, short enough to re-learn between exercises.
        var axisTau = 1.2
        /// High-pass time constant (seconds): removes gravity leak & drift.
        var highPassTau = 1.4
        /// Low-pass time constant (seconds): removes sensor jitter.
        var lowPassTau = 0.07
        /// Amplitude-envelope decay (seconds): how fast the "typical swing size"
        /// is forgotten, so the threshold tracks the current set.
        var envTau = 0.9
        /// A lobe counts when |s| exceeds this fraction of the envelope …
        var enterK = 0.45
        /// … and the opposite lobe is armed again only after |s| falls back under
        /// this smaller fraction (hysteresis, kills double-counts on one swing).
        var exitK = 0.18
        /// Absolute floor on the lobe threshold (g) so stillness never counts.
        var floorAmp = 0.012
        /// Fastest believable rep (seconds). ~2.9 reps/s hard ceiling.
        var minPeriod = 0.35
        /// Slowest rep before a half-cycle is considered stalled and forgotten.
        var maxPeriod = 6.0
        /// Reject a rep arriving sooner than this fraction of the learned median
        /// cadence (catches bounces between real reps).
        var cadenceGate = 0.5
    }

    private let config: Config
    init(config: Config = Config()) { self.config = config }

    // MARK: - Outputs (read after each `process`)

    private(set) var reps = 0
    /// Smoothed 0…1 "how hard is the wrist moving" for the live UI meter.
    private(set) var motionLevel = 0.0
    /// Conditioned 1-D rep signal, exposed for debugging/visualisation.
    private(set) var signal = 0.0

    // MARK: - Dominant-axis (power iteration on exp. covariance)

    private var cxx = 0.0, cyy = 0.0, czz = 0.0
    private var cxy = 0.0, cxz = 0.0, cyz = 0.0
    private var ux = 0.0, uy = 1.0, uz = 0.0   // current axis estimate
    private var axisSeeded = false

    // MARK: - Filters

    private var hp = 0.0          // high-pass state (slow mean of projection)
    private var lp = 0.0          // low-pass state (final signal)
    private var env = 0.0         // amplitude envelope of |s|

    // MARK: - Rep state machine

    private var armedPositive = true   // ready to accept a positive lobe
    private var armedNegative = true
    private var sawPositive = false
    private var sawNegative = false
    private var lastRepTime = 0.0
    private var lastLobeTime = 0.0
    private var medianPeriod = 0.0     // learned cadence (seconds)

    // MARK: - Work/rest envelope (RMS of motion magnitude)

    private var rmsEnergy = 0.0
    private var restFloor = 0.0
    private var restFloorSeeded = false
    /// True while the wrist is actively working (above the learned rest floor).
    private(set) var isWorking = false

    func reset() {
        reps = 0; motionLevel = 0; signal = 0
        cxx = 0; cyy = 0; czz = 0; cxy = 0; cxz = 0; cyz = 0
        ux = 0; uy = 1; uz = 0; axisSeeded = false
        hp = 0; lp = 0; env = 0
        armedPositive = true; armedNegative = true
        sawPositive = false; sawNegative = false
        lastRepTime = 0; lastLobeTime = 0; medianPeriod = 0
        rmsEnergy = 0; restFloor = 0; restFloorSeeded = false; isWorking = false
    }

    /// Clears the per-set counters but keeps everything the detector *learned*
    /// (dominant axis, filter state, amplitude envelope and cadence), so set two
    /// starts already tuned to how you're lifting today.
    func resetForNextSet() {
        reps = 0; signal = 0
        armedPositive = true; armedNegative = true
        sawPositive = false; sawNegative = false
        lastRepTime = 0; lastLobeTime = 0
    }

    /// Overrides the live rep count (Digital Crown correction). Keeps the signal
    /// state so counting continues cleanly from the corrected value.
    func setReps(_ value: Int) { reps = max(0, value) }

    /// Learned rep cadence in seconds (0 until a couple of reps are seen).
    var learnedPeriod: Double { medianPeriod }
    /// Current amplitude envelope of the conditioned signal.
    var amplitude: Double { env }

    /// Seeds the cadence and amplitude from a short calibration set, so the very
    /// first working set is already gated correctly.
    func calibrate(period: Double, amplitude: Double) {
        if period > config.minPeriod, period < config.maxPeriod { medianPeriod = period }
        if amplitude > 0 { env = max(env, amplitude) }
    }

    /// Feeds one sample. Returns `true` exactly on the sample a rep is counted.
    @discardableResult
    func process(_ s: MotionSample, dt rawDt: Double) -> Bool {
        let dt = min(max(rawDt, 1.0 / 400.0), 1.0 / 20.0) // clamp odd gaps

        updateAxis(ax: s.ax, ay: s.ay, az: s.az, dt: dt)

        // Project gravity-free acceleration onto the dominant axis.
        let p = s.ax * ux + s.ay * uy + s.az * uz

        // Band-pass: subtract slow mean (high-pass), then smooth (low-pass).
        hp += (p - hp) * (dt / config.highPassTau)
        let band = p - hp
        lp += (band - lp) * (dt / config.lowPassTau)
        signal = lp

        // Amplitude envelope: rise instantly to a new peak, decay slowly.
        let mag = abs(lp)
        if mag > env { env = mag } else { env += (mag - env) * (dt / config.envTau) }

        let counted = updateRepMachine(s: lp, t: s.t)
        updateEnergy(sample: s, dt: dt)
        return counted
    }

    // MARK: - Dominant axis

    private func updateAxis(ax: Double, ay: Double, az: Double, dt: Double) {
        let a = dt / config.axisTau
        let b = 1 - a
        cxx = b * cxx + a * ax * ax
        cyy = b * cyy + a * ay * ay
        czz = b * czz + a * az * az
        cxy = b * cxy + a * ax * ay
        cxz = b * cxz + a * ax * az
        cyz = b * cyz + a * ay * az

        // One power-iteration step: u' = C · u, then normalise. Converges to the
        // top eigenvector (the direction of greatest acceleration variance).
        let nx = cxx * ux + cxy * uy + cxz * uz
        let ny = cxy * ux + cyy * uy + cyz * uz
        let nz = cxz * ux + cyz * uy + czz * uz
        let n = sqrt(nx * nx + ny * ny + nz * nz)
        guard n > 1e-9 else { return }
        var vx = nx / n, vy = ny / n, vz = nz / n
        // Keep the axis sign continuous so the projection doesn't flip mid-rep.
        if vx * ux + vy * uy + vz * uz < 0 { vx = -vx; vy = -vy; vz = -vz }
        if !axisSeeded {
            ux = vx; uy = vy; uz = vz; axisSeeded = true
        } else {
            // Light smoothing on top of the iteration for extra stability.
            let s = 0.25
            ux += (vx - ux) * s; uy += (vy - uy) * s; uz += (vz - uz) * s
            let m = sqrt(ux * ux + uy * uy + uz * uz)
            if m > 1e-9 { ux /= m; uy /= m; uz /= m }
        }
    }

    // MARK: - Rep state machine (hysteresis + cadence gate)

    private func updateRepMachine(s: Double, t: Double) -> Bool {
        let enter = max(config.enterK * env, config.floorAmp)
        let exit = max(config.exitK * env, config.floorAmp * 0.5)

        // Drop a stalled half-cycle (a long pause mid-rep) so it can't pair up
        // with the next swing into a phantom rep.
        if lastLobeTime > 0, t - lastLobeTime > config.maxPeriod {
            sawPositive = false; sawNegative = false
            armedPositive = true; armedNegative = true
        }

        // Positive lobe.
        if s > enter, armedPositive {
            sawPositive = true; armedPositive = false; lastLobeTime = t
        } else if s < exit, !armedPositive, s < enter * 0.5 {
            armedPositive = true // re-arm once we've clearly come back down
        }
        // Negative lobe.
        if s < -enter, armedNegative {
            sawNegative = true; armedNegative = false; lastLobeTime = t
        } else if s > -exit, !armedNegative, s > -enter * 0.5 {
            armedNegative = true
        }

        guard sawPositive, sawNegative else { return false }

        // A full cycle is ready. Gate on cadence.
        let since = lastRepTime > 0 ? t - lastRepTime : .greatestFiniteMagnitude
        let minGap = max(config.minPeriod, medianPeriod * config.cadenceGate)
        guard since >= minGap else {
            // Too soon — treat as noise, re-arm without counting.
            sawPositive = false; sawNegative = false
            return false
        }

        reps += 1
        if lastRepTime > 0 { learnCadence(interval: since) }
        lastRepTime = t
        sawPositive = false; sawNegative = false
        return true
    }

    /// Robust-ish running median via a slow pull toward recent intervals, kept in
    /// the believable rep range.
    private func learnCadence(interval: Double) {
        guard interval > config.minPeriod, interval < config.maxPeriod else { return }
        if medianPeriod == 0 { medianPeriod = interval }
        else { medianPeriod += (interval - medianPeriod) * 0.25 }
    }

    // MARK: - Work / rest energy

    private func updateEnergy(sample s: MotionSample, dt: Double) {
        let accelMag = sqrt(s.ax * s.ax + s.ay * s.ay + s.az * s.az)
        let gyroMag = sqrt(s.wx * s.wx + s.wy * s.wy + s.wz * s.wz)
        let move = accelMag + 0.12 * gyroMag
        // Sliding RMS via EMA of the square.
        rmsEnergy += (move * move - rmsEnergy) * (dt / 0.4)
        let rms = sqrt(max(rmsEnergy, 0))

        if !restFloorSeeded { restFloor = rms; restFloorSeeded = true }
        if !isWorking { restFloor += (rms - restFloor) * (dt / 0.7) } // learn rest only while resting

        let enter = max(0.030, restFloor * 2.6)
        let exit = max(0.018, restFloor * 1.7)
        if isWorking {
            if rms < exit { isWorking = false }
        } else {
            if rms > enter { isWorking = true }
        }
        motionLevel = min(rms / max(enter, 1e-4), 1.0)
    }
}
