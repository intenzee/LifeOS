import CryptoKit
import Foundation
#if canImport(DeviceCheck)
import DeviceCheck
#endif
#if canImport(Security)
import Security
#endif

// MARK: - App Attest / DeviceCheck

/// `DCAppAttestService`, behind a protocol so the client is testable on a Mac.
public protocol AppAttesting: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

/// `DCDevice` tokens, the fallback where App Attest isn't supported.
public protocol DeviceChecking: Sendable {
    var isSupported: Bool { get }
    func generateToken() async throws -> Data
}

#if canImport(DeviceCheck) && !os(watchOS)
public struct SystemAppAttest: AppAttesting {
    public init() {}

    public var isSupported: Bool { DCAppAttestService.shared.isSupported }

    public func generateKey() async throws -> String {
        try await DCAppAttestService.shared.generateKey()
    }

    public func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
    }

    public func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
    }
}

public struct SystemDeviceCheck: DeviceChecking {
    public init() {}

    public var isSupported: Bool { DCDevice.current.isSupported }

    public func generateToken() async throws -> Data {
        try await DCDevice.current.generateToken()
    }
}
#endif

// MARK: - Credentials

/// What the client remembers between launches.
public struct APICredentials: Codable, Sendable, Equatable {
    /// The App Attest key. Device-bound: never restored to another device.
    public var keyId: String?
    /// Stable per install; names DeviceCheck and debug installs on the proxy.
    public var installUUID: String
    public var token: String?
    public var tokenKind: InstallKind?
    public var tokenExpiry: Date?

    public init(keyId: String? = nil, installUUID: String = UUID().uuidString, token: String? = nil,
                tokenKind: InstallKind? = nil, tokenExpiry: Date? = nil) {
        self.keyId = keyId
        self.installUUID = installUUID
        self.token = token
        self.tokenKind = tokenKind
        self.tokenExpiry = tokenExpiry
    }
}

public protocol APICredentialStore: Sendable {
    func load() -> APICredentials?
    func save(_ credentials: APICredentials)
}

public final class MemoryCredentialStore: APICredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: APICredentials?

    public init(_ value: APICredentials? = nil) { self.value = value }

    public func load() -> APICredentials? { lock.withLock { value } }
    public func save(_ credentials: APICredentials) { lock.withLock { value = credentials } }
}

#if canImport(Security)
/// One keychain item, readable after first unlock and never synced or migrated:
/// an App Attest key id is useless on any other device.
public struct KeychainAPICredentialStore: APICredentialStore {
    private let service: String
    private let account = "lifeos.api.credentials"

    public init(service: String = "com.tanmay.LifeOS.api") { self.service = service }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    public func load() -> APICredentials? {
        var lookup = query
        lookup[kSecReturnData as String] = true
        lookup[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(lookup as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return try? JSONDecoder().decode(APICredentials.self, from: data)
    }

    public func save(_ credentials: APICredentials) {
        guard let data = try? JSONEncoder().encode(credentials) else { return }
        let attributes: [String: Any] = [kSecValueData as String: data,
                                         kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            SecItemAdd(query.merging(attributes) { $1 } as CFDictionary, nil)
        }
    }
}
#endif

// MARK: - Transport

public protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Returns once the response headers arrive; the lines follow.
    func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init(session: URLSession = URLSessionTransport.defaultSession()) { self.session = session }

    public static func defaultSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        return URLSession(configuration: config)
    }

    public func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw LifeOSAPIError.invalidResponse }
        return (data, http)
    }

    public func lines(for request: URLRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw LifeOSAPIError.invalidResponse }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines { continuation.yield(line) }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (stream, http)
    }
}

// MARK: - Hashing

enum Digest {
    static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
