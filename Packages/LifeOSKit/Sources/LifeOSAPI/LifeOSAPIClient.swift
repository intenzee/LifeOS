import Foundation

/// Client for the LifeOS AI proxy (doc 07, BE-11).
///
/// - Proves the install once with App Attest (DeviceCheck where App Attest
///   isn't supported; a debug token only in DEBUG builds against the dev proxy)
///   and keeps a 24 h install token, refreshed with an assertion.
/// - Signs every POST with an assertion over method, path, timestamp and body.
///   Signing and sending are serialised, so the proxy always sees the assertion
///   counter increase.
/// - Retries once on transient failures, re-authenticates once on a 401, and
///   maps every failure to `LifeOSAPIError` so callers can degrade.
public actor LifeOSAPIClient {
    public struct Configuration: Sendable {
        public var baseURL: URL
        /// The dev proxy's debug token, for the simulator and CI. Leave `nil` in release builds.
        public var debugToken: String?
        public var configTTL: TimeInterval
        public var maxRetries: Int
        public var retryBackoff: TimeInterval
        /// Longer server-suggested waits aren't retried in place: the caller degrades.
        public var maxInlineRetryAfter: TimeInterval

        public init(baseURL: URL, debugToken: String? = nil, configTTL: TimeInterval = 3600, maxRetries: Int = 1,
                    retryBackoff: TimeInterval = 1, maxInlineRetryAfter: TimeInterval = 5) {
            self.baseURL = baseURL
            self.debugToken = debugToken
            self.configTTL = configTTL
            self.maxRetries = maxRetries
            self.retryBackoff = retryBackoff
            self.maxInlineRetryAfter = maxInlineRetryAfter
        }
    }

    private let configuration: Configuration
    private let transport: any HTTPTransport
    private let attest: (any AppAttesting)?
    private let deviceCheck: (any DeviceChecking)?
    private let store: any APICredentialStore
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (TimeInterval) async throws -> Void

    private var credentials: APICredentials
    private var authTask: Task<APICredentials, Error>?
    private var signingTail: Task<Void, Never>?
    private var cachedConfig: (config: ProxyRemoteConfig, fetchedAt: Date)?

    static let tokenRefreshMargin: TimeInterval = 300

    public init(configuration: Configuration,
                transport: any HTTPTransport = URLSessionTransport(),
                attest: (any AppAttesting)?,
                deviceCheck: (any DeviceChecking)?,
                store: any APICredentialStore,
                now: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
                    try await Task.sleep(nanoseconds: UInt64($0 * 1_000_000_000))
                }) {
        self.configuration = configuration
        self.transport = transport
        self.attest = attest
        self.deviceCheck = deviceCheck
        self.store = store
        self.now = now
        self.sleep = sleep
        if let saved = store.load() {
            credentials = saved
        } else {
            credentials = APICredentials()
            store.save(credentials)
        }
    }

    // MARK: - Public API

    /// A chat completion on `route`. `body` is OpenAI-compatible JSON without `model`.
    public func complete(_ route: AIRoute, body: Data) async throws -> APIResponse {
        let (data, response) = try await perform { try await self.sendData(.post(route.rawValue, body), $0) }
        return APIResponse(body: data, model: response.value(forHTTPHeaderField: "X-LifeOS-Model"),
                           quotaRemaining: response.value(forHTTPHeaderField: "X-LifeOS-Quota-Remaining").flatMap(Int.init))
    }

    /// Streams `/v1/chat` (`"stream": true` is set for you). Yields each SSE
    /// `data:` payload (an OpenAI chunk as JSON) and ends at `[DONE]`.
    public func stream(body: Data) async throws -> AsyncThrowingStream<String, Error> {
        let streamed = try Self.settingStream(body)
        let (lines, _) = try await perform { try await self.sendLines(.post(AIRoute.chat.rawValue, streamed), $0) }
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await line in lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" { break }
                        continuation.yield(payload)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.map(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// A packaged food by barcode; `nil` when nobody has it.
    public func food(barcode: String) async throws -> ProxyFood? {
        do {
            let (data, _) = try await perform { try await self.sendData(.get("/v1/food/barcode/\(barcode)"), $0) }
            return try Self.decode(ProxyFood.self, data)
        } catch LifeOSAPIError.notFound {
            return nil
        }
    }

    public func searchFoods(_ query: String) async throws -> [ProxyFood] {
        struct Page: Decodable { let items: [ProxyFood] }
        let (data, _) = try await perform {
            try await self.sendData(.get("/v1/food/search", query: [URLQueryItem(name: "q", value: query)]), $0)
        }
        return try Self.decode(Page.self, data).items
    }

    /// Remote config, cached for `configTTL` (an hour). Needs no token.
    public func remoteConfig(forceRefresh: Bool = false) async throws -> ProxyRemoteConfig {
        if !forceRefresh, let cachedConfig, now().timeIntervalSince(cachedConfig.fetchedAt) < configuration.configTTL {
            return cachedConfig.config
        }
        let (data, response) = try await raw(.get("/v1/config"), token: nil)
        try Self.check(response, data)
        let config = try Self.decode(ProxyRemoteConfig.self, data)
        cachedConfig = (config, now())
        return config
    }

    /// Forgets the token and the App Attest key (a new key is attested next time).
    public func resetInstall() {
        credentials = APICredentials(installUUID: credentials.installUUID)
        store.save(credentials)
    }

    /// How this install is currently authenticated, if it is.
    public var installKind: InstallKind? { credentials.token == nil ? nil : credentials.tokenKind }

    // MARK: - Retry and re-authentication

    private func perform<T: Sendable>(_ operation: @Sendable (APICredentials) async throws -> T) async throws -> T {
        var reauthenticated = false
        var attempt = 0
        while true {
            do {
                return try await operation(try await validCredentials())
            } catch {
                let failure = Self.map(error)
                if failure == .unauthorized, !reauthenticated {
                    reauthenticated = true
                    credentials.token = nil
                    store.save(credentials)
                    continue
                }
                guard attempt < configuration.maxRetries, let wait = retryDelay(for: failure) else { throw failure }
                attempt += 1
                try await sleep(wait)
            }
        }
    }

    private func retryDelay(for failure: LifeOSAPIError) -> TimeInterval? {
        switch failure {
        case .network, .server: return configuration.retryBackoff
        case .serviceBusy(let after), .rateLimited(let after):
            return after <= configuration.maxInlineRetryAfter ? max(after, configuration.retryBackoff) : nil
        default: return nil
        }
    }

    // MARK: - Install token

    private func validCredentials() async throws -> APICredentials {
        if credentials.token != nil, let expiry = credentials.tokenExpiry,
           expiry.timeIntervalSince(now()) > Self.tokenRefreshMargin {
            return credentials
        }
        if let authTask { return try await authTask.value }
        let task = Task { try await self.authenticate() }
        authTask = task
        defer { authTask = nil }
        return try await task.value
    }

    private func authenticate() async throws -> APICredentials {
        if let attest, attest.isSupported {
            if let keyId = credentials.keyId {
                do {
                    return adopt(try await refresh(keyId: keyId, attest: attest))
                } catch LifeOSAPIError.unauthorized {
                    // The proxy no longer knows this key (or it was reset): attest a new one.
                    credentials.keyId = nil
                }
            }
            return adopt(try await register(attest))
        }
        if let deviceCheck, deviceCheck.isSupported {
            let token: Data
            do {
                token = try await deviceCheck.generateToken()
            } catch {
                throw LifeOSAPIError.attestationFailed("DeviceCheck: \(error.localizedDescription)")
            }
            let body = try Self.json(["deviceToken": token.base64EncodedString(), "installUUID": credentials.installUUID])
            return adopt(try await tokenRequest(.post("/v1/attest/devicecheck", body)))
        }
        if let debugToken = configuration.debugToken {
            let body = try Self.json(["installUUID": credentials.installUUID])
            return adopt(try await tokenRequest(.post("/v1/attest/debug", body,
                                                                headers: ["X-LifeOS-Debug": debugToken])))
        }
        throw LifeOSAPIError.unavailable
    }

    private struct TokenReply: Decodable {
        let installToken: String
        let expiresIn: TimeInterval
        let kind: InstallKind
        var keyId: String?
    }

    private func register(_ attest: any AppAttesting) async throws -> TokenReply {
        struct Challenge: Decodable { let challenge: String }
        let (challengeData, challengeResponse) = try await raw(.post("/v1/attest/challenge", Data("{}".utf8)), token: nil)
        try Self.check(challengeResponse, challengeData)
        let challenge = try Self.decode(Challenge.self, challengeData).challenge

        let keyId: String
        let attestation: Data
        do {
            keyId = try await attest.generateKey()
            attestation = try await attest.attestKey(keyId, clientDataHash: Digest.sha256(Data(challenge.utf8)))
        } catch {
            throw LifeOSAPIError.attestationFailed(error.localizedDescription)
        }
        let body = try Self.json(["keyId": keyId, "attestation": attestation.base64EncodedString(),
                                  "challenge": challenge])
        var reply = try await tokenRequest(.post("/v1/attest/register", body))
        reply.keyId = keyId
        return reply
    }

    private func refresh(keyId: String, attest: any AppAttesting) async throws -> TokenReply {
        let request = Request.post("/v1/attest/refresh", try Self.json(["keyId": keyId]))
        let signer = APICredentials(keyId: keyId, installUUID: credentials.installUUID, tokenKind: .attest)
        var reply = try await serially {
            let (data, response) = try await self.raw(request, token: nil, signedBy: signer)
            try Self.check(response, data)
            return try Self.decode(TokenReply.self, data)
        }
        reply.keyId = keyId
        return reply
    }

    private func tokenRequest(_ request: Request) async throws -> TokenReply {
        let (data, response) = try await raw(request, token: nil)
        do {
            try Self.check(response, data)
        } catch LifeOSAPIError.unauthorized {
            throw LifeOSAPIError.attestationFailed("the proxy rejected this install")
        }
        return try Self.decode(TokenReply.self, data)
    }

    private func adopt(_ reply: TokenReply) -> APICredentials {
        credentials.token = reply.installToken
        credentials.tokenKind = reply.kind
        credentials.tokenExpiry = now().addingTimeInterval(reply.expiresIn)
        if let keyId = reply.keyId { credentials.keyId = keyId }
        store.save(credentials)
        return credentials
    }

    // MARK: - Requests

    private func sendData(_ request: Request, _ creds: APICredentials) async throws -> (Data, HTTPURLResponse) {
        let work: @Sendable () async throws -> (Data, HTTPURLResponse) = {
            let (data, response) = try await self.raw(request, token: creds.token, signedBy: creds)
            try Self.check(response, data)
            return (data, response)
        }
        return Self.needsAssertion(request, creds) ? try await serially(work) : try await work()
    }

    private func sendLines(_ request: Request, _ creds: APICredentials)
        async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        try await serially {
            let urlRequest = try await self.urlRequest(request, token: creds.token, signedBy: creds)
            let (lines, response) = try await self.transport.lines(for: urlRequest)
            guard (200..<300).contains(response.statusCode) else {
                var body = ""
                for try await line in lines { body += line }
                try Self.check(response, Data(body.utf8))
                throw LifeOSAPIError.invalidResponse
            }
            return (lines, response)
        }
    }

    private func raw(_ request: Request, token: String?, signedBy creds: APICredentials? = nil)
        async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.data(for: try await urlRequest(request, token: token, signedBy: creds))
        } catch {
            throw Self.map(error)
        }
    }

    private static func needsAssertion(_ request: Request, _ creds: APICredentials?) -> Bool {
        request.method == "POST" && creds?.tokenKind == .attest && creds?.keyId != nil
    }

    private func urlRequest(_ request: Request, token: String?, signedBy creds: APICredentials?) async throws
        -> URLRequest {
        var components = URLComponents(url: configuration.baseURL.appendingPathComponent(request.path),
                                       resolvingAgainstBaseURL: false)
        if !request.query.isEmpty { components?.queryItems = request.query }
        guard let url = components?.url else { throw LifeOSAPIError.badRequest("bad URL") }
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        if request.body != nil { urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let token { urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }

        if Self.needsAssertion(request, creds), let keyId = creds?.keyId, let attest {
            let timestamp = String(Int64(now().timeIntervalSince1970 * 1000))
            let clientData = Self.clientData(method: request.method, path: url.path, timestamp: timestamp,
                                             body: request.body ?? Data())
            let assertion: Data
            do {
                assertion = try await attest.generateAssertion(keyId, clientDataHash: Digest.sha256(clientData))
            } catch {
                // A key the system no longer has: start over with a new one.
                throw LifeOSAPIError.unauthorized
            }
            urlRequest.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-LifeOS-Assertion")
            urlRequest.setValue(timestamp, forHTTPHeaderField: "X-LifeOS-Timestamp")
        }
        return urlRequest
    }

    /// Runs `work` after every earlier signed request has been sent.
    private func serially<T: Sendable>(_ work: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = signingTail
        let task = Task { () async throws -> T in
            await previous?.value
            return try await work()
        }
        signingTail = Task { _ = try? await task.value }
        return try await task.value
    }
}
