import Foundation
import OSLog

/// The `ai` section of the app's remote config (contract C10, F01 FR3/FR7/FR8).
///
/// Lets us rotate model IDs, re-route tasks, set quotas and kill-switch any
/// provider without an app update. Every field is optional on the wire: missing
/// values fall back to `AIRemoteConfig.default`, unknown keys are ignored, so an
/// old app never breaks on a newer config file.
nonisolated struct AIRemoteConfig: Codable, Sendable, Equatable {
    var promptVersion: String
    var groqVisionModels: [String]
    var groqTextModels: [String]
    var geminiModels: [String]
    var flags: Flags
    /// Per-task provider chains overriding the code-defined routing table.
    var routing: [String: [ProviderID]]
    /// Providers switched off globally (model-rotation drills, incidents).
    var disabledProviders: [ProviderID]
    var quotas: [String: QuotaManager.Limits]

    nonisolated struct Flags: Codable, Sendable, Equatable {
        var pccEnabled: Bool
        /// Phase 0 keeps photo scanning byte-for-byte identical; F04 flips this on
        /// to put Apple's on-device/PCC vision ahead of BYOK in the photo chain.
        var photoAppleVision: Bool
        var assistant: Bool
        var autoLogPresets: Bool
        /// F04: per-item grams resolved against the nutrition catalog. Off → schema v1 (Phase 0 behaviour).
        var photoSchemaV2: Bool

        func isOn(_ flag: AIFeatureFlag) -> Bool {
            switch flag {
            case .pccEnabled: pccEnabled
            case .photoAppleVision: photoAppleVision
            case .assistant: assistant
            case .autoLogPresets: autoLogPresets
            case .photoSchemaV2: photoSchemaV2
            }
        }

        static let `default` = Flags(pccEnabled: true, photoAppleVision: false, assistant: false, autoLogPresets: false,
                                     photoSchemaV2: true)

        init(pccEnabled: Bool, photoAppleVision: Bool, assistant: Bool, autoLogPresets: Bool, photoSchemaV2: Bool = true) {
            self.pccEnabled = pccEnabled
            self.photoAppleVision = photoAppleVision
            self.assistant = assistant
            self.autoLogPresets = autoLogPresets
            self.photoSchemaV2 = photoSchemaV2
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let d = Flags.default
            pccEnabled = try c.decodeIfPresent(Bool.self, forKey: .pccEnabled) ?? d.pccEnabled
            photoAppleVision = try c.decodeIfPresent(Bool.self, forKey: .photoAppleVision) ?? d.photoAppleVision
            assistant = try c.decodeIfPresent(Bool.self, forKey: .assistant) ?? d.assistant
            autoLogPresets = try c.decodeIfPresent(Bool.self, forKey: .autoLogPresets) ?? d.autoLogPresets
            photoSchemaV2 = try c.decodeIfPresent(Bool.self, forKey: .photoSchemaV2) ?? d.photoSchemaV2
        }
    }

    static let `default` = AIRemoteConfig(
        promptVersion: PromptRegistry.version,
        // Same list `GroqMealAnalyzer` shipped with (2026-09); preview models, so
        // they are expected to rotate — that's what this config is for.
        groqVisionModels: ["qwen/qwen3.6-27b", "qwen/qwen3.8-27b"],
        groqTextModels: ["qwen/qwen3.6-27b", "qwen/qwen3.8-27b"],
        geminiModels: ["gemini-flash-lite-latest", "gemini-flash-latest"],
        flags: .default,
        routing: [:],
        disabledProviders: [],
        quotas: [
            // Conservative defaults under the providers' published free tiers.
            ProviderID.groqBYOK.rawValue: .init(perMinute: 25, perDay: 900),
            ProviderID.geminiBYOK.rawValue: .init(perMinute: 12, perDay: 900),
        ]
    )

    init(promptVersion: String, groqVisionModels: [String], groqTextModels: [String], geminiModels: [String],
         flags: Flags, routing: [String: [ProviderID]], disabledProviders: [ProviderID],
         quotas: [String: QuotaManager.Limits]) {
        self.promptVersion = promptVersion
        self.groqVisionModels = groqVisionModels
        self.groqTextModels = groqTextModels
        self.geminiModels = geminiModels
        self.flags = flags
        self.routing = routing
        self.disabledProviders = disabledProviders
        self.quotas = quotas
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AIRemoteConfig.default
        promptVersion = try c.decodeIfPresent(String.self, forKey: .promptVersion) ?? d.promptVersion
        groqVisionModels = Self.nonEmpty(try c.decodeIfPresent([String].self, forKey: .groqVisionModels)) ?? d.groqVisionModels
        groqTextModels = Self.nonEmpty(try c.decodeIfPresent([String].self, forKey: .groqTextModels)) ?? d.groqTextModels
        geminiModels = Self.nonEmpty(try c.decodeIfPresent([String].self, forKey: .geminiModels)) ?? d.geminiModels
        flags = try c.decodeIfPresent(Flags.self, forKey: .flags) ?? d.flags
        // Unknown provider names in a newer config are dropped, not fatal.
        let rawRouting = try c.decodeIfPresent([String: [String]].self, forKey: .routing) ?? [:]
        routing = rawRouting.mapValues { $0.compactMap(ProviderID.init(rawValue:)) }
        let rawDisabled = try c.decodeIfPresent([String].self, forKey: .disabledProviders) ?? []
        disabledProviders = rawDisabled.compactMap(ProviderID.init(rawValue:))
        quotas = try c.decodeIfPresent([String: QuotaManager.Limits].self, forKey: .quotas) ?? d.quotas
    }

    private static func nonEmpty(_ list: [String]?) -> [String]? {
        guard let list, !list.isEmpty else { return nil }
        return list
    }

    var quotaLimits: [ProviderID: QuotaManager.Limits] {
        Dictionary(uniqueKeysWithValues: quotas.compactMap { key, value in
            ProviderID(rawValue: key).map { ($0, value) }
        })
    }

    /// Decodes either the bare `ai` object or the full app config `{ "ai": { … } }`.
    static func decode(from data: Data) throws -> AIRemoteConfig {
        struct Envelope: Decodable { let ai: AIRemoteConfig }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) { return envelope.ai }
        return try JSONDecoder().decode(AIRemoteConfig.self, from: data)
    }
}

