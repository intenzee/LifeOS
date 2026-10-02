import Foundation
import LifeOSCore

/// What changed in the store. `days` is empty for non-day documents (profile, food library).
public struct StoreChange: Sendable, Equatable {
    public let collection: String
    public let days: Set<DayKey>

    public init(collection: String, days: Set<DayKey>) {
        self.collection = collection
        self.days = days
    }
}

/// Fans store changes out to any number of async subscribers
/// (summary recompute, watch snapshot, widgets).
public final class ChangeBus: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<StoreChange>.Continuation] = [:]

    public init() {}

    /// A new stream of every change published after this call.
    public func changes() -> AsyncStream<StoreChange> {
        let (stream, continuation) = AsyncStream.makeStream(of: StoreChange.self, bufferingPolicy: .unbounded)
        let id = UUID()
        lock.withLock { continuations[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            _ = self.lock.withLock { self.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    public func publish(_ change: StoreChange) {
        let targets = lock.withLock { Array(continuations.values) }
        for continuation in targets { continuation.yield(change) }
    }
}
