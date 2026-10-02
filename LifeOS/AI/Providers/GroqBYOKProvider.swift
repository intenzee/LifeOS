import Foundation

/// T3 — Groq (OpenAI-compatible chat completions) with the user's own key.
///
/// A port of `GroqMealAnalyzer`'s networking behind the gateway, generalised to
/// any task: prioritised model list (now from remote config, FR8), retired
/// models skipped automatically, JSON mode, one retry with backoff, and a model
/// that answers in prose is skipped like the legacy `badResponse` path.
nonisolated struct GroqBYOKProvider: AIProvider {
    let id: ProviderID = .groqBYOK
    let capabilities: Set<AICapability> = [.text, .vision]

    private let credentials: any AICredentialProviding
    private let models: @Sendable (_ vision: Bool) async -> [String]
    private let transport: RESTTransport
    private let endpoint = URL(string: "https://api.groq.com/openai/v1/chat/completions")!

    init(credentials: any AICredentialProviding,
         models: @escaping @Sendable (_ vision: Bool) async -> [String],
         session: URLSession = RESTTransport.defaultSession()) {
        self.credentials = credentials
        self.models = models
        self.transport = RESTTransport(session: session, provider: .groqBYOK)
    }

    /// Test seam: custom transport (e.g. no-sleep backoff).
    init(credentials: any AICredentialProviding,
         models: @escaping @Sendable (_ vision: Bool) async -> [String],
         transport: RESTTransport) {
        self.credentials = credentials
        self.models = models
        self.transport = transport
    }

    func availability(for task: AITask) async -> AIAvailability {
        credentials.apiKey(for: id) == nil ? .unavailable(.missingCredential) : .available
    }

    func generate(_ call: ProviderCall) async throws -> ProviderResponse {
        guard let key = call.apiKeyOverride ?? credentials.apiKey(for: id) else {
            throw AIError.unavailable(.missingCredential)
        }
        let candidates = await models(!call.input.images.isEmpty)
        var lastRecoverable: AIError = .noModelAvailable

        for model in candidates {
            do {
                let content = try await complete(call, model: model, key: key)
                if !call.outputIsPlainText, !containsJSONObject(content) {
                    lastRecoverable = .invalidOutput("model \(model) did not return JSON")
                    continue
                }
                return ProviderResponse(raw: content, model: model)
            } catch let error as AIError {
                switch error {
                case .noModelAvailable, .modelRetired, .invalidOutput, .server:
                    // This model is gone or misbehaving — try the next candidate.
                    lastRecoverable = error
                    continue
                default:
                    // Auth, rate limit, network, cancellation: not the model's fault.
                    throw error
                }
            }
        }
        throw lastRecoverable
    }

    // MARK: - Request

    private func complete(_ call: ProviderCall, model: String, key: String) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = RESTBody.data(Self.body(for: call, model: model))

        let data = try await transport.send(request)
        guard let decoded = try? JSONDecoder().decode(ChatResponse.self, from: data),
              let content = decoded.choices.first?.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIError.invalidOutput("empty completion")
        }
        return content
    }

    /// Request body. For the meal-photo prompts this is byte-for-byte the legacy
    /// payload: same system/user text, temperature 0.2, max_tokens 900, JSON mode.
    static func body(for call: ProviderCall, model: String) -> JSONValue {
        var userText = call.fullUserText
        if !call.outputIsPlainText, !call.prompt.embedsSchema {
            userText += "\n\n" + call.schema.promptInstruction()
        }

        let userContent: JSONValue
        if call.input.images.isEmpty {
            userContent = .string(userText)
        } else {
            var parts: [JSONValue] = [.object([.init("type", .string("text")), .init("text", .string(userText))])]
            for image in call.input.images {
                parts.append(.object([
                    .init("type", .string("image_url")),
                    .init("image_url", .object([.init("url", .string(image.dataURL))])),
                ]))
            }
            userContent = .array(parts)
        }

        var members: [JSONValue.Member] = [
            .init("model", .string(model)),
            .init("temperature", .number(call.generation.temperature ?? 0.2)),
            .init("max_tokens", .number(Double(call.generation.maxOutputTokens ?? 900))),
        ]
        if !call.outputIsPlainText {
            members.append(.init("response_format", .object([.init("type", .string("json_object"))])))
        }
        members.append(.init("messages", .array([
            .object([.init("role", .string("system")), .init("content", .string(call.fullInstructions))]),
            .object([.init("role", .string("user")), .init("content", userContent)]),
        ])))
        return .object(members)
    }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String? }
        let choices: [Choice]
    }
}
