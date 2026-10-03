import Foundation
import LifeOSAPI

/// The LifeOS AI proxy (doc 07, BE-11) as a gateway provider.
///
/// Off by default: `LifeOSProxy.makeClient()` returns `nil` until the proxy is
/// deployed and the flag is set, so nothing here runs in shipping builds yet.
/// The provider id is injected by whoever registers it with the router (the AI
/// team owns `ProviderID` and the chains). It must be a T3 id: the proxy sends
/// the prompt to Groq, so the third-party consent and redaction rules apply
/// exactly as they do for BYOK.
///
/// Prompts stay with the gateway: the body is the BYOK Groq body, and the proxy
/// replaces the model, caps the tokens and keeps the key.
nonisolated struct ProxyAIProvider: AIProvider {
    let id: ProviderID
    let capabilities: Set<AICapability> = [.text, .vision, .streaming]

    private let client: LifeOSAPIClient

    init(id: ProviderID, client: LifeOSAPIClient) {
        self.id = id
        self.client = client
    }

    func availability(for task: AITask) async -> AIAvailability {
        // Cached for an hour; an unreachable config isn't a reason to skip the proxy.
        let route = Self.route(for: task, hasImages: Self.photoTasks.contains(task))
        if let config = try? await client.remoteConfig(), config.isDisabled(route) {
            return .unavailable(.disabledByConfig)
        }
        return .available
    }

    func generate(_ call: ProviderCall) async throws -> ProviderResponse {
        let route = Self.route(for: call.task, hasImages: !call.input.images.isEmpty)
        let response: APIResponse
        do {
            response = try await client.complete(route, body: Self.body(for: call))
        } catch {
            throw Self.aiError(error, provider: id)
        }
        if Self.isGuardrailStop(response.body) { throw AIError.guardrail }
        guard let content = response.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.invalidOutput("empty completion")
        }
        return ProviderResponse(raw: content, model: response.model ?? "proxy")
    }

    /// Plain-text chat streams through `/v1/chat`; everything else is one answer.
    func stream(_ call: ProviderCall) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard call.outputIsPlainText, call.input.images.isEmpty else {
                        continuation.yield(try await generate(call).raw)
                        continuation.finish()
                        return
                    }
                    var text = ""
                    for try await payload in try await client.stream(body: Self.body(for: call)) {
                        if Self.isGuardrailStop(Data(payload.utf8)) { throw AIError.guardrail }
                        guard let delta = Self.delta(in: payload), !delta.isEmpty else { continue }
                        text += delta
                        continuation.yield(text)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.aiError(error, provider: id))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Mapping

    /// Photos and labels go to the vision route; the food sentence to the parse
    /// route, whose answer must carry `items`; every other text task is chat.
    static func route(for task: AITask, hasImages: Bool) -> AIRoute {
        if hasImages { return .visionMeal }
        return task == .foodTextParse ? .parseMeal : .chat
    }

    static let photoTasks: Set<AITask> = [.mealPhotoAnalyze, .mealPhotoRefine, .nutritionLabelRead]

    /// The BYOK body without `model`.
    static func body(for call: ProviderCall) -> Data {
        var body = GroqBYOKProvider.body(for: call, model: "")
        if case .object(let members) = body { body = .object(members.filter { $0.key != "model" }) }
        return RESTBody.data(body)
    }

    /// `choices[0].delta.content` of a streamed chunk.
    static func delta(in payload: String) -> String? {
        (try? JSONDecoder().decode(CompletionChunk.self, from: Data(payload.utf8)))?.choices.first?.delta?.content
    }

    /// A refusal or a content-filter stop, in a completion or a streamed chunk.
    /// Mapped to `.guardrail` so the gateway doesn't hand the same request to
    /// the next provider (unless the task allows it).
    static func isGuardrailStop(_ body: Data) -> Bool {
        guard let choice = (try? JSONDecoder().decode(CompletionChunk.self, from: body))?.choices.first else {
            return false
        }
        let refusal = choice.message?.refusal ?? choice.delta?.refusal
        return choice.finishReason == "content_filter" || !(refusal ?? "").isEmpty
    }

    // One case per `LifeOSAPIError`: splitting the switch would only hide that.
    // swiftlint:disable:next cyclomatic_complexity
    static func aiError(_ error: Error, provider: ProviderID) -> AIError {
        if let error = error as? AIError { return error }
        guard let error = error as? LifeOSAPIError else {
            return error is CancellationError ? .cancelled : .network(String(describing: error))
        }
        switch error {
        case .unavailable: return .unavailable(.missingCredential)
        case .attestationFailed, .unauthorized: return .authFailed(provider)
        case .quotaExceeded: return .quotaExhausted(provider)
        case .rateLimited: return .rateLimited(provider)
        case .serviceBusy: return .circuitOpen(provider)
        case .disabled: return .unavailable(.disabledByConfig)
        case .badRequest: return .unsupportedInput
        case .notFound: return .server(404)
        case .noModelAvailable: return .noModelAvailable
        case .server(let status): return .server(status)
        case .network(let message): return .network(message)
        case .invalidResponse: return .invalidOutput("unreadable proxy response")
        case .cancelled: return .cancelled
        }
    }
}

/// The parts of an OpenAI-compatible completion or streamed chunk the provider reads.
nonisolated private struct CompletionChunk: Decodable {
    struct Choice: Decodable {
        let message: Message?
        let delta: Message?
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message, delta
            case finishReason = "finish_reason"
        }
    }

    struct Message: Decodable {
        let content: String?
        let refusal: String?
    }

    let choices: [Choice]
}

/// Where the proxy client comes from. Both settings are off until BE-09 deploys
/// the proxy; the debug token exists only in DEBUG builds, for the dev proxy.
nonisolated enum LifeOSProxy {
    static let enabledKey = "lx.proxy.enabled"
    static let baseURLKey = "lx.proxy.baseURL"
    static let debugTokenKey = "lx.proxy.debugToken"

    /// One client per process: it serialises assertion counters.
    static func makeClient(defaults: UserDefaults = .standard) -> LifeOSAPIClient? {
        lock.withLock { () -> LifeOSAPIClient? in
            if let shared { return shared }
            guard defaults.bool(forKey: enabledKey),
                  let raw = defaults.string(forKey: baseURLKey), let baseURL = URL(string: raw),
                  baseURL.scheme == "https" else { return nil }
            var debugToken: String?
            #if DEBUG
            debugToken = defaults.string(forKey: debugTokenKey)
            #endif
            let client = LifeOSAPIClient(configuration: .init(baseURL: baseURL, debugToken: debugToken),
                                         attest: SystemAppAttest(), deviceCheck: SystemDeviceCheck(),
                                         store: KeychainAPICredentialStore())
            shared = client
            return client
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var shared: LifeOSAPIClient?
}
