import Foundation

/// A fully rendered prompt from the registry (F01 FR10). The `id` + `version`
/// pair is recorded in every result so evals can trace answers to prompt text.
nonisolated struct AIPrompt: Sendable, Hashable {
    var id: String
    var version: String
    /// System-level instructions.
    var instructions: String
    /// The user turn, with any user content already wrapped as quoted data.
    var user: String
    /// True when `user`/`instructions` already spell out the JSON contract (e.g.
    /// the legacy Groq meal prompt). Otherwise REST providers append one.
    var embedsSchema: Bool

    init(id: String, version: String, instructions: String, user: String, embedsSchema: Bool = false) {
        self.id = id
        self.version = version
        self.instructions = instructions
        self.user = user
        self.embedsSchema = embedsSchema
    }
}

/// The type-erased call a provider executes. Providers never see `Output`; they
/// return raw text and the gateway validates and decodes centrally, so every
/// engine is held to the same contract.
nonisolated struct ProviderCall: Sendable {
    var task: AITask
    var prompt: AIPrompt
    var input: AIInput
    /// Already privacy-filtered for this provider's tier.
    var context: ContextPacket?
    var schema: AISchema
    var outputIsPlainText: Bool
    var generation: AIGenerationOptions
    /// Set on the repair retry: what was wrong with `previousRaw`.
    var repairFeedback: String?
    var previousRaw: String?
    /// Per-request BYOK key (see `AIRequest.credentialOverrides`).
    var apiKeyOverride: String?

    /// Instructions with the rendered context appended as clearly-delimited data.
    var fullInstructions: String {
        guard let context, !context.isEmpty else { return prompt.instructions }
        return prompt.instructions + "\n\n" + context.rendered()
    }

    /// The user turn including repair feedback, if any.
    var fullUserText: String {
        guard let repairFeedback else { return prompt.user }
        var text = prompt.user
        if let previousRaw { text += "\n\nYour previous reply:\n\(previousRaw.prefix(2_000))" }
        return text + "\n\n" + repairFeedback
    }
}

nonisolated struct TokenUsage: Sendable, Hashable, Codable {
    var input: Int?
    var output: Int?
}

nonisolated struct ProviderResponse: Sendable {
    var raw: String
    var model: String
    var usage: TokenUsage?

    init(raw: String, model: String, usage: TokenUsage? = nil) {
        self.raw = raw
        self.model = model
        self.usage = usage
    }
}

/// One engine behind the gateway (F01 FR2). Implementations throw `AIError`.
nonisolated protocol AIProvider: Sendable {
    var id: ProviderID { get }
    var capabilities: Set<AICapability> { get }
    /// Cheap, cached where possible; called before every attempt.
    func availability(for task: AITask) async -> AIAvailability
    func generate(_ call: ProviderCall) async throws -> ProviderResponse
    /// Streams cumulative text snapshots. Default: one snapshot from `generate`.
    func stream(_ call: ProviderCall) -> AsyncThrowingStream<String, Error>
    /// Warm the engine ahead of a likely request (e.g. sheet opened).
    func prewarm(for task: AITask) async
    /// Fast local engines (T0/T4) are exempt from the latency deadline so the
    /// chain can always end in *some* answer.
    var isLocalFallback: Bool { get }
}

nonisolated extension AIProvider {
    func stream(_ call: ProviderCall) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let response = try await self.generate(call)
                    continuation.yield(response.raw)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    func prewarm(for task: AITask) async {}

    var isLocalFallback: Bool { id.tier == .t0 || id.tier == .t4 }
}

/// A provider backed by plain Swift closures, one per task. Used for the
/// deterministic tier (rules, templates) and the legacy Vision tier, whose
/// handlers live next to the data they need.
nonisolated struct LocalHandlerProvider: AIProvider {
    typealias Handler = @Sendable (ProviderCall) async throws -> String

    let id: ProviderID
    let capabilities: Set<AICapability>
    private let handlers: [AITask: Handler]

    init(id: ProviderID, capabilities: Set<AICapability> = [.text], handlers: [AITask: Handler]) {
        self.id = id
        self.capabilities = capabilities
        self.handlers = handlers
    }

    func adding(_ task: AITask, _ handler: @escaping Handler) -> LocalHandlerProvider {
        var copy = handlers
        copy[task] = handler
        return LocalHandlerProvider(id: id, capabilities: capabilities, handlers: copy)
    }

    func availability(for task: AITask) async -> AIAvailability {
        handlers[task] == nil ? .unavailable(.notImplemented) : .available
    }

    func generate(_ call: ProviderCall) async throws -> ProviderResponse {
        guard let handler = handlers[call.task] else { throw AIError.unavailable(.notImplemented) }
        try Task.checkCancellation()
        return ProviderResponse(raw: try await handler(call), model: "\(id.rawValue).\(call.task.rawValue)")
    }
}
