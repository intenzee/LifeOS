import Foundation
import OSLog

/// Loggers for the AI layer (F01 FR14, audit B10). Content is always logged
/// with `privacy: .private`; codes, providers and timings are public.
nonisolated enum AILog {
    static let subsystem = "app.lifeos.ai"
    static let gateway = Logger(subsystem: subsystem, category: "gateway")
    static let provider = Logger(subsystem: subsystem, category: "provider")
    static let signposter = OSSignposter(subsystem: subsystem, category: .pointsOfInterest)
}

/// One gateway request outcome. Deliberately content-free so it can be shown in
/// the diagnostics screen and exported (opt-in) without leaking user data.
nonisolated struct AIEvent: Codable, Sendable, Identifiable, Hashable {
    nonisolated enum Outcome: String, Codable, Sendable {
        case success, cacheHit, failed
    }

    var id: UUID
    var date: Date
    var task: AITask
    var provider: ProviderID?
    var model: String?
    var outcome: Outcome
    var errorCode: String?
    var latencyMs: Int
    var promptVersion: String
    var attempts: [Attempt]

    nonisolated struct Attempt: Codable, Sendable, Hashable {
        var provider: ProviderID
        var errorCode: String
        var latencyMs: Int
    }
}

/// Ring buffer of recent events, plus aggregate counters, for "AI diagnostics".
actor AIEventLog {
    private let capacity: Int
    private(set) var events: [AIEvent] = []
    private var continuations: [UUID: AsyncStream<AIEvent>.Continuation] = [:]

    init(capacity: Int = 200) { self.capacity = capacity }

    func record(_ event: AIEvent) {
        events.append(event)
        if events.count > capacity { events.removeFirst(events.count - capacity) }
        for continuation in continuations.values { continuation.yield(event) }
    }

    func recent(_ limit: Int = 50) -> [AIEvent] { Array(events.suffix(limit).reversed()) }

    func clear() { events = [] }

    /// Live feed for the diagnostics screen.
    func updates() -> AsyncStream<AIEvent> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AIEvent>.makeStream()
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return stream
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }

    nonisolated struct Summary: Sendable, Hashable {
        var task: AITask
        var provider: ProviderID?
        var count: Int
        var failures: Int
        var p50Ms: Int
        var p95Ms: Int
    }

    func summary() -> [Summary] {
        let grouped = Dictionary(grouping: events) { "\($0.task.rawValue)|\($0.provider?.rawValue ?? "-")" }
        return grouped.values.compactMap { group -> Summary? in
            guard let first = group.first else { return nil }
            let latencies = group.map(\.latencyMs).sorted()
            return Summary(task: first.task, provider: first.provider, count: group.count,
                           failures: group.filter { $0.outcome == .failed }.count,
                           p50Ms: Self.percentile(latencies, 0.5), p95Ms: Self.percentile(latencies, 0.95))
        }
        .sorted { ($0.task.rawValue, $0.provider?.rawValue ?? "") < ($1.task.rawValue, $1.provider?.rawValue ?? "") }
    }

    static func percentile(_ sorted: [Int], _ p: Double) -> Int {
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int((Double(sorted.count - 1) * p).rounded()))
        return sorted[index]
    }
}

nonisolated extension Duration {
    nonisolated var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds) * 1_000 + Int(attoseconds / 1_000_000_000_000_000)
    }
}
