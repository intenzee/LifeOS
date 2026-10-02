import Foundation
import Testing
@testable import LifeOSAI

@Suite("AIGateway routing & fallback")
struct AIGatewayTests {

    @Test("First available provider in the chain answers, with provenance")
    func firstAvailableWins() async throws {
        let t1 = MockAIProvider(id: .appleOnDevice, responding: Fixtures.parsedMealJSON)
        let t0 = MockAIProvider(id: .deterministic, responding: #"{"items":[],"mealType":"unknown"}"#)
        let gateway = await Fixtures.gateway([t1, t0])

        let result = try await gateway.run(Fixtures.foodRequest())

        #expect(result.provider == .appleOnDevice)
        #expect(result.output.items.map(\.name) == ["roti", "dal"])
        #expect(result.output.mealType == .lunch)
        #expect(result.promptVersion == PromptRegistry.version)
        #expect(result.degradedFrom.isEmpty)
        #expect(t0.callCount == 0)
    }

    @Test("Recoverable failures fall through the chain and are recorded")
    func recoverableFallThrough() async throws {
        let t1 = MockAIProvider(id: .appleOnDevice, script: [.fail(.contextOverflow)])
        let t2 = MockAIProvider(id: .applePCC, script: [.fail(.server(503))])
        let t0 = MockAIProvider(id: .deterministic, responding: Fixtures.parsedMealJSON)
        let gateway = await Fixtures.gateway([t1, t2, t0])

        let result = try await gateway.run(Fixtures.foodRequest())

        #expect(result.provider == .deterministic)
        #expect(result.degradedFrom.map(\.provider) == [.appleOnDevice, .applePCC, .geminiBYOK, .groqBYOK])
        #expect(result.degradedFrom.first?.error == .contextOverflow)
        #expect(result.didDegrade)
    }

    @Test("Forcing each provider unavailable degrades to the next one (Phase 0 exit)",
          arguments: [ProviderID.appleOnDevice, .applePCC, .geminiBYOK, .groqBYOK])
    func forcedUnavailableDegrades(_ forcedOff: ProviderID) async throws {
        let chain: [ProviderID] = [.appleOnDevice, .applePCC, .geminiBYOK, .groqBYOK, .deterministic]
        let mocks = chain.map { MockAIProvider(id: $0, responding: Fixtures.parsedMealJSON) }
        let consents = InMemoryConsentStore([.geminiBYOK: Fixtures.personalConsent, .groqBYOK: Fixtures.personalConsent])
        let gateway = await Fixtures.gateway(mocks, consents: consents)
        await gateway.setDebugOverrides(.init(forcedUnavailable: Set(chain.prefix { $0 != forcedOff }).union([forcedOff])))

        let result = try await gateway.run(Fixtures.foodRequest())

        let expected = chain[chain.firstIndex(of: forcedOff)! + 1]
        #expect(result.provider == expected)
        #expect(result.degradedFrom.last?.error == .unavailable(.disabledByConfig))
    }

    @Test("With every model tier off, the deterministic tier still answers within budget")
    func allModelTiersOff() async throws {
        let gateway = AIStack.makeGateway(.init(credentials: StaticCredentials(), consents: InMemoryConsentStore()))
        await gateway.setDebugOverrides(.init(forcedUnavailable: [.appleOnDevice, .applePCC, .geminiBYOK, .groqBYOK]))
        let clock = ContinuousClock()
        let start = clock.now

        let result = try await gateway.run(Fixtures.foodRequest("2 rotis and dal", budget: .seconds(2)))

        #expect(result.provider == .deterministic)
        #expect(result.output.items.map(\.name) == ["roti", "dal"])
        #expect(clock.now - start < .seconds(2))
    }

    @Test("Exhausted chain throws a typed error carrying every attempt")
    func exhausted() async throws {
        let t1 = MockAIProvider(id: .appleOnDevice, availability: .unavailable(.deviceNotEligible), script: [])
        let gateway = await Fixtures.gateway([t1])
        let request = AIRequest<ParsedMeal>(task: .memoryExtract, prompt: PromptRegistry.foodTextParse("x"),
                                            input: .text("x"), privacy: .health)

        await #expect(throws: AIError.self) { try await gateway.run(request) }
        do {
            _ = try await gateway.run(request)
        } catch let AIError.exhausted(attempts) {
            #expect(attempts.map(\.provider) == [.appleOnDevice, .applePCC])
            #expect(attempts.first?.error == .unavailable(.deviceNotEligible))
            #expect(attempts.last?.error == .unavailable(.notImplemented))
        }
    }

    @Test("Invalid output gets exactly one repair retry with the validation feedback")
    func repairRetry() async throws {
        let t1 = MockAIProvider(id: .appleOnDevice, script: [
            .respond(#"{"items":[{"quantity":2}],"mealType":"lunch"}"#),   // missing name
            .respond(Fixtures.parsedMealJSON),
        ])
        let gateway = await Fixtures.gateway([t1])

        let result = try await gateway.run(Fixtures.foodRequest())

        #expect(result.provider == .appleOnDevice)
        #expect(t1.callCount == 2)
        let repair = try #require(t1.calls.last)
        #expect(repair.repairFeedback?.contains("$.items[0].name is required") == true)
        #expect(repair.fullUserText.contains("Your previous reply"))
    }

    @Test("Output still invalid after repair moves to the next provider")
    func repairThenNext() async throws {
        let t1 = MockAIProvider(id: .appleOnDevice, script: [.respond("not json at all")])
        let t0 = MockAIProvider(id: .deterministic, responding: Fixtures.parsedMealJSON)
        let gateway = await Fixtures.gateway([t1, t0])

        let result = try await gateway.run(Fixtures.foodRequest())

        #expect(t1.callCount == 2)
        #expect(result.provider == .deterministic)
        #expect(result.degradedFrom.first?.error.code == "invalidOutput")
    }

    @Test("Guardrail hits fall back only for benign tasks")
    func guardrailPolicy() async throws {
        let benignT1 = MockAIProvider(id: .appleOnDevice, script: [.fail(.guardrail)])
        let t0 = MockAIProvider(id: .deterministic, responding: Fixtures.parsedMealJSON)
        let benign = await Fixtures.gateway([benignT1, t0])
        #expect(try await benign.run(Fixtures.foodRequest("a shot of whiskey")).provider == .deterministic)

        let chatT1 = MockAIProvider(id: .appleOnDevice, script: [.fail(.guardrail)])
        let chatT2 = MockAIProvider(id: .applePCC, responding: "should never be asked")
        let safety = await Fixtures.gateway([chatT1, chatT2])
        let chat = AIRequest<AIText>(task: .assistantChat,
                                     prompt: AIPrompt(id: "chat", version: "t", instructions: "", user: "hi"),
                                     input: .text("hi"), privacy: .health)
        await #expect(throws: AIError.guardrail) { try await safety.run(chat) }
        #expect(chatT2.callCount == 0)
    }

    @Test("Image input skips providers without vision")
    func capabilitySkip() async throws {
        let textOnly = MockAIProvider(id: .appleOnDevice, capabilities: [.text], script: [.respond(Fixtures.mealPhotoJSON)])
        let vision = MockAIProvider(id: .visionLegacy, capabilities: [.text, .vision], script: [.respond(Fixtures.mealPhotoJSON)])
        var config = AIRemoteConfig.default
        config.flags.photoAppleVision = true
        let gateway = await Fixtures.gateway([textOnly, vision], config: config)

        let result = try await gateway.run(Fixtures.photoRequest())

        #expect(result.provider == .visionLegacy)
        #expect(textOnly.callCount == 0)
        #expect(result.degradedFrom.first?.error == .unsupportedInput)
    }

    @Test("A slow provider is cut off at the deadline and the chain continues")
    func timeout() async throws {
        let slow = MockAIProvider(id: .appleOnDevice, script: [.delay(.seconds(30), then: Fixtures.parsedMealJSON)])
        let t0 = MockAIProvider(id: .deterministic, responding: Fixtures.parsedMealJSON)
        let gateway = await Fixtures.gateway([slow, t0])
        let clock = ContinuousClock()
        let start = clock.now

        let result = try await gateway.run(Fixtures.foodRequest(budget: .milliseconds(300)))

        #expect(result.provider == .deterministic)
        #expect(result.degradedFrom.first?.error == .timeout)
        #expect(clock.now - start < .seconds(3))
    }

    @Test("Caller cancellation propagates as .cancelled, not a fallback")
    func cancellation() async throws {
        let slow = MockAIProvider(id: .appleOnDevice, script: [.delay(.seconds(30), then: Fixtures.parsedMealJSON)])
        let t0 = MockAIProvider(id: .deterministic, responding: Fixtures.parsedMealJSON)
        let gateway = await Fixtures.gateway([slow, t0])

        let task = Task { try await gateway.run(Fixtures.foodRequest(budget: .seconds(60))) }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()

        await #expect(throws: AIError.cancelled) { try await task.value }
        #expect(t0.callCount == 0)
    }

    @Test("Remote-config routing override and kill switch")
    func remoteRouting() async throws {
        let t1 = MockAIProvider(id: .appleOnDevice, responding: Fixtures.parsedMealJSON)
        let t0 = MockAIProvider(id: .deterministic, responding: Fixtures.parsedMealJSON)
        var config = AIRemoteConfig.default
        config.routing = [AITask.foodTextParse.rawValue: [.deterministic, .appleOnDevice]]
        let gateway = await Fixtures.gateway([t1, t0], config: config)
        #expect(try await gateway.run(Fixtures.foodRequest()).provider == .deterministic)

        config.routing = [:]
        config.disabledProviders = [.appleOnDevice]
        let killed = await Fixtures.gateway([t1, t0], config: config)
        let result = try await killed.run(Fixtures.foodRequest())
        #expect(result.provider == .deterministic)
        #expect(!result.degradedFrom.contains { $0.provider == .appleOnDevice })
    }

    @Test("Availability reports the chain and the primary provider")
    func availabilityReport() async throws {
        let t1 = MockAIProvider(id: .appleOnDevice, availability: .unavailable(.appleIntelligenceNotEnabled), script: [])
        let t0 = MockAIProvider(id: .deterministic, responding: Fixtures.parsedMealJSON)
        let gateway = await Fixtures.gateway([t1, t0])

        let summary = await gateway.availability(for: .foodTextParse)

        #expect(summary.chain.map(\.provider) == [.appleOnDevice, .applePCC, .geminiBYOK, .groqBYOK, .deterministic])
        #expect(summary.chain.first?.availability == .unavailable(.appleIntelligenceNotEnabled))
        #expect(summary.primary == .deterministic)
        #expect(summary.isAvailable)
    }

    @Test("Successful runs and failures are recorded as content-free events")
    func telemetry() async throws {
        let t0 = MockAIProvider(id: .deterministic, responding: Fixtures.parsedMealJSON)
        let gateway = await Fixtures.gateway([t0])
        _ = try await gateway.run(Fixtures.foodRequest("secret sentence"))

        let events = await gateway.events.recent()
        let event = try #require(events.first)
        #expect(event.outcome == .success)
        #expect(event.provider == .deterministic)
        let encoded = String(decoding: try JSONEncoder().encode(event), as: UTF8.self)
        #expect(!encoded.contains("secret"))
        #expect(await gateway.events.summary().first?.count == 1)
    }

    @Test("Streaming yields partial text then a completed result; pre-token failures fall back")
    func streaming() async throws {
        let t1 = MockAIProvider(id: .appleOnDevice, script: [.fail(.unavailable(.modelNotReady))])
        let t2 = MockAIProvider(id: .applePCC, responding: "Here is your summary.")
        let gateway = await Fixtures.gateway([t1, t2])
        let request = AIRequest<AIText>(task: .assistantChat,
                                        prompt: AIPrompt(id: "chat", version: "t", instructions: "Be brief.", user: "summary"),
                                        input: .text("summary"), privacy: .health)
        var partials: [String] = []
        var completed: AIResult<AIText>?
        for try await event in gateway.stream(request) {
            switch event {
            case .partial(let text): partials.append(text)
            case .completed(let result): completed = result
            }
        }
        #expect(partials == ["Here is your summary."])
        #expect(completed?.provider == .applePCC)
        #expect(completed?.output.text == "Here is your summary.")
        #expect(completed?.degradedFrom.first?.provider == .appleOnDevice)
    }

    @Test("Per-request key override makes a BYOK provider usable without a stored key")
    func credentialOverride() async throws {
        let (session, token) = StubURLProtocol.session { _ in
            (200, Data(#"{"choices":[{"message":{"content":"{\"name\":\"Dal\",\"calories\":200}"}}]}"#.utf8))
        }
        let groq = GroqBYOKProvider(credentials: StaticCredentials(), models: { _ in ["m1"] }, session: session)
        let consents = InMemoryConsentStore([.groqBYOK: Fixtures.personalConsent])
        let gateway = await Fixtures.gateway([groq], consents: consents)

        let result = try await gateway.run(Fixtures.photoRequest(overrides: [.groqBYOK: "typed-key"]))

        #expect(result.provider == .groqBYOK)
        let sent = try #require(StubURLProtocol.requests(token).first)
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer typed-key")
    }
}
