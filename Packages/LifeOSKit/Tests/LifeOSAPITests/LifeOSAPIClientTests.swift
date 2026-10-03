import CryptoKit
import Foundation
import Testing
@testable import LifeOSAPI

// MARK: - Fakes

final class FakeAttest: AppAttesting, @unchecked Sendable {
    private let lock = NSLock()
    var isSupported = true
    private(set) var keys = 0
    private(set) var attestedHashes: [Data] = []
    private(set) var assertedHashes: [Data] = []
    var failAssertions = false

    func generateKey() async throws -> String {
        lock.withLock {
            keys += 1
            return "key-\(keys)"
        }
    }

    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        lock.withLock { attestedHashes.append(clientDataHash) }
        return Data("attestation-\(keyId)".utf8)
    }

    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try lock.withLock {
            if failAssertions { throw CancellationError() }
            assertedHashes.append(clientDataHash)
            return Data("assertion-\(assertedHashes.count)".utf8)
        }
    }
}

struct FakeDeviceCheck: DeviceChecking {
    var isSupported = true
    func generateToken() async throws -> Data { Data("device-token".utf8) }
}

/// Records requests and answers them with `handler`.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    struct Reply {
        var status: Int
        var body: String
        var headers: [String: String] = [:]
        var delay: TimeInterval = 0
    }

    private let lock = NSLock()
    private(set) var requests: [URLRequest] = []
    var handler: @Sendable (URLRequest) throws -> Reply = { _ in Reply(status: 500, body: "{}") }

    var paths: [String] { lock.withLock { requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } } }

    func requests(to path: String) -> [URLRequest] { lock.withLock { requests.filter { $0.url?.path == path } } }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { requests.append(request) }
        let reply = try handler(request)
        if reply.delay > 0 { try await Task.sleep(nanoseconds: UInt64(reply.delay * 1_000_000_000)) }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil,
                                       headerFields: reply.headers)!
        return (Data(reply.body.utf8), response)
    }

    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        let lines = String(decoding: data, as: UTF8.self).components(separatedBy: "\n")
        return (AsyncThrowingStream { continuation in
            for line in lines { continuation.yield(line) }
            continuation.finish()
        }, response)
    }
}

final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date(timeIntervalSince1970: 1_790_000_000)
    private(set) var sleeps: [TimeInterval] = []

    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value += seconds } }
    func sleep(_ seconds: TimeInterval) { lock.withLock { sleeps.append(seconds); value += seconds } }
}

