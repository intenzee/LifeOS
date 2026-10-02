import Foundation

/// A user's grant for one third-party cloud provider (F01 FR11, F11 §6).
nonisolated struct CloudConsent: Codable, Sendable, Hashable {
    nonisolated enum Source: String, Codable, Sendable {
        /// Explicit consent sheet with the data-use disclosure.
        case consentSheet
        /// The user saved a BYOK key on a screen that discloses where data goes.
        /// Covers `.personal` only — never `.health`.
        case keyEntry
        /// Users who saved a key before the gateway existed (Phase 0 migration).
        case legacyKeyEntry
    }

    /// Highest privacy class the user agreed to send to this provider.
    var maxPrivacy: PrivacyClass
    var grantedAt: Date
    var source: Source
}

nonisolated protocol ConsentStoring: Sendable {
    func consent(for provider: ProviderID) -> CloudConsent?
    func grant(_ consent: CloudConsent, for provider: ProviderID)
    func revoke(_ provider: ProviderID)
}

/// UserDefaults-backed consent store. Consent flags are not secrets; keys live
/// in the Keychain separately.
nonisolated final class UserDefaultsConsentStore: ConsentStoring, @unchecked Sendable {
    // UserDefaults is thread-safe; the class holds no other mutable state.
    private let defaults: UserDefaults
    private let prefix: String

    init(defaults: UserDefaults = .standard, prefix: String = "ai.consent.") {
        self.defaults = defaults
        self.prefix = prefix
    }

    func consent(for provider: ProviderID) -> CloudConsent? {
        guard let data = defaults.data(forKey: prefix + provider.rawValue) else { return nil }
        return try? JSONDecoder().decode(CloudConsent.self, from: data)
    }

    func grant(_ consent: CloudConsent, for provider: ProviderID) {
        guard let data = try? JSONEncoder().encode(consent) else { return }
        defaults.set(data, forKey: prefix + provider.rawValue)
    }

    func revoke(_ provider: ProviderID) {
        defaults.removeObject(forKey: prefix + provider.rawValue)
    }
}

/// In-memory store for tests and previews.
nonisolated final class InMemoryConsentStore: ConsentStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var grants: [ProviderID: CloudConsent]

    init(_ grants: [ProviderID: CloudConsent] = [:]) { self.grants = grants }

    func consent(for provider: ProviderID) -> CloudConsent? { lock.withLock { grants[provider] } }
    func grant(_ consent: CloudConsent, for provider: ProviderID) { lock.withLock { grants[provider] = consent } }
    func revoke(_ provider: ProviderID) { lock.withLock { grants[provider] = nil } }
}

/// Decides whether a request may go to a provider and what context it may carry.
nonisolated struct PrivacyGate: Sendable {
    let consents: any ConsentStoring

    /// Tasks whose data must never leave Apple's boundary, consent or not.
    static let neverThirdParty: Set<AITask> = [.memoryExtract, .memoryConsolidate]

    nonisolated enum Decision: Sendable, Equatable {
        case allow(contextCeiling: PrivacyClass)
        case deny(AIError)
    }

    func evaluate(task: AITask, privacy: PrivacyClass, provider: ProviderID) -> Decision {
        guard provider.isThirdPartyCloud else {
            // Device and Apple PCC are inside the privacy boundary.
            return .allow(contextCeiling: .health)
        }
        if Self.neverThirdParty.contains(task) {
            return .deny(.consentRequired(provider))
        }
        if privacy == .public {
            // No user data at all — still strip any context to be safe.
            return .allow(contextCeiling: .public)
        }
        guard let consent = consents.consent(for: provider) else {
            return .deny(.consentRequired(provider))
        }
        // Health data needs an explicit, sheet-based grant; key entry never implies it.
        let effectiveMax: PrivacyClass = consent.source == .consentSheet ? consent.maxPrivacy : min(consent.maxPrivacy, .personal)
        guard privacy <= effectiveMax else {
            return .deny(.consentRequired(provider))
        }
        return .allow(contextCeiling: effectiveMax)
    }

    /// Removes direct identifiers from text bound for a third-party cloud.
    static func redact(_ text: String) -> String {
        var out = text
        let patterns: [(Regex<Substring>, String)] = [
            (#/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/#, "[email]"),
            // International (+…), 10-digit mobile, or 3-3-4 formats only — loose
            // digit runs would eat food quantities like "100 200 300".
            (#/\+\d[\d\s\-]{8,}\d|\b\d{10}\b|\b\d{3}[\-\s]\d{3}[\-\s]\d{4}\b/#, "[phone]"),
        ]
        for (pattern, replacement) in patterns {
            out = out.replacing(pattern, with: replacement)
        }
        return out
    }
}
