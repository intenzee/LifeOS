import Foundation
import Testing
@testable import LifeOSAI

/// Regression suite for "photo scanning works identically through the Gateway"
/// (Phase 0 exit criterion). Each case mirrors a branch of the pre-gateway
/// `MealScannerEngine.scan`; the app-side mapping to `MealScanError` is a thin
/// switch over these outcomes.
@Suite("Meal photo flow through the gateway (legacy parity)")
struct MealPhotoFlowTests {

    private func groq(_ script: [MockAIProvider.Step], key: Bool = true) -> MockAIProvider {
        MockAIProvider(id: .groqBYOK, capabilities: [.text, .vision],
                       availability: key ? .available : .unavailable(.missingCredential), script: script)
    }

    private func vision(_ script: [MockAIProvider.Step]) -> MockAIProvider {
        MockAIProvider(id: .visionLegacy, capabilities: [.text, .vision], script: script)
    }

    private let onDeviceBanana = #"{"name":"Banana","servingSize":"1 medium","calories":105,"protein":1.3,"carbs":27,"fat":0.4,"items":[],"confidence":0.81}"#
    private let consents = InMemoryConsentStore([.groqBYOK: Fixtures.personalConsent])

    @Test("No key → straight to on-device, not a degradation")
    func noKey() async throws {
        let g = groq([], key: false)
        let v = vision([.respond(onDeviceBanana)])
        let gateway = await Fixtures.gateway([g, v], consents: consents)

        let result = try await gateway.run(Fixtures.photoRequest())

        #expect(result.provider == .visionLegacy)
        #expect(result.output.confidence == 0.81)
        #expect(result.degradedFrom.map(\.error) == [.unavailable(.missingCredential)])
        #expect(g.callCount == 0)
    }

    @Test("Key + Groq success → Groq result with learned hints in the system prompt")
    func groqSuccess() async throws {
        let g = groq([.respond(Fixtures.mealPhotoJSON)])
        let gateway = await Fixtures.gateway([g, vision([])], consents: consents)
        let hints = ContextPacket(sections: [.init(title: "learned", body: "HINT: it is usually egg fried rice", privacy: .personal)])

        let result = try await gateway.run(Fixtures.photoRequest(context: hints))

        #expect(result.provider == .groqBYOK)
        #expect(result.output.totals.calories == 520)
        #expect(result.degradedFrom.isEmpty)
        let call = try #require(g.calls.first)
        #expect(call.fullInstructions == PromptRegistry.mealPhotoSystem + "\n\nHINT: it is usually egg fried rice")
        #expect(call.prompt.user == PromptRegistry.mealPhotoUser)
    }

    @Test("Groq fails (bad key / rate limit / retired / 5xx) → on-device result, Groq error kept for the banner",
          arguments: [AIError.authFailed(.groqBYOK), .rateLimited(.groqBYOK), .noModelAvailable, .server(502)])
    func groqFailsOnDeviceServes(_ error: AIError) async throws {
        let gateway = await Fixtures.gateway([groq([.fail(error)]), vision([.respond(onDeviceBanana)])], consents: consents)

        let result = try await gateway.run(Fixtures.photoRequest())

        #expect(result.provider == .visionLegacy)
        #expect(result.degradedFrom.first?.provider == .groqBYOK)
        #expect(result.degradedFrom.first?.error == error)
    }

    @Test("Groq fails and on-device recognises nothing → exhausted with the Groq error first")
    func bothFail() async throws {
        let gateway = await Fixtures.gateway([groq([.fail(.authFailed(.groqBYOK))]),
                                              vision([.fail(.invalidOutput("no recognisable food"))])], consents: consents)
        do {
            _ = try await gateway.run(Fixtures.photoRequest())
            Issue.record("expected failure")
        } catch let error as AIError {
            #expect(error.userActionableCause == .authFailed(.groqBYOK))
            guard case .exhausted(let attempts) = error else { Issue.record("expected exhausted"); return }
            #expect(attempts.map(\.provider) == [.groqBYOK, .visionLegacy])
        }
    }

    @Test("Groq returning an all-zero estimate is a bad response → on-device (legacy rule)")
    func emptyEstimate() async throws {
        let g = groq([.respond(#"{"name":"Plate","calories":0,"protein":0,"carbs":0,"fat":0}"#)])
        let gateway = await Fixtures.gateway([g, vision([.respond(onDeviceBanana)])], consents: consents)
        let result = try await gateway.run(Fixtures.photoRequest())
        #expect(result.provider == .visionLegacy)
        #expect(g.callCount == 2, "one repair attempt before moving on")
    }

    @Test("Refine with Groq only (Phase 0 chain) needs a key")
    func refineChain() async throws {
        let gateway = await Fixtures.gateway([groq([], key: false), vision([.respond(onDeviceBanana)])], consents: consents)
        let summary = await gateway.availability(for: .mealPhotoRefine)
        #expect(summary.chain.map(\.provider) == [.groqBYOK])
        #expect(summary.primary == nil)
    }

    @Test("Phase 0 photo routing: Apple vision tiers are configured but flag-gated off")
    func phase0Routing() {
        #expect(RoutingTable.v1.chain(for: .mealPhotoAnalyze, config: .default) == [.groqBYOK, .visionLegacy])
        #expect(AIRemoteConfig.default.flags.photoAppleVision == false)
    }
}

@Suite("DeterministicFoodParser")
struct DeterministicFoodParserTests {

    @Test("Parses quantities, units, plurals and meal type",
          arguments: [
            ("two rotis, dal and a bowl of curd for lunch", ["roti", "dal", "curd"], [2.0, 1, 1], ["piece", "serving", "bowl"], ParsedMeal.MealSlot.lunch),
            ("had 3 idlis with sambar this morning", ["idli", "sambar"], [3, 1], ["piece", "serving"], .breakfast),
            ("do paratha aur ek glass lassi", ["paratha", "lassi"], [2, 1], ["piece", "glass"], .unknown),
            ("200g paneer tikka + 1/2 cup rice for dinner", ["paneer tikka", "rice"], [200, 0.5], ["g", "cup"], .dinner),
            ("2 boiled eggs and black coffee without sugar", ["egg", "black coffee"], [2, 1], ["piece", "serving"], .unknown),
          ])
    func parses(_ text: String, _ names: [String], _ quantities: [Double], _ units: [String], _ meal: ParsedMeal.MealSlot) {
        let parsed = DeterministicFoodParser.parse(text)
        #expect(parsed.items.map(\.name) == names)
        #expect(parsed.items.map(\.quantity) == quantities)
        #expect(parsed.items.map(\.unit) == units)
        #expect(parsed.mealType == meal)
    }

    @Test("Captures preparation and preset references")
    func extras() {
        let coffee = DeterministicFoodParser.parse("black coffee without sugar")
        #expect(coffee.items.first?.preparation == "without sugar")
        let fried = DeterministicFoodParser.parse("2 fried eggs")
        #expect(fried.items.first?.preparation == "fried")
        let preset = DeterministicFoodParser.parse("log my usual breakfast")
        #expect(preset.refersToPreset)
        #expect(preset.presetPhrase == "usual breakfast")
        #expect(preset.items.isEmpty)
    }

    @Test("Non-food input yields no items")
    func nonFood() {
        #expect(DeterministicFoodParser.parse("nothing").items.isEmpty)
        #expect(DeterministicFoodParser.parse("   ").items.isEmpty)
    }
}