private func body(_ request: URLRequest) -> [String: Any] {
    (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
}

private let tokenReply = #"{"installToken":"tok-1","expiresIn":86400,"kind":"attest"}"#
private let completion = #"{"choices":[{"message":{"content":"{\"items\":[]}"}}]}"#

/// The proxy's happy path; `overrides` answer specific paths first.
private func proxy(_ overrides: [String: (URLRequest) -> FakeTransport.Reply] = [:])
    -> @Sendable (URLRequest) throws -> FakeTransport.Reply {
    nonisolated(unsafe) let overrides = overrides
    return { request in
        let path = request.url?.path ?? ""
        if let override = overrides[path] { return override(request) }
        switch path {
        case "/v1/attest/challenge": return .init(status: 200, body: #"{"challenge":"chal-123"}"#)
        case "/v1/attest/register", "/v1/attest/refresh": return .init(status: 200, body: tokenReply)
        case "/v1/attest/devicecheck":
            return .init(status: 200, body: #"{"installToken":"tok-dc","expiresIn":86400,"kind":"devicecheck"}"#)
        case "/v1/attest/debug":
            return .init(status: 200, body: #"{"installToken":"tok-dbg","expiresIn":86400,"kind":"debug"}"#)
        default:
            return .init(status: 200, body: completion,
                         headers: ["X-LifeOS-Model": "qwen/qwen3.6-27b", "X-LifeOS-Quota-Remaining": "99"])
        }
    }
}

// MARK: - Tests

@Suite("LifeOS API client")
struct LifeOSAPIClientTests {
    let transport = FakeTransport()
    let attest = FakeAttest()
    let clock = TestClock()
    let store = MemoryCredentialStore()
    let parseBody = Data(#"{"messages":[{"role":"user","content":"two rotis"}]}"#.utf8)

    func client(attest: (any AppAttesting)? = nil, deviceCheck: (any DeviceChecking)? = nil,
                debugToken: String? = nil) -> LifeOSAPIClient {
        let clock = clock
        return LifeOSAPIClient(configuration: .init(baseURL: URL(string: "https://proxy.test")!, debugToken: debugToken),
                               transport: transport, attest: attest ?? self.attest, deviceCheck: deviceCheck,
                               store: store, now: { clock.now }, sleep: { clock.sleep($0) })
    }

    @Test func attestsOnceThenSignsEachRequest() async throws {
        transport.handler = proxy()
        let api = client()
        let first = try await api.complete(.parseMeal, body: parseBody)
        #expect(first.content == #"{"items":[]}"#)
        #expect(first.model == "qwen/qwen3.6-27b")
        #expect(first.quotaRemaining == 99)
        _ = try await api.complete(.parseMeal, body: parseBody)

        #expect(transport.paths == ["POST /v1/attest/challenge", "POST /v1/attest/register",
                                    "POST /v1/parse/meal", "POST /v1/parse/meal"])
        let register = try #require(transport.requests(to: "/v1/attest/register").first)
        #expect(body(register)["keyId"] as? String == "key-1")
        #expect(body(register)["challenge"] as? String == "chal-123")
        #expect(attest.attestedHashes == [Data(SHA256.hash(data: Data("chal-123".utf8)))])

        let parse = try #require(transport.requests(to: "/v1/parse/meal").first)
        #expect(parse.value(forHTTPHeaderField: "Authorization") == "Bearer tok-1")
        let timestamp = try #require(parse.value(forHTTPHeaderField: "X-LifeOS-Timestamp"))
        #expect(parse.value(forHTTPHeaderField: "X-LifeOS-Assertion") == Data("assertion-1".utf8).base64EncodedString())
        let expected = LifeOSAPIClient.clientData(method: "POST", path: "/v1/parse/meal", timestamp: timestamp,
                                                  body: parseBody)
        #expect(attest.assertedHashes.first == Data(SHA256.hash(data: expected)))
        #expect(store.load()?.keyId == "key-1")
        #expect(await api.installKind == .attest)
    }

    /// The proxy computes the same bytes (`clientDataForRequest` in attest.ts).
    @Test func clientDataMatchesTheProxy() {
        let data = LifeOSAPIClient.clientData(method: "post", path: "/v1/chat", timestamp: "1", body: Data("{}".utf8))
        #expect(String(decoding: data, as: UTF8.self)
                == "POST\n/v1/chat\n1\n44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a")
    }

    @Test func refreshesAnExpiringTokenWithAnAssertion() async throws {
        transport.handler = proxy()
        let api = client()
        _ = try await api.complete(.parseMeal, body: parseBody)
        clock.advance(86_400 - 200)                      // inside the 5-minute margin
        _ = try await api.complete(.parseMeal, body: parseBody)
        let refresh = try #require(transport.requests(to: "/v1/attest/refresh").first)
        #expect(refresh.value(forHTTPHeaderField: "X-LifeOS-Assertion") != nil)
        #expect(body(refresh)["keyId"] as? String == "key-1")
        #expect(attest.keys == 1)                        // no new key
    }

    @Test func aForgottenInstallAttestsANewKey() async throws {
        store.save(APICredentials(keyId: "old-key", installUUID: "u"))
        transport.handler = proxy(["/v1/attest/refresh": { _ in
            .init(status: 401, body: #"{"error":"unknown_install"}"#)
        }])
        _ = try await client().complete(.parseMeal, body: parseBody)
        #expect(transport.paths.prefix(3) == ["POST /v1/attest/refresh", "POST /v1/attest/challenge",
                                              "POST /v1/attest/register"])
        #expect(store.load()?.keyId == "key-1")
    }

    @Test func a401ReauthenticatesOnceThenGivesUp() async throws {
        nonisolated(unsafe) var parses = 0
        transport.handler = proxy(["/v1/parse/meal": { _ in
            parses += 1
            return parses == 1 ? .init(status: 401, body: #"{"error":"assertion_failed"}"#)
                               : .init(status: 200, body: completion)
        }])
        let api = client()
        _ = try await api.complete(.parseMeal, body: parseBody)
        #expect(transport.requests(to: "/v1/attest/refresh").count == 1)

        transport.handler = proxy(["/v1/parse/meal": { _ in .init(status: 401, body: #"{"error":"unauthorized"}"#) }])
        await #expect(throws: LifeOSAPIError.unauthorized) { try await api.complete(.parseMeal, body: parseBody) }
    }

    @Test func mapsProxyErrorsAndRetriesOnlyShortTransientOnes() async throws {
        let api = client()
        transport.handler = proxy(["/v1/parse/meal": { _ in
            .init(status: 429, body: #"{"error":"daily_quota","retryAfter":3600}"#)
        }])
        await #expect(throws: LifeOSAPIError.quotaExceeded(retryAfter: 3600)) {
            try await api.complete(.parseMeal, body: parseBody)
        }
        transport.handler = proxy(["/v1/parse/meal": { _ in .init(status: 503, body: #"{"error":"disabled"}"#) }])
        await #expect(throws: LifeOSAPIError.disabled) { try await api.complete(.parseMeal, body: parseBody) }
        transport.handler = proxy(["/v1/parse/meal": { _ in
            .init(status: 502, body: #"{"error":"no_model_available"}"#)
        }])
        await #expect(throws: LifeOSAPIError.noModelAvailable) { try await api.complete(.parseMeal, body: parseBody) }
        #expect(clock.sleeps.isEmpty)

        nonisolated(unsafe) var calls = 0
        transport.handler = proxy(["/v1/parse/meal": { _ in
            calls += 1
            return calls == 1 ? .init(status: 503, body: #"{"error":"provider_busy","retryAfter":2}"#)
                              : .init(status: 200, body: completion)
        }])
        _ = try await api.complete(.parseMeal, body: parseBody)
        #expect(clock.sleeps == [2])

        transport.handler = proxy(["/v1/parse/meal": { _ in
            .init(status: 503, body: #"{"error":"provider_busy","retryAfter":60}"#)
        }])
        await #expect(throws: LifeOSAPIError.serviceBusy(retryAfter: 60)) {
            try await api.complete(.parseMeal, body: parseBody)
        }
        #expect(clock.sleeps == [2])                     // 60 s isn't waited in place
    }

    @Test func networkErrorsAreRetriedOnce() async throws {
        nonisolated(unsafe) var calls = 0
        transport.handler = proxy(["/v1/parse/meal": { _ in
            calls += 1
            return .init(status: 200, body: completion)
        }])
        let wrapped = transport.handler
        nonisolated(unsafe) var failed = false
        transport.handler = { request in
            if request.url?.path == "/v1/parse/meal", !failed {
                failed = true
                throw URLError(.timedOut)
            }
            return try wrapped(request)
        }
        _ = try await client().complete(.parseMeal, body: parseBody)
        #expect(calls == 1)
        #expect(clock.sleeps == [1])
    }

    @Test func fallsBackToDeviceCheckThenDebugThenGivesUp() async throws {
        transport.handler = proxy()
        attest.isSupported = false
        _ = try await client(deviceCheck: FakeDeviceCheck()).complete(.parseMeal, body: parseBody)
        let dc = try #require(transport.requests(to: "/v1/attest/devicecheck").first)
        #expect(body(dc)["deviceToken"] as? String == Data("device-token".utf8).base64EncodedString())
        #expect(transport.requests(to: "/v1/parse/meal").first?.value(forHTTPHeaderField: "X-LifeOS-Assertion") == nil)

        store.save(APICredentials(installUUID: "u"))
        _ = try await client(debugToken: "letmein").complete(.parseMeal, body: parseBody)
        #expect(transport.requests(to: "/v1/attest/debug").first?.value(forHTTPHeaderField: "X-LifeOS-Debug") == "letmein")

        store.save(APICredentials(installUUID: "u"))
        await #expect(throws: LifeOSAPIError.unavailable) {
            try await client().complete(.parseMeal, body: parseBody)
        }
    }

    @Test func signedRequestsReachTheProxyInCounterOrder() async throws {
        // The first signed request is slow; the second must still wait for it.
        let slowFirst: (URLRequest) -> FakeTransport.Reply = { request in
            let first = request.value(forHTTPHeaderField: "X-LifeOS-Assertion")
                == Data("assertion-1".utf8).base64EncodedString()
            return .init(status: 200, body: completion, delay: first ? 0.05 : 0)
        }
        transport.handler = proxy(["/v1/parse/meal": slowFirst, "/v1/vision/meal": slowFirst])
        let api = client()
        async let one = api.complete(.parseMeal, body: parseBody)
        async let two = api.complete(.visionMeal, body: parseBody)
        _ = try await (one, two)
        let sent = transport.requests.compactMap { $0.value(forHTTPHeaderField: "X-LifeOS-Assertion") }
        #expect(sent == [Data("assertion-1".utf8).base64EncodedString(), Data("assertion-2".utf8).base64EncodedString()])
        #expect(attest.keys == 1)                        // one registration for both
    }

    @Test func cachesRemoteConfigForAnHour() async throws {
        let config = #"{"version":"v","minimumAppVersion":"1.0","flags":{"proxyEnabled":true},"#
            + #""killSwitches":{"chat":true},"quotas":{"photo":25},"routes":{}}"#
        transport.handler = proxy(["/v1/config": { _ in .init(status: 200, body: config) }])
        let api = client()
        #expect(try await api.remoteConfig().isDisabled(.chat))
        _ = try await api.remoteConfig()
        #expect(transport.requests(to: "/v1/config").count == 1)
        #expect(transport.requests(to: "/v1/config").first?.value(forHTTPHeaderField: "Authorization") == nil)
        clock.advance(3_601)
        _ = try await api.remoteConfig()
        #expect(transport.requests(to: "/v1/config").count == 2)
    }

    @Test func looksUpFoods() async throws {
        let food = #"{"id":"off:1","source":"openfoodfacts","barcode":"8901719101038","name":"Parle-G","#
            + #""per100g":{"kcal":450,"proteinG":7,"carbsG":77,"fatG":12},"#
            + #""attribution":{"source":"Open Food Facts","license":"ODbL-1.0","url":"u"}}"#
        transport.handler = proxy([
            "/v1/food/barcode/8901719101038": { _ in .init(status: 200, body: food) },
            "/v1/food/barcode/00000000": { _ in .init(status: 404, body: #"{"error":"not_found"}"#) },
            "/v1/food/search": { _ in .init(status: 200, body: "{\"items\":[\(food)]}") },
        ])
        let api = client()
        #expect(try await api.food(barcode: "8901719101038")?.name == "Parle-G")
        #expect(try await api.food(barcode: "00000000") == nil)
        #expect(try await api.searchFoods("dal makhani").first?.attribution.license == "ODbL-1.0")
        let search = try #require(transport.requests(to: "/v1/food/search").first)
        #expect(search.url?.query == "q=dal%20makhani")
        #expect(search.value(forHTTPHeaderField: "X-LifeOS-Assertion") == nil)   // GETs aren't signed
    }

    @Test func streamsChatPayloadsUntilDone() async throws {
        let sse = "data: {\"a\":1}\n\n: keep-alive\ndata: {\"a\":2}\ndata: [DONE]\ndata: {\"a\":3}\n"
        transport.handler = proxy(["/v1/chat": { _ in
            .init(status: 200, body: sse, headers: ["Content-Type": "text/event-stream"])
        }])
        var payloads: [String] = []
        for try await payload in try await client().stream(body: Data(#"{"messages":[]}"#.utf8)) {
            payloads.append(payload)
        }
        #expect(payloads == [#"{"a":1}"#, #"{"a":2}"#])
        #expect(body(try #require(transport.requests(to: "/v1/chat").first))["stream"] as? Bool == true)
    }

    @Test func resetKeepsTheInstallUUID() async throws {
        transport.handler = proxy()
        let api = client()
        _ = try await api.complete(.parseMeal, body: parseBody)
        let uuid = store.load()?.installUUID
        await api.resetInstall()
        #expect(store.load()?.keyId == nil)
        #expect(store.load()?.token == nil)
        #expect(store.load()?.installUUID == uuid)
        #expect(await api.installKind == nil)
    }
}
