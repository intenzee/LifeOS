import Foundation

/// App-wide owner of the AI Gateway (iOS-only glue; excluded from the SwiftPM
/// harness because it touches UIKit-backed app types).
///
/// Product code reaches AI only through `AIServices.shared.gateway`.
final class AIServices {
    static let shared = AIServices()

    let gateway: AIGateway
    let consents: UserDefaultsConsentStore
    let credentials: KeychainCredentialStore

    /// Info.plist key holding the remote-config URL (contract C10). Absent →
    /// code defaults only, which is the correct Phase 0 behaviour.
    static let remoteConfigInfoKey = "LifeOSAIRemoteConfigURL"

    private init() {
        consents = UserDefaultsConsentStore()
        credentials = KeychainCredentialStore()

        let storage = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("AI", isDirectory: true)
        let configURL = (Bundle.main.object(forInfoDictionaryKey: Self.remoteConfigInfoKey) as? String)
            .flatMap(URL.init(string:))

        gateway = AIStack.makeGateway(.init(
            remoteConfigURL: configURL,
            storageDirectory: storage,
            credentials: credentials,
            consents: consents,
            additionalProviders: [VisionLegacyMealProvider.make()]))

        migrateLegacyKeyConsent()
    }

    /// Call on launch / foreground: refresh remote config (cached 1 h).
    func start() {
        Task { await gateway.refreshConfig() }
    }

    // MARK: - Consent

    /// Users who saved a Groq key before the gateway existed already chose to
    /// send meal photos to Groq; keep that working for `.personal` data only.
    private func migrateLegacyKeyConsent() {
        for provider in [ProviderID.groqBYOK, .geminiBYOK]
        where credentials.apiKey(for: provider) != nil && consents.consent(for: provider) == nil {
            consents.grant(CloudConsent(maxPrivacy: .personal, grantedAt: Date(), source: .legacyKeyEntry), for: provider)
        }
    }

    /// The user entered a key on a screen that discloses where data goes.
    /// Grants `.personal` only — `.health` always needs the explicit consent sheet.
    func recordKeyEntryConsent(for provider: ProviderID) {
        guard consents.consent(for: provider) == nil else { return }
        consents.grant(CloudConsent(maxPrivacy: .personal, grantedAt: Date(), source: .keyEntry), for: provider)
        Task { await gateway.consentDidChange() }
    }

    func revokeCloudConsent(for provider: ProviderID) {
        consents.revoke(provider)
        Task { await gateway.consentDidChange() }
    }
}
