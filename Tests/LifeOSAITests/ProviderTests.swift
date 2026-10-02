import Foundation
import Testing
@testable import LifeOSAI

nonisolated private func groqReply(_ content: String) -> Data {
    let escaped = JSONValue.object([.init("choices", .array([.object([.init("message", .object([.init("content", .string(content))]))])]))])
    return Data(escaped.serialized().utf8)
}

nonisolated private let noSleep: @Sendable (Int) async throws -> Void = { _ in }

nonisolated private func photoCall(hints: String? = nil) -> ProviderCall {
    ProviderCall(task: .mealPhotoAnalyze, prompt: PromptRegistry.mealPhotoAnalyze(),
                 input: .image(AIImage(jpegData: Data([1, 2, 3]))),
                 context: hints.map { ContextPacket(sections: [.init(title: "learned", body: $0, privacy: .personal)]) },
                 schema: MealPhotoEstimate.schema, outputIsPlainText: false, generation: .init())
}

@Suite("GroqBYOKProvider")
struct GroqProviderTests {

    @Test("Meal-photo request is semantically identical to the legacy GroqMealAnalyzer payload")
    func legacyPayloadParity() throws {
        let hints = "Past corrections: fried rice was egg fried rice (520 kcal)."
        let image = AIImage(jpegData: Data([1, 2, 3]))
        let body = GroqBYOKProvider.body(for: photoCall(hints: hints), model: "qwen/qwen3.6-27b")

        // What the pre-gateway client sent (GroqMealAnalyzer.makeRequestBody).
        let legacy: [String: Any] = [
            "model": "qwen/qwen3.6-27b",
            "temperature": 0.2,
            "max_tokens": 900,
            "response_format": ["type": "json_object"],
            "messages": [
                ["role": "system", "content": PromptRegistry.mealPhotoSystem + "\n\n" + hints],
                ["role": "user", "content": [
                    ["type": "text", "text": PromptRegistry.mealPhotoUser],
                    ["type": "image_url", "image_url": ["url": image.dataURL]],
                ]],
            ],
        ]
        let ours = try JSONSerialization.jsonObject(with: Data(body.serialized().utf8)) as? NSDictionary
        #expect(ours == (legacy as NSDictionary))
    }

    @Test("Text tasks get a JSON Schema instruction and plain string content")
    func textBody() {
        let call = ProviderCall(task: .foodTextParse, prompt: PromptRegistry.foodTextParse("2 idli"), input: .text("2 idli"),
                                context: nil, schema: ParsedMeal.schema, outputIsPlainText: false,
                                generation: .init(temperature: 0, maxOutputTokens: 300))
        let body = GroqBYOKProvider.body(for: call, model: "m")
        guard case .array(let messages)? = body["messages"], case .string(let user)? = messages[1]["content"] else {
            Issue.record("unexpected shape"); return
        }
        #expect(user.contains("conforms to this JSON Schema"))
        #expect(body["temperature"] == .number(0))
        #expect(body["max_tokens"] == .number(300))
    }

    @Test("Retired models are skipped; the next model answers")
    func modelRotation() async throws {
        let (session, token) = StubURLProtocol.session { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            return body.contains("\"retired/model\"") ? (404, Data()) : (200, groqReply(Fixtures.mealPhotoJSON))
        }
        let provider = GroqBYOKProvider(credentials: StaticCredentials([.groqBYOK: "k"]),
                                        models: { _ in ["retired/model", "live/model"] },
                                        transport: RESTTransport(session: session, provider: .groqBYOK, backoff: noSleep))
        let response = try await provider.generate(photoCall())
        #expect(response.model == "live/model")
        #expect(StubURLProtocol.requests(token).count == 2)
    }

