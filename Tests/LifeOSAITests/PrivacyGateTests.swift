import Foundation
import Testing
@testable import LifeOSAI

@Suite("Privacy gate & consent")
struct PrivacyGateTests {

    @Test(".health requests never reach third-party cloud without consent — network-level proof (Phase 0 exit)")
    func healthNeverReachesT3() async throws {
        let (session, token) = StubURLProtocol.session { _ in (200, Data("{}".utf8)) }
        let credentials = StaticCredentials([.groqBYOK: "k", .geminiBYOK: "k"])
        // Personal consent from key entry exists — it must not cover health data.
        let consents = InMemoryConsentStore([.groqBYOK: Fixtures.personalConsent, .geminiBYOK: Fixtures.personalConsent])
        let gateway = AIGateway(providers: [
            GroqBYOKProvider(credentials: credentials, models: { _ in ["m"] }, session: session),
            GeminiBYOKProvider(credentials: credentials, models: { ["g"] }, session: session),
        ], consents: consents)

        await gateway.setDebugOverrides(.init(forcedChains: [.assistantChat: [.geminiBYOK, .groqBYOK]]))
        let request = AIRequest<AIText>(task: .assistantChat,
                                        prompt: AIPrompt(id: "chat", version: "t", instructions: "", user: "my weight trend"),
                                        input: .text("my weight trend"), privacy: .health)

        do {
            _ = try await gateway.run(request)
            Issue.record("expected the chain to be exhausted")
        } catch let AIError.exhausted(attempts) {
            #expect(attempts.map(\.error) == [.consentRequired(.geminiBYOK), .consentRequired(.groqBYOK)])
        }
        #expect(StubURLProtocol.requests(token).isEmpty, "no bytes may leave the device")
    }

    @Test("Personal context sent to T3 cannot smuggle health sections")
    func contextCeiling() async throws {
        let groq = MockAIProvider(id: .groqBYOK, responding: Fixtures.parsedMealJSON)
        let consents = InMemoryConsentStore([.groqBYOK: Fixtures.personalConsent])
        let gateway = await Fixtures.gateway([groq], consents: consents)
        await gateway.setDebugOverrides(.init(forcedChains: [.foodTextParse: [.groqBYOK]]))
        let context = ContextPacket(sections: [.init(title: "prefs", body: "vegetarian", privacy: .personal)])

        _ = try await gateway.run(Fixtures.foodRequest(context: context))
        #expect(groq.calls.first?.fullInstructions.contains("vegetarian") == true)

        // Same request with a health section is now .health overall → denied.
        let withHealth = ContextPacket(sections: context.sections + [.init(title: "weight", body: "82 kg", privacy: .health)])
        await #expect(throws: AIError.self) { try await gateway.run(Fixtures.foodRequest(context: withHealth)) }
        #expect(groq.callCount == 1)
    }

    @Test("Sheet consent for health allows it; key-entry consent caps at personal")
    func consentLevels() {
        let gate = PrivacyGate(consents: InMemoryConsentStore([
            .geminiBYOK: Fixtures.healthConsent,
            .groqBYOK: CloudConsent(maxPrivacy: .health, grantedAt: Date(), source: .keyEntry),
        ]))
        #expect(gate.evaluate(task: .assistantChat, privacy: .health, provider: .geminiBYOK) == .allow(contextCeiling: .health))
        #expect(gate.evaluate(task: .assistantChat, privacy: .health, provider: .groqBYOK) == .deny(.consentRequired(.groqBYOK)))
        #expect(gate.evaluate(task: .foodTextParse, privacy: .personal, provider: .groqBYOK) == .allow(contextCeiling: .personal))
    }

    @Test("Memory tasks never go to third-party cloud, even with full consent")
    func memoryNeverT3() {
        let gate = PrivacyGate(consents: InMemoryConsentStore([.geminiBYOK: Fixtures.healthConsent]))
        #expect(gate.evaluate(task: .memoryExtract, privacy: .health, provider: .geminiBYOK) == .deny(.consentRequired(.geminiBYOK)))
        #expect(gate.evaluate(task: .memoryExtract, privacy: .health, provider: .applePCC) == .allow(contextCeiling: .health))
    }

    @Test("Public requests need no consent but carry no context")
    func publicRequests() {
        let gate = PrivacyGate(consents: InMemoryConsentStore())
        #expect(gate.evaluate(task: .presetSuggestName, privacy: .public, provider: .groqBYOK) == .allow(contextCeiling: .public))
    }

    @Test("Identifiers are redacted from text bound for third-party cloud; food numbers are not")
    func redaction() {
        let text = "email me at sam@example.com or +91 98765 43210, I ate 100 200 300 g rice"
        let redacted = PrivacyGate.redact(text)
        #expect(!redacted.contains("sam@example.com"))
        #expect(!redacted.contains("98765"))
        #expect(redacted.contains("100 200 300 g rice"))
    }

    @Test("Revoking consent cancels an in-flight third-party request")
    func revocationCancelsInFlight() async throws {
        let consents = InMemoryConsentStore([.groqBYOK: Fixtures.personalConsent])
        let slowGroq = MockAIProvider(id: .groqBYOK, script: [.delay(.seconds(30), then: Fixtures.parsedMealJSON)])
        let t0 = MockAIProvider(id: .deterministic, responding: Fixtures.parsedMealJSON)
        let gateway = await Fixtures.gateway([slowGroq, t0], consents: consents)
        await gateway.setDebugOverrides(.init(forcedChains: [.foodTextParse: [.groqBYOK, .deterministic]]))

        let task = Task { try await gateway.run(Fixtures.foodRequest(budget: .seconds(60))) }
        try await Task.sleep(for: .milliseconds(150))
        consents.revoke(.groqBYOK)
        await gateway.consentDidChange()

        let result = try await task.value
        #expect(result.provider == .deterministic)
        #expect(result.degradedFrom.first?.error == .consentRequired(.groqBYOK))
    }

    @Test("UserDefaults consent store round-trips and revokes")
    func userDefaultsStore() throws {
        let defaults = try #require(UserDefaults(suiteName: "test.consent.\(UUID().uuidString)"))
        let store = UserDefaultsConsentStore(defaults: defaults)
        #expect(store.consent(for: .groqBYOK) == nil)
        store.grant(Fixtures.personalConsent, for: .groqBYOK)
        #expect(store.consent(for: .groqBYOK)?.maxPrivacy == .personal)
        store.revoke(.groqBYOK)
        #expect(store.consent(for: .groqBYOK) == nil)
    }
}
