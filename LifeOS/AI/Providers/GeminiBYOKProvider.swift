import Foundation

/// T3 — Google Gemini API (AI Studio free tier) with the user's own key.
///
/// Note for product/legal (master plan §3): a Google One / AI Pro subscription
/// does not include API access, and the free tier may use content to improve
/// Google's products — hence opt-in consent only, enforced by the privacy gate.
nonisolated struct GeminiBYOKProvider: AIProvider {
    let id: ProviderID = .geminiBYOK
    let capabilities: Set<AICapability> = [.text, .vision, .longContext]

    private let credentials: any AICredentialProviding
    private let models: @Sendable () async -> [String]
    private let transport: RESTTransport
    private let baseURL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/")!

    init(credentials: any AICredentialProviding,
         models: @escaping @Sendable () async -> [String],
         session: URLSession = RESTTransport.defaultSession()) {
        self.credentials = credentials
        self.models = models
        self.transport = RESTTransport(session: session, provider: .geminiBYOK)
    }

    init(credentials: any AICredentialProviding,
         models: @escaping @Sendable () async -> [String],
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
        var lastRecoverable: AIError = .noModelAvailable
        for model in await models() {
            do {
                let text = try await generateContent(call, model: model, key: key)
                return ProviderResponse(raw: text, model: model)
            } catch let error as AIError {
                switch error {
                case .noModelAvailable, .modelRetired, .server, .invalidOutput:
                    lastRecoverable = error
                    continue
                default:
                    throw error
                }
            }
        }
        throw lastRecoverable
    }

    private func generateContent(_ call: ProviderCall, model: String, key: String) async throws -> String {
        let url = baseURL.appendingPathComponent("\(model):generateContent")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // Header, not query string: keys must never appear in URLs (F11 privacy).
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = RESTBody.data(Self.body(for: call))

        let data = try await transport.send(request) { status, body in
            Self.classify(status: status, body: body, model: model)
        }
        return try Self.extractText(from: data)
    }

    static func body(for call: ProviderCall) -> JSONValue {
        var parts: [JSONValue] = [.object([.init("text", .string(call.fullUserText))])]
        for image in call.input.images {
            parts.append(.object([.init("inline_data", .object([
                .init("mime_type", .string(image.mimeType)),
                .init("data", .string(image.data.base64EncodedString())),
            ]))]))
        }

        var config: [JSONValue.Member] = []
        if let temperature = call.generation.temperature { config.append(.init("temperature", .number(temperature))) }
        if let maxTokens = call.generation.maxOutputTokens { config.append(.init("maxOutputTokens", .number(Double(maxTokens)))) }
        if !call.outputIsPlainText {
            config.append(.init("responseMimeType", .string("application/json")))
            config.append(.init("responseSchema", call.schema.geminiSchema()))
        }

        var members: [JSONValue.Member] = [
            .init("systemInstruction", .object([.init("parts", .array([.object([.init("text", .string(call.fullInstructions))])]))])),
            .init("contents", .array([.object([.init("role", .string("user")), .init("parts", .array(parts))])])),
        ]
        if !config.isEmpty { members.append(.init("generationConfig", .object(config))) }
        return .object(members)
    }

    /// Gemini returns 400 for both bad keys and bad requests; the body tells them apart.
    static func classify(status: Int, body: Data, model: String) -> AIError? {
        let message = (JSONValue.parse(String(decoding: body, as: UTF8.self))?["error"]?["message"]).flatMap {
            if case .string(let s) = $0 { s } else { nil }
        } ?? ""
        let lower = message.lowercased()
        switch status {
        case 400 where lower.contains("api key"), 401, 403:
            return .authFailed(.geminiBYOK)
        case 404:
            return .modelRetired(model)
        case 400:
            return .invalidOutput("request rejected")
        case 429:
            return .rateLimited(.geminiBYOK)
        default:
            return nil
        }
    }

    static func extractText(from data: Data) throws -> String {
        guard let root = JSONValue.parse(String(decoding: data, as: UTF8.self)) else {
            throw AIError.invalidOutput("unparseable response")
        }
        if case .string? = root["promptFeedback"]?["blockReason"] { throw AIError.guardrail }
        guard case .array(let candidates)? = root["candidates"], let first = candidates.first else {
            throw AIError.invalidOutput("no candidates")
        }
        if case .string(let reason)? = first["finishReason"], ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST"].contains(reason) {
            throw AIError.guardrail
        }
        guard case .array(let parts)? = first["content"]?["parts"] else { throw AIError.invalidOutput("no parts") }
        let text = parts.compactMap { part -> String? in
            if case .string(let s)? = part["text"] { s } else { nil }
        }.joined()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AIError.invalidOutput("empty text") }
        return text
    }
}