    @Test("Changing groqVisionModels in remote config changes the model sent, no app update (Phase 0 exit)")
    func remoteConfigModels() async throws {
        let (session, token) = StubURLProtocol.session { _ in (200, groqReply(Fixtures.mealPhotoJSON)) }
        let store = AIRemoteConfigStore(remoteURL: nil, cacheURL: nil)
        var config = AIRemoteConfig.default
        config.groqVisionModels = ["vendor/brand-new-vision"]
        await store.override(config)
        let provider = GroqBYOKProvider(credentials: StaticCredentials([.groqBYOK: "k"]), models: { vision in
            let current = await store.current
            return vision ? current.groqVisionModels : current.groqTextModels
        }, session: session)

        _ = try await provider.generate(photoCall())

        let sent = String(decoding: StubURLProtocol.requests(token).first?.httpBody ?? Data(), as: UTF8.self)
        #expect(sent.contains("\"model\":\"vendor/brand-new-vision\""))
    }

    @Test("A model answering in prose is skipped like legacy badResponse")
    func proseSkipped() async throws {
        let (session, _) = StubURLProtocol.session { request in
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            return body.contains("\"chatty\"") ? (200, groqReply("I think this is rice!")) : (200, groqReply(Fixtures.mealPhotoJSON))
        }
        let provider = GroqBYOKProvider(credentials: StaticCredentials([.groqBYOK: "k"]), models: { _ in ["chatty", "good"] },
                                        transport: RESTTransport(session: session, provider: .groqBYOK, backoff: noSleep))
        #expect(try await provider.generate(photoCall()).model == "good")
    }

    @Test("Auth failure stops immediately; rate limit retries once then surfaces",
          arguments: [(401, AIError.authFailed(.groqBYOK), 1), (429, AIError.rateLimited(.groqBYOK), 2)])
    func userActionable(_ status: Int, _ expected: AIError, _ requests: Int) async throws {
        let (session, token) = StubURLProtocol.session { _ in (status, Data()) }
        let provider = GroqBYOKProvider(credentials: StaticCredentials([.groqBYOK: "k"]), models: { _ in ["a", "b"] },
                                        transport: RESTTransport(session: session, provider: .groqBYOK, backoff: noSleep))
        await #expect(throws: expected) { try await provider.generate(photoCall()) }
        #expect(StubURLProtocol.requests(token).count == requests)
    }

    @Test("5xx retries once per model, then tries the next model")
    func serverErrors() async throws {
        let (session, token) = StubURLProtocol.session { _ in (503, Data()) }
        let provider = GroqBYOKProvider(credentials: StaticCredentials([.groqBYOK: "k"]), models: { _ in ["a", "b"] },
                                        transport: RESTTransport(session: session, provider: .groqBYOK, backoff: noSleep))
        await #expect(throws: AIError.server(503)) { try await provider.generate(photoCall()) }
        #expect(StubURLProtocol.requests(token).count == 4)
    }

    @Test("No key → unavailable(missingCredential)")
    func missingKey() async {
        let provider = GroqBYOKProvider(credentials: StaticCredentials(), models: { _ in ["a"] })
        #expect(await provider.availability(for: .mealPhotoAnalyze) == .unavailable(.missingCredential))
        await #expect(throws: AIError.unavailable(.missingCredential)) { try await provider.generate(photoCall()) }
    }
}

@Suite("GeminiBYOKProvider")
struct GeminiProviderTests {

    @Test("Request uses header auth, responseSchema and inline image data")
    func requestShape() async throws {
        let reply = #"{"candidates":[{"content":{"parts":[{"text":"{\"name\":\"Dal\",\"calories\":200}"}]},"finishReason":"STOP"}]}"#
        let (session, token) = StubURLProtocol.session { _ in (200, Data(reply.utf8)) }
        let provider = GeminiBYOKProvider(credentials: StaticCredentials([.geminiBYOK: "g-key"]), models: { ["gemini-x"] }, session: session)

        let response = try await provider.generate(photoCall())

        #expect(response.model == "gemini-x")
        #expect(response.raw.contains("Dal"))
        let request = try #require(StubURLProtocol.requests(token).first)
        #expect(request.url?.absoluteString.hasSuffix("models/gemini-x:generateContent") == true)
        #expect(request.url?.query == nil, "keys never go in URLs")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "g-key")
        let body = try #require(JSONValue.parse(String(decoding: request.httpBody ?? Data(), as: UTF8.self)))
        #expect(body["generationConfig"]?["responseMimeType"] == .string("application/json"))
        #expect(body["generationConfig"]?["responseSchema"]?["type"] == .string("OBJECT"))
        guard case .array(let contents)? = body["contents"], case .array(let parts)? = contents.first?["parts"] else {
            Issue.record("unexpected body"); return
        }
        #expect(parts.count == 2)
        #expect(parts[1]["inline_data"]?["mime_type"] == .string("image/jpeg"))
    }

