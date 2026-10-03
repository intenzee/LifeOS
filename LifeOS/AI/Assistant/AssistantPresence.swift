import Foundation
import Observation

/// The single state the assistant's orb / 3D visual binds to (contract C9).
nonisolated enum AssistantVisualState: Equatable, Sendable {
    case idle
    /// 0…1 microphone level for reactive animation.
    case listening(level: Double)
    case thinking
    /// Streaming progress 0…1 (by phrases revealed).
    case speaking(progress: Double)
    case success
    case error
}

/// Main-actor observable presence. State changes are coalesced to ≤ 30 Hz so a
/// mic meter or token stream can't flood SwiftUI (C9 guarantee).
@MainActor
@Observable
final class AssistantPresence {
    static let shared = AssistantPresence()

    private(set) var state: AssistantVisualState = .idle
    @ObservationIgnored private var lastEmit = Date.distantPast
    @ObservationIgnored private var pending: AssistantVisualState?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private let minInterval: TimeInterval

    init(maxHz: Double = 30) {
        minInterval = 1 / maxHz
    }

    func set(_ new: AssistantVisualState, now: Date = Date()) {
        // Discrete transitions (idle/thinking/success/error) always land at once;
        // continuous values (level, progress) are throttled.
        let continuous: Bool
        switch (state, new) {
        case (.listening, .listening), (.speaking, .speaking): continuous = true
        default: continuous = false
        }
        guard continuous, now.timeIntervalSince(lastEmit) < minInterval else {
            emit(new, at: now)
            return
        }
        pending = new
        guard flushTask == nil else { return }
        let delay = minInterval - now.timeIntervalSince(lastEmit)
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(max(0, delay) * 1_000)))
            guard let self, let pending = self.pending else { return }
            self.emit(pending, at: Date())
        }
    }

    private func emit(_ new: AssistantVisualState, at date: Date) {
        flushTask?.cancel()
        flushTask = nil
        pending = nil
        lastEmit = date
        if state != new { state = new }
    }

    /// Success and error flash, then settle back to idle.
    func flash(_ new: AssistantVisualState, for seconds: Double = 1.2) {
        set(new)
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int(seconds * 1_000)))
            guard let self, self.state == new else { return }
            self.set(.idle)
        }
    }
}
