import Foundation
import Testing
@testable import LifeOSAI

@Suite("QuotaManager")
struct QuotaManagerTests {

    @Test("Per-minute bucket refills after the window")
    func perMinute() async throws {
        let clock = TestClock()
        let quota = QuotaManager(limits: [.groqBYOK: .init(perMinute: 2, perDay: nil)], now: clock.provider)
        try await quota.reserve(.groqBYOK)
        try await quota.reserve(.groqBYOK)
        await #expect(throws: AIError.quotaExhausted(.groqBYOK)) { try await quota.reserve(.groqBYOK) }
        #expect(await quota.check(.groqBYOK) == .unavailable(.quotaExhausted))
        clock.advance(61)
        try await quota.reserve(.groqBYOK)
    }

    @Test("Per-day cap resets on the next UTC day")
    func perDay() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 86_400 * 20_000 + 100))
        let quota = QuotaManager(limits: [.geminiBYOK: .init(perMinute: nil, perDay: 1)], now: clock.provider)
        try await quota.reserve(.geminiBYOK)
        await #expect(throws: AIError.self) { try await quota.reserve(.geminiBYOK) }
        clock.advance(86_400)
        try await quota.reserve(.geminiBYOK)
        #expect(await quota.status(.geminiBYOK).usedToday == 1)
    }

    @Test("Three consecutive provider faults open the circuit for the cool-down, then half-open")
    func circuitBreaker() async throws {
        let clock = TestClock()
        let quota = QuotaManager(now: clock.provider)
        for _ in 0..<3 { await quota.recordFailure(.applePCC, error: .server(500)) }
        await #expect(throws: AIError.circuitOpen(.applePCC)) { try await quota.reserve(.applePCC) }
        #expect(await quota.status(.applePCC).circuitOpenUntil != nil)

        clock.advance(601)
        try await quota.reserve(.applePCC)                 // half-open trial allowed
        await quota.recordFailure(.applePCC, error: .timeout)
        await #expect(throws: AIError.self) { try await quota.reserve(.applePCC) }  // re-opened at once

        clock.advance(601)
        try await quota.reserve(.applePCC)
        await quota.recordSuccess(.applePCC)
        #expect(await quota.status(.applePCC).consecutiveFailures == 0)
    }

    @Test("User-actionable errors never trip the breaker")
    func userErrorsDontTrip() async throws {
        let quota = QuotaManager()
        for _ in 0..<5 { await quota.recordFailure(.groqBYOK, error: .authFailed(.groqBYOK)) }
        for _ in 0..<5 { await quota.recordFailure(.groqBYOK, error: .consentRequired(.groqBYOK)) }
        try await quota.reserve(.groqBYOK)
    }

    @Test("Gateway applies remote-config quotas")
    func gatewayQuota() async throws {
        var config = AIRemoteConfig.default
        config.quotas = [ProviderID.appleOnDevice.rawValue: .init(perMinute: 1, perDay: nil)]
        let t1 = MockAIProvider(id: .appleOnDevice, responding: Fixtures.parsedMealJSON)
        let t0 = MockAIProvider(id: .deterministic, responding: Fixtures.parsedMealJSON)
        let gateway = await Fixtures.gateway([t1, t0], config: config)
        #expect(try await gateway.run(Fixtures.foodRequest()).provider == .appleOnDevice)
        let second = try await gateway.run(Fixtures.foodRequest())
        #expect(second.provider == .deterministic)
        #expect(second.degradedFrom.first?.error == .quotaExhausted(.appleOnDevice))
    }
}

@Suite("AIResponseCache")
struct ResponseCacheTests {

    @Test("Identical (normalised) input is served from cache without calling a provider")
    func cacheHit() async throws {
        let t1 = MockAIProvider(id: .appleOnDevice, responding: Fixtures.parsedMealJSON)
        let gateway = await Fixtures.gateway([t1])
        let first = try await gateway.run(Fixtures.foodRequest("2 Rotis  and dal", cache: .useTaskDefault))
        let second = try await gateway.run(Fixtures.foodRequest("2 rotis and dal ", cache: .useTaskDefault))
        #expect(!first.fromCache)
        #expect(second.fromCache)
        #expect(second.output == first.output)
        #expect(second.provider == .appleOnDevice)
        #expect(t1.callCount == 1)
    }

    @Test("Bypass and uncached tasks always call the provider")
    func bypass() async throws {
        let t1 = MockAIProvider(id: .appleOnDevice, responding: Fixtures.parsedMealJSON)
        let gateway = await Fixtures.gateway([t1])
        _ = try await gateway.run(Fixtures.foodRequest(cache: .bypass))
        _ = try await gateway.run(Fixtures.foodRequest(cache: .bypass))
        #expect(t1.callCount == 2)
        #expect(AIResponseCache.defaultTTL(for: .mealPhotoAnalyze) == nil, "photo answers are not cached in Phase 0")
        #expect(AIResponseCache.defaultTTL(for: .assistantChat) == nil)
    }

    @Test("Entries expire after their TTL")
    func ttl() async throws {
        let clock = TestClock()
        let cache = AIResponseCache(now: clock.provider)
        await cache.store("k", outputJSON: Data("{}".utf8), provider: .appleOnDevice, model: "m",
                          promptVersion: "v", ttl: 60, privacy: .personal)
        #expect(await cache.lookup("k") != nil)
        clock.advance(61)
        #expect(await cache.lookup("k") == nil)
    }

    @Test("Prompt version is part of the key")
    func promptVersionInvalidates() {
        var call = ProviderCall(task: .foodTextParse, prompt: PromptRegistry.foodTextParse("dal"), input: .text("dal"),
                                context: nil, schema: ParsedMeal.schema, outputIsPlainText: false, generation: .init())
        let a = AIResponseCache.key(for: call)
        call.prompt.version = "2099.1.1"
        #expect(AIResponseCache.key(for: call) != a)
    }

    @Test("Persists to disk across instances, but never health-class answers")
    func persistence() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cache-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = AIResponseCache(fileURL: url)
        await cache.store("personal", outputJSON: Data("{}".utf8), provider: .appleOnDevice, model: "m",
                          promptVersion: "v", ttl: 600, privacy: .personal)
        await cache.store("health", outputJSON: Data("{}".utf8), provider: .appleOnDevice, model: "m",
                          promptVersion: "v", ttl: 600, privacy: .health)
        #expect(await cache.count == 2)

        let reloaded = AIResponseCache(fileURL: url)
        #expect(await reloaded.lookup("personal") != nil)
        #expect(await reloaded.lookup("health") == nil)
        await reloaded.removeAll()
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Capacity evicts the oldest entries")
    func eviction() async {
        let cache = AIResponseCache(capacity: 2)
        for key in ["a", "b", "c"] {
            await cache.store(key, outputJSON: Data(), provider: .deterministic, model: "m", promptVersion: "v",
                              ttl: 60, privacy: .public)
        }
        #expect(await cache.lookup("a") == nil)
        #expect(await cache.lookup("c") != nil)
    }
}