    @Test("Status classification: bad key (400 'API key'), retired model, rejected request, rate limit")
    func classify() {
        let badKey = Data(#"{"error":{"message":"API key not valid. Please pass a valid API key."}}"#.utf8)
        #expect(GeminiBYOKProvider.classify(status: 400, body: badKey, model: "m") == .authFailed(.geminiBYOK))
        #expect(GeminiBYOKProvider.classify(status: 404, body: Data(), model: "m") == .modelRetired("m"))
        #expect(GeminiBYOKProvider.classify(status: 400, body: Data(), model: "m") == .invalidOutput("request rejected"))
        #expect(GeminiBYOKProvider.classify(status: 429, body: Data(), model: "m") == .rateLimited(.geminiBYOK))
        #expect(GeminiBYOKProvider.classify(status: 500, body: Data(), model: "m") == nil)
    }

    @Test("Safety blocks map to guardrail; empty candidates are invalid")
    func extraction() throws {
        #expect(throws: AIError.guardrail) {
            try GeminiBYOKProvider.extractText(from: Data(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#.utf8))
        }
        #expect(throws: AIError.guardrail) {
            try GeminiBYOKProvider.extractText(from: Data(#"{"candidates":[{"finishReason":"SAFETY"}]}"#.utf8))
        }
        #expect(throws: AIError.self) { try GeminiBYOKProvider.extractText(from: Data(#"{"candidates":[]}"#.utf8)) }
        #expect(try GeminiBYOKProvider.extractText(from: Data(#"{"candidates":[{"content":{"parts":[{"text":"a"},{"text":"b"}]}}]}"#.utf8)) == "ab")
    }

    @Test("Retired model falls through to the next configured model")
    func rotation() async throws {
        let ok = #"{"candidates":[{"content":{"parts":[{"text":"{}"}]}}]}"#
        let (session, _) = StubURLProtocol.session { request in
            request.url!.absoluteString.contains("old-model") ? (404, Data()) : (200, Data(ok.utf8))
        }
        let provider = GeminiBYOKProvider(credentials: StaticCredentials([.geminiBYOK: "k"]), models: { ["old-model", "new-model"] },
                                          transport: RESTTransport(session: session, provider: .geminiBYOK, backoff: noSleep))
        #expect(try await provider.generate(photoCall()).model == "new-model")
    }
}

@Suite("Credentials")
struct CredentialTests {
    @Test("Environment credentials for the CLI")
    func environment() {
        let creds = StaticCredentials.fromEnvironment(["GROQ_API_KEY": " gsk ", "GOOGLE_API_KEY": "g"])
        #expect(creds.apiKey(for: .groqBYOK) == "gsk")
        #expect(creds.apiKey(for: .geminiBYOK) == "g")
        #expect(creds.apiKey(for: .appleOnDevice) == nil)
    }

    @Test("Keychain accounts match the legacy AIKeyStore layout")
    func keychainLayout() {
        #expect(KeychainCredentialStore.service == "app.lifeos.aiscan.apikey")
        #expect(KeychainCredentialStore.account(for: .groqBYOK) == "Groq")
        #expect(KeychainCredentialStore.account(for: .geminiBYOK) == "Gemini")
        #expect(KeychainCredentialStore.account(for: .appleOnDevice) == nil)
    }
}
