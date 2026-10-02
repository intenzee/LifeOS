import Foundation

/// Scripted provider for unit tests, evals and SwiftUI previews (F01 FR15).
///
/// Each call pops the next scripted step; when the script runs out the last
/// step repeats. Records every call so tests can assert on what was sent.
nonisolated final class MockAIProvider: AIProvider, @unchecked Sendable {
    nonisolated enum Step: Sendable {
        case respond(String)
        case fail(AIError)
        /// Waits before responding — for timeout and cancellation tests.
        case delay(Duration, then: String)
        /// Runs a closure on the call — for content-dependent fakes.
        case compute(@Sendable (ProviderCall) throws -> String)
    }

    let id: ProviderID
    let capabilities: Set<AICapability>
    private let lock = NSLock()
    private var script: [Step]
    private var _availability: AIAvailability
    private var _calls: [ProviderCall] = []

    init(id: ProviderID, capabilities: Set<AICapability> = [.text, .vision, .streaming],
         availability: AIAvailability = .available, script: [Step]) {
        self.id = id
        self.capabilities = capabilities
        self._availability = availability
        self.script = script
    }

    convenience init(id: ProviderID, responding raw: String) {
        self.init(id: id, script: [.respond(raw)])
    }

    var calls: [ProviderCall] { lock.withLock { _calls } }
    var callCount: Int { lock.withLock { _calls.count } }

    func setAvailability(_ availability: AIAvailability) { lock.withLock { _availability = availability } }
    func setScript(_ steps: [Step]) { lock.withLock { script = steps } }

    func availability(for task: AITask) async -> AIAvailability { lock.withLock { _availability } }

    func generate(_ call: ProviderCall) async throws -> ProviderResponse {
        let step: Step = lock.withLock {
            _calls.append(call)
            if script.count > 1 { return script.removeFirst() }
            return script.first ?? .fail(.noModelAvailable)
        }
        switch step {
        case .respond(let raw):
            return ProviderResponse(raw: raw, model: "mock-\(id.rawValue)")
        case .fail(let error):
            throw error
        case .delay(let duration, let raw):
            try await Task.sleep(for: duration)
            return ProviderResponse(raw: raw, model: "mock-\(id.rawValue)")
        case .compute(let body):
            return ProviderResponse(raw: try body(call), model: "mock-\(id.rawValue)")
        }
    }
}
