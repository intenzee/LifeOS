import Foundation
import Testing
@testable import LifeOSAI

@Suite("Core types & error taxonomy")
struct CoreTypesTests {

    nonisolated static let allErrors: [AIError] = [
        .unavailable(.osTooOld), .unavailable(.deviceNotEligible), .unavailable(.appleIntelligenceNotEnabled),
        .unavailable(.modelNotReady), .unavailable(.missingCredential), .unavailable(.consentRequired),
        .unavailable(.offline), .unavailable(.circuitOpen), .consentRequired(.groqBYOK), .authFailed(.geminiBYOK),
        .rateLimited(.groqBYOK), .quotaExhausted(.applePCC), .circuitOpen(.applePCC), .contextOverflow, .guardrail,
        .refusal, .unsupportedLocale, .unsupportedInput, .modelRetired("m"), .noModelAvailable, .invalidOutput("x"),
        .network("x"), .server(500), .timeout, .cancelled,
        .exhausted([AIAttempt(provider: .groqBYOK, error: .authFailed(.groqBYOK), latency: .zero)]),
        .exhausted([AIAttempt(provider: .appleOnDevice, error: .timeout, latency: .zero)]),
    ]

    @Test("Every error has a non-empty user message and a content-free code", arguments: allErrors)
    func messagesAndCodes(_ error: AIError) throws {
        #expect(!error.userMessage.isEmpty)
        #expect(!error.code.isEmpty)
        #expect(!error.code.contains(" "))
        // Codable round trip (attempts are persisted in diagnostics events).
        let data = try JSONEncoder().encode(error)
        #expect(try JSONDecoder().decode(AIError.self, from: data) == error)
    }

    @Test("Recoverable vs user-actionable classification")
    func classification() {
        #expect(AIError.server(500).isRecoverable)
        #expect(!AIError.cancelled.isRecoverable)
        #expect(!AIError.exhausted([]).isRecoverable)
        #expect(AIError.authFailed(.groqBYOK).isUserActionable)
        #expect(AIError.unavailable(.missingCredential).isUserActionable)
        #expect(!AIError.timeout.isUserActionable)
        let chain = AIError.exhausted([AIAttempt(provider: .appleOnDevice, error: .timeout, latency: .zero),
                                       AIAttempt(provider: .groqBYOK, error: .rateLimited(.groqBYOK), latency: .zero)])
        #expect(chain.isUserActionable)
        #expect(chain.userActionableCause == .rateLimited(.groqBYOK))
        #expect(chain.userMessage == AIError.rateLimited(.groqBYOK).userMessage)
        #expect(AIError.timeout.userActionableCause == nil)
        #expect(AIError.authFailed(.groqBYOK).userActionableCause == .authFailed(.groqBYOK))
    }

    @Test("Foreign errors normalise into the taxonomy")
    func normalisation() {
        #expect(AIError.from(CancellationError()) == .cancelled)
        #expect(AIError.from(URLError(.cancelled)) == .cancelled)
        #expect(AIError.from(URLError(.timedOut)) == .timeout)
        #expect(AIError.from(URLError(.notConnectedToInternet)) == .unavailable(.offline))
        #expect(AIError.from(URLError(.cannotFindHost)).code == "network")
        #expect(AIError.from(NSError(domain: "x", code: 1)) == .server(-1))
        #expect(AIError.from(AIError.guardrail) == .guardrail)
    }

    @Test("Provider tiers, cloud boundary and labels")
    func providers() {
        #expect(ProviderID.deterministic.tier == .t0)
        #expect(ProviderID.appleOnDevice.tier < ProviderID.applePCC.tier)
        #expect(ProviderID.allCases.filter(\.isThirdPartyCloud) == [.geminiBYOK, .groqBYOK])
        #expect(Set(ProviderID.allCases.map(\.displayName)).count == ProviderID.allCases.count)
        #expect(PrivacyClass.public < .personal && PrivacyClass.personal < .health)
    }

