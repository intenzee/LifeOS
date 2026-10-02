import Foundation

/// Per-provider request limits and circuit breaker (F01 FR7).
///
/// Free tiers are only free while we stay inside them, so the gateway reserves
/// a slot *before* calling a provider instead of discovering the limit via 429s.
/// Three consecutive provider-side failures open the circuit for a cool-down so
/// a broken engine is skipped instantly instead of costing latency on every call.
actor QuotaManager {

    nonisolated struct Limits: Sendable, Hashable, Codable {
        var perMinute: Int?
        var perDay: Int?

        static let unlimited = Limits(perMinute: nil, perDay: nil)
    }

    nonisolated struct Status: Sendable, Hashable {
        var usedLastMinute: Int
        var usedToday: Int
        var limits: Limits
        var consecutiveFailures: Int
        var circuitOpenUntil: Date?
    }

    private let now: @Sendable () -> Date
    private let failureThreshold: Int
    private let coolDown: TimeInterval
    private var limits: [ProviderID: Limits]
    private var minuteWindow: [ProviderID: [Date]] = [:]
    private var dayCount: [ProviderID: (day: Int, count: Int)] = [:]
    private var consecutiveFailures: [ProviderID: Int] = [:]
    private var openUntil: [ProviderID: Date] = [:]

    init(limits: [ProviderID: Limits] = [:],
         failureThreshold: Int = 3,
         coolDown: TimeInterval = 600,
         now: @escaping @Sendable () -> Date = { Date() }) {
        self.limits = limits
        self.failureThreshold = failureThreshold
        self.coolDown = coolDown
        self.now = now
    }

    func setLimits(_ newLimits: [ProviderID: Limits]) {
        limits = newLimits
    }

    /// Non-consuming check used for availability reporting.
    func check(_ provider: ProviderID) -> AIAvailability {
        let date = now()
        if let until = openUntil[provider], until > date { return .unavailable(.circuitOpen) }
        let limit = limits[provider] ?? .unlimited
        if let perMinute = limit.perMinute, recentCount(provider, at: date) >= perMinute {
            return .unavailable(.quotaExhausted)
        }
        if let perDay = limit.perDay, todayCount(provider, at: date) >= perDay {
            return .unavailable(.quotaExhausted)
        }
        return .available
    }

    /// Consumes one request slot or throws.
    func reserve(_ provider: ProviderID) throws {
        let date = now()
        switch check(provider) {
        case .available:
            break
        case .unavailable(.circuitOpen):
            throw AIError.circuitOpen(provider)
        case .unavailable:
            throw AIError.quotaExhausted(provider)
        }
        if let until = openUntil[provider], until <= date {
            // Half-open: allow one trial request; a failure re-opens immediately.
            openUntil[provider] = nil
            consecutiveFailures[provider] = failureThreshold - 1
        }
        minuteWindow[provider, default: []].append(date)
        let day = Self.dayNumber(date)
        let current = dayCount[provider]
        dayCount[provider] = (day, current?.day == day ? current!.count + 1 : 1)
    }

    func recordSuccess(_ provider: ProviderID) {
        consecutiveFailures[provider] = 0
        openUntil[provider] = nil
    }

    /// Only provider-side faults count toward the breaker; a user's bad key or a
    /// consent refusal says nothing about the engine's health.
    func recordFailure(_ provider: ProviderID, error: AIError) {
        guard Self.countsTowardBreaker(error) else { return }
        let failures = (consecutiveFailures[provider] ?? 0) + 1
        consecutiveFailures[provider] = failures
        if failures >= failureThreshold {
            openUntil[provider] = now().addingTimeInterval(coolDown)
        }
        if case .rateLimited = error {
            // The provider told us we're over; stop asking for the cool-down.
            openUntil[provider] = now().addingTimeInterval(min(coolDown, 60))
        }
    }

    func status(_ provider: ProviderID) -> Status {
        let date = now()
        return Status(usedLastMinute: recentCount(provider, at: date),
                      usedToday: todayCount(provider, at: date),
                      limits: limits[provider] ?? .unlimited,
                      consecutiveFailures: consecutiveFailures[provider] ?? 0,
                      circuitOpenUntil: openUntil[provider].flatMap { $0 > date ? $0 : nil })
    }

    func reset(_ provider: ProviderID) {
        consecutiveFailures[provider] = 0
        openUntil[provider] = nil
        minuteWindow[provider] = nil
        dayCount[provider] = nil
    }

    // MARK: - Private

    private func recentCount(_ provider: ProviderID, at date: Date) -> Int {
        let cutoff = date.addingTimeInterval(-60)
        let kept = (minuteWindow[provider] ?? []).filter { $0 > cutoff }
        minuteWindow[provider] = kept
        return kept.count
    }

    private func todayCount(_ provider: ProviderID, at date: Date) -> Int {
        guard let entry = dayCount[provider], entry.day == Self.dayNumber(date) else { return 0 }
        return entry.count
    }

    private static func dayNumber(_ date: Date) -> Int {
        // Provider quotas reset on UTC days.
        Int(date.timeIntervalSince1970 / 86_400)
    }

    static func countsTowardBreaker(_ error: AIError) -> Bool {
        switch error {
        case .network, .server, .timeout, .invalidOutput, .noModelAvailable, .modelRetired, .rateLimited:
            return true
        default:
            return false
        }
    }
}