/// Remote-config feature flags the routing table can depend on.
nonisolated enum AIFeatureFlag: String, Sendable, CaseIterable {
    case pccEnabled, photoAppleVision, assistant, autoLogPresets, photoSchemaV2
}

/// Loads, caches and refreshes the AI remote config.
///
/// Order of precedence: last good fetched copy (cached on disk) → code defaults.
/// A fetch failure never degrades the current config.
actor AIRemoteConfigStore {
    private let remoteURL: URL?
    private let cacheURL: URL?
    private let session: URLSession
    private let maxAge: TimeInterval
    private(set) var current: AIRemoteConfig
    private var lastFetch: Date?

    init(remoteURL: URL?, cacheURL: URL?, session: URLSession = .shared, maxAge: TimeInterval = 3_600) {
        self.remoteURL = remoteURL
        self.cacheURL = cacheURL
        self.session = session
        self.maxAge = maxAge
        if let cacheURL, let data = try? Data(contentsOf: cacheURL), let cached = try? AIRemoteConfig.decode(from: data) {
            current = cached
        } else {
            current = .default
        }
    }

    /// Fetches a fresh copy if the cached one is older than `maxAge`.
    /// Returns the (possibly unchanged) current config.
    @discardableResult
    func refreshIfStale(force: Bool = false) async -> AIRemoteConfig {
        guard let remoteURL else { return current }
        if !force, let lastFetch, Date().timeIntervalSince(lastFetch) < maxAge { return current }
        lastFetch = Date()
        do {
            var request = URLRequest(url: remoteURL)
            request.timeoutInterval = 10
            request.cachePolicy = .reloadIgnoringLocalCacheData
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return current }
            let config = try AIRemoteConfig.decode(from: data)
            current = config
            if let cacheURL {
                try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? data.write(to: cacheURL, options: .atomic)
            }
        } catch {
            AILog.gateway.notice("Remote config refresh failed: \(String(describing: error), privacy: .public)")
        }
        return current
    }

    /// For tests, the debug screen and model-rotation drills.
    func override(_ config: AIRemoteConfig) {
        current = config
    }
}
