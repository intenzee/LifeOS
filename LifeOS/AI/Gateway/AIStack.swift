import Foundation

/// Assembles the standard gateway: every tier, wired to shared config, quota,
/// cache, consent and telemetry. The app, the `ai-eval` CLI and integration
/// tests all build their gateway here so they exercise the same wiring.
nonisolated enum AIStack {

    nonisolated struct Options: Sendable {
        var remoteConfigURL: URL?
        /// Directory for the response cache and cached remote config. nil = memory only.
        var storageDirectory: URL?
        var credentials: any AICredentialProviding
        var consents: any ConsentStoring
        /// Extra/replacement providers (e.g. the app's Vision-legacy handler).
        var additionalProviders: [any AIProvider] = []
        var session: URLSession = RESTTransport.defaultSession()

        init(remoteConfigURL: URL? = nil, storageDirectory: URL? = nil,
             credentials: any AICredentialProviding, consents: any ConsentStoring,
             additionalProviders: [any AIProvider] = []) {
            self.remoteConfigURL = remoteConfigURL
            self.storageDirectory = storageDirectory
            self.credentials = credentials
            self.consents = consents
            self.additionalProviders = additionalProviders
        }
    }

    static func makeGateway(_ options: Options) -> AIGateway {
        let configStore = AIRemoteConfigStore(
            remoteURL: options.remoteConfigURL,
            cacheURL: options.storageDirectory?.appendingPathComponent("ai-remote-config.json"))

        let groq = GroqBYOKProvider(credentials: options.credentials, models: { vision in
            let config = await configStore.current
            return vision ? config.groqVisionModels : config.groqTextModels
        }, session: options.session)
        let gemini = GeminiBYOKProvider(credentials: options.credentials, models: {
            await configStore.current.geminiModels
        }, session: options.session)

        var providers: [any AIProvider] = [
            deterministicProvider(),
            AppleOnDeviceProvider(),
            ApplePCCProvider(),
            gemini,
            groq,
        ]
        providers.append(contentsOf: options.additionalProviders)

        return AIGateway(
            providers: providers,
            configStore: configStore,
            cache: AIResponseCache(fileURL: options.storageDirectory?.appendingPathComponent("ai-response-cache.json")),
            consents: options.consents)
    }

    /// T0: rules and templates. Grows a handler per task as features land.
    static func deterministicProvider() -> LocalHandlerProvider {
        LocalHandlerProvider(id: .deterministic, handlers: [
            .foodTextParse: { call in
                let text = call.input.text ?? ""
                let parsed = DeterministicFoodParser.parse(text)
                let data = try JSONEncoder().encode(parsed)
                return String(decoding: data, as: UTF8.self)
            },
        ])
    }
}
