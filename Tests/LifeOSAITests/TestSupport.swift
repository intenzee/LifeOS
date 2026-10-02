import Foundation
@testable import LifeOSAI

/// Network stub. Each test gets its own `URLSession` tagged with a token so
/// parallel tests never see each other's handlers or recorded requests.
nonisolated final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, Data)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]
    nonisolated(unsafe) private static var recorded: [String: [URLRequest]] = [:]
    static let tokenHeader = "X-Stub-Token"

    /// A session whose requests are answered by `handler`. Returns the token
    /// used to read back recorded requests.
    static func session(_ handler: @escaping Handler) -> (URLSession, String) {
        let token = UUID().uuidString
        lock.withLock { handlers[token] = handler }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        config.httpAdditionalHeaders = [tokenHeader: token]
        return (URLSession(configuration: config), token)
    }

    static func requests(_ token: String) -> [URLRequest] { lock.withLock { recorded[token] ?? [] } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let token = request.value(forHTTPHeaderField: Self.tokenHeader) ?? ""
        var captured = request
        if captured.httpBody == nil, let stream = request.httpBodyStream {
            captured.httpBody = Self.read(stream)
        }
        let handler = Self.lock.withLock { () -> Handler? in
            Self.recorded[token, default: []].append(captured)
            return Self.handlers[token]
        }
        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (status, body) = try handler(captured)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

nonisolated enum Fixtures {
    static let parsedMealJSON = #"{"items":[{"name":"roti","quantity":2,"unit":"piece"},{"name":"dal","quantity":1,"unit":"bowl"}],"mealType":"lunch"}"#
    static let mealPhotoJSON = #"{"name":"Fried Rice","servingSize":"1 plate","calories":520,"protein":14,"carbs":78,"fat":16,"items":[{"name":"Rice","calories":300,"protein":6,"carbs":65,"fat":2}]}"#

    static func foodRequest(_ text: String = "two rotis and a bowl of dal for lunch",
                            privacy: PrivacyClass = .personal,
                            budget: Duration = .seconds(5),
                            context: ContextPacket? = nil,
                            cache: AICachePolicy = .bypass) -> AIRequest<ParsedMeal> {
        AIRequest(task: .foodTextParse, prompt: PromptRegistry.foodTextParse(text), input: .text(text),
                  context: context, privacy: privacy, latencyBudget: budget, cachePolicy: cache)
    }

    static func photoRequest(context: ContextPacket? = nil, overrides: [ProviderID: String] = [:]) -> AIRequest<MealPhotoEstimate> {
        AIRequest(task: .mealPhotoAnalyze, prompt: PromptRegistry.mealPhotoAnalyze(),
                  input: .image(AIImage(jpegData: Data([0xFF, 0xD8, 0xFF, 0xD9]))),
                  context: context, privacy: .personal, latencyBudget: .seconds(5),
                  credentialOverrides: overrides)
    }

    static func gateway(_ providers: [any AIProvider], consents: any ConsentStoring = InMemoryConsentStore(),
                        config: AIRemoteConfig = .default, cache: AIResponseCache = AIResponseCache(),
                        quota: QuotaManager = QuotaManager()) async -> AIGateway {
        let store = AIRemoteConfigStore(remoteURL: nil, cacheURL: nil)
        await store.override(config)
        return AIGateway(providers: providers, configStore: store, quota: quota, cache: cache, consents: consents)
    }

    static let personalConsent = CloudConsent(maxPrivacy: .personal, grantedAt: Date(), source: .keyEntry)
    static let healthConsent = CloudConsent(maxPrivacy: .health, grantedAt: Date(), source: .consentSheet)
}

/// A mutable clock for quota/cache tests.
nonisolated final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date
    init(_ start: Date = Date(timeIntervalSince1970: 1_800_000_000)) { current = start }
    var now: Date { lock.withLock { current } }
    func advance(_ seconds: TimeInterval) { lock.withLock { current = current.addingTimeInterval(seconds) } }
    var provider: @Sendable () -> Date { { [self] in self.now } }
}