    @Test("Inputs declare the capabilities they need")
    func inputs() {
        let image = AIImage(jpegData: Data([0xFF]), pixelWidth: 10, pixelHeight: 10)
        #expect(AIInput.text("hi").requiredCapabilities == [.text])
        #expect(AIInput.image(image, caption: "c").requiredCapabilities == [.text, .vision])
        #expect(AIInput.image(image).text == nil)
        #expect(AIInput.multimodal(text: "t", images: [image, image]).images.count == 2)
        #expect(AIInput.multimodal(text: "t", images: []).text == "t")
        #expect(image.dataURL == "data:image/jpeg;base64,/w==")
    }

    @Test("Context packets: privacy, filtering and rendering")
    func contextPackets() {
        let packet = ContextPacket(sections: [
            .init(title: "a", body: "likes dal", privacy: .personal),
            .init(title: "b", body: "  ", privacy: .public),
            .init(title: "c", body: "82 kg", privacy: .health),
        ])
        #expect(packet.privacy == .health)
        #expect(packet.rendered() == "likes dal\n\n82 kg")
        #expect(packet.filtered(maxPrivacy: .personal).rendered() == "likes dal")
        #expect(ContextPacket().isEmpty)
        #expect(ContextPacket().privacy == .public)
        let request = Fixtures.foodRequest(privacy: .personal, context: packet)
        #expect(request.effectivePrivacy == .health)
    }

    @Test("Task metadata used by routing and availability")
    func taskMetadata() {
        #expect(AITask.mealPhotoAnalyze.requiredCapabilities.contains(.vision))
        #expect(AITask.foodTextParse.allowsGuardrailFallback)
        #expect(!AITask.assistantChat.allowsGuardrailFallback)
        for task in AITask.allCases {
            #expect(RoutingTable.v1.chains[task]?.isEmpty == false, "every task has a route: \(task)")
            _ = task.defaultPrivacy
        }
        let a = AITaskAvailability(task: .foodTextParse, chain: [(.appleOnDevice, .available)])
        let b = AITaskAvailability(task: .foodTextParse, chain: [(.appleOnDevice, .available)])
        #expect(a == b)
        #expect(Set([a, b]).count == 1)
        #expect(AIAvailability.unavailable(.offline).isAvailable == false)
    }

    @Test("Event log: live updates, ring buffer and percentiles")
    func eventLog() async throws {
        let log = AIEventLog(capacity: 3)
        let updates = await log.updates()
        let event = AIEvent(id: UUID(), date: Date(), task: .foodTextParse, provider: .deterministic, model: "m",
                            outcome: .success, errorCode: nil, latencyMs: 10, promptVersion: "v", attempts: [])
        for latency in [10, 20, 30, 40] {
            var e = event
            e.id = UUID()
            e.latencyMs = latency
            await log.record(e)
        }
        var iterator = updates.makeAsyncIterator()
        #expect(await iterator.next()?.latencyMs == 10)
        #expect(await log.events.count == 3)
        #expect(await log.recent(1).first?.latencyMs == 40)
        let summary = try #require(await log.summary().first)
        #expect(summary.count == 3 && summary.p50Ms == 30 && summary.p95Ms == 40)
        #expect(AIEventLog.percentile([], 0.5) == 0)
        await log.clear()
        #expect(await log.events.isEmpty)
        #expect(Duration.milliseconds(1_500).milliseconds == 1_500)
    }

