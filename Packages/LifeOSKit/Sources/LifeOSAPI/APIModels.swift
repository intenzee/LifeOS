import Foundation

/// The proxy's AI routes (doc 07 §3). Bodies are OpenAI-compatible chat
/// completions without `model`: the proxy picks the model.
public enum AIRoute: String, Sendable, CaseIterable {
    case visionMeal = "/v1/vision/meal"
    case parseMeal = "/v1/parse/meal"
    case chat = "/v1/chat"
}

/// A non-streaming answer: the provider's chat-completion JSON, untouched.
public struct APIResponse: Sendable, Equatable {
    public let body: Data
    /// The model the proxy used (`X-LifeOS-Model`).
    public let model: String?
    /// Requests left today on this route's quota.
    public let quotaRemaining: Int?

    public init(body: Data, model: String?, quotaRemaining: Int?) {
        self.body = body
        self.model = model
        self.quotaRemaining = quotaRemaining
    }

    /// `choices[0].message.content`, the part callers usually want.
    public var content: String? {
        struct Payload: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        return (try? JSONDecoder().decode(Payload.self, from: body))?.choices.first?.message.content
    }
}

/// Typed failures. Every case leaves the app able to degrade: on-device
/// parsing, on-device Vision, cached foods (doc 07 §6).
public enum LifeOSAPIError: Error, Sendable, Equatable {
    /// No way to authenticate this install (no App Attest, DeviceCheck or debug token).
    case unavailable
    case attestationFailed(String)
    case unauthorized
    /// The install's daily allowance for this route is used up.
    case quotaExceeded(retryAfter: TimeInterval)
    case rateLimited(retryAfter: TimeInterval)
    /// Providers are throttling or down; the proxy's breaker is open.
    case serviceBusy(retryAfter: TimeInterval)
    /// A kill switch turned this route off.
    case disabled
    case badRequest(String)
    case notFound
    case noModelAvailable
    case server(Int)
    case network(String)
    case invalidResponse
    case cancelled

    /// Worth retrying later without changing anything.
    public var isTransient: Bool {
        switch self {
        case .rateLimited, .serviceBusy, .network, .server: return true
        default: return false
        }
    }
}

/// `GET /v1/food/…` items (BE-07). Nutrition is per 100 g.
public struct ProxyFood: Codable, Sendable, Equatable, Identifiable {
    public struct Per100g: Codable, Sendable, Equatable {
        public let kcal: Double
        public let proteinG: Double
        public let carbsG: Double
        public let fatG: Double
        public let fiberG: Double?
        public let sugarG: Double?
        public let sodiumMg: Double?
    }

    /// Open Food Facts data is ODbL: show this wherever the item is shown.
    public struct Attribution: Codable, Sendable, Equatable {
        public let source: String
        public let license: String
        public let url: String
    }

    public let id: String
    public let source: String
    public let barcode: String?
    public let name: String
    public let brand: String?
    public let servingSizeG: Double?
    public let servingLabel: String?
    public let per100g: Per100g
    public let attribution: Attribution
}

/// `GET /v1/config` (BE-08), cached for an hour by the client.
public struct ProxyRemoteConfig: Codable, Sendable, Equatable {
    public struct Target: Codable, Sendable, Equatable {
        public let provider: String
        public let models: [String]
    }

    public let version: String
    public let minimumAppVersion: String
    public let flags: [String: Bool]
    public let killSwitches: [String: Bool]
    public let quotas: [String: Int]
    public let routes: [String: [Target]]

    public func isDisabled(_ route: AIRoute) -> Bool {
        switch route {
        case .visionMeal: return killSwitches["vision.meal"] == true
        case .parseMeal: return killSwitches["parse.meal"] == true
        case .chat: return killSwitches["chat"] == true
        }
    }
}

/// How the install proved itself.
public enum InstallKind: String, Codable, Sendable {
    case attest, devicecheck, debug
}