    @Test("Mock provider scripts, records calls and can compute replies")
    func mockProvider() async throws {
        let mock = MockAIProvider(id: .appleOnDevice, script: [.compute { call in "echo:\(call.task.rawValue)" }])
        let call = ProviderCall(task: .nudgeCompose, prompt: AIPrompt(id: "p", version: "v", instructions: "", user: "u"),
                                input: .text("u"), context: nil, schema: AIText.schema, outputIsPlainText: true, generation: .init())
        #expect(try await mock.generate(call).raw == "echo:nudgeCompose")
        mock.setAvailability(.unavailable(.offline))
        #expect(await mock.availability(for: .nudgeCompose) == .unavailable(.offline))
        mock.setScript([.fail(.timeout)])
        await #expect(throws: AIError.timeout) { try await mock.generate(call) }
        #expect(mock.callCount == 2)

        // Default protocol behaviour: one-shot stream, no-op prewarm.
        mock.setScript([.respond("streamed")])
        var chunks: [String] = []
        for try await chunk in mock.stream(call) { chunks.append(chunk) }
        #expect(chunks == ["streamed"])
        await mock.prewarm(for: .nudgeCompose)
        #expect(!mock.isLocalFallback)
    }

    @Test("Local handler providers report per-task availability")
    func localHandlers() async throws {
        let provider = LocalHandlerProvider(id: .deterministic, handlers: [:]).adding(.nudgeCompose) { _ in "Drink water" }
        #expect(await provider.availability(for: .nudgeCompose) == .available)
        #expect(await provider.availability(for: .weeklyReview) == .unavailable(.notImplemented))
        #expect(provider.isLocalFallback)
        let call = ProviderCall(task: .weeklyReview, prompt: AIPrompt(id: "p", version: "v", instructions: "", user: ""),
                                input: .text(""), context: nil, schema: AIText.schema, outputIsPlainText: true, generation: .init())
        await #expect(throws: AIError.unavailable(.notImplemented)) { try await provider.generate(call) }
    }
}

@Suite("SchemaValidator edge cases")
struct SchemaValidatorEdgeTests {

    nonisolated struct Probe: AIOutput, Equatable {
        var count: Int
        var ok: Bool
        var label: String
        var tags: [String]

        static let schema: AISchema = .object(name: "Probe", properties: [
            AISchemaProperty("count", .integer(minimum: 0, maximum: 10)),
            AISchemaProperty("ok", .boolean()),
            AISchemaProperty("label", .string()),
            AISchemaProperty("tags", .array(of: .string(), minItems: 1, maxItems: 2)),
        ])
    }

    @Test("Integers round and clamp; booleans and strings coerce; arrays truncate")
    func coercions() throws {
        let probe = try SchemaValidator.decode(#"{"count":"12.6","ok":"yes","label":7,"tags":["a","b","c"]}"#, as: Probe.self).get()
        #expect(probe == Probe(count: 10, ok: true, label: "7", tags: ["a", "b"]))
        let other = try SchemaValidator.decode(#"{"count":2.4,"ok":0,"label":true,"tags":["x"]}"#, as: Probe.self).get()
        #expect(other == Probe(count: 2, ok: false, label: "true", tags: ["x"]))
    }

    @Test("Shape errors are reported per path", arguments: [
        (#"{"count":"many","ok":true,"label":"a","tags":["x"]}"#, "$.count must be an integer"),
        (#"{"count":1,"ok":"maybe","label":"a","tags":["x"]}"#, "$.ok must be a boolean"),
        (#"{"count":1,"ok":true,"label":["a"],"tags":["x"]}"#, "$.label must be a string"),
        (#"{"count":1,"ok":true,"label":"a","tags":[]}"#, "$.tags needs at least 1 item(s)"),
        (#"{"count":1,"ok":true,"label":"a","tags":"x"}"#, "$.tags must be an array"),
        (#"[1,2]"#, "$ must be an object"),
    ])
    func shapeErrors(_ raw: String, _ issue: String) {
        guard case .failure(let failure) = SchemaValidator.decode(raw, as: Probe.self) else {
            Issue.record("expected failure for \(raw)"); return
        }
        #expect(failure.issues.contains(issue), "\(failure.issues)")
    }

    @Test("Numbers: NaN-free, negative and plain")
    func numbers() {
        #expect(SchemaValidator.numericValue(.number(.infinity)) == nil)
        #expect(SchemaValidator.numericValue(.string("-3.5")) == -3.5)
        #expect(SchemaValidator.numericValue(.bool(true)) == nil)
    }
}
