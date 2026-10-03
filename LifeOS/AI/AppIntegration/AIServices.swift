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
    /// Food presets (F03). AI-owned file store until FoodPreset moves into LifeOSData (C1).
    let presets: FilePresetRepository

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

        presets = FilePresetRepository(url: storage?.appendingPathComponent("presets.json"))
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
        AIAssistantBridge.shared.startObservingWorkouts()
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

// MARK: - Food logging (Phase 1)

extension AIServices {
    /// Text/voice/preset logging. The user's custom, favourite and recent foods
    /// are read fresh each time so their own numbers win over the catalog.
    var foodLogger: SmartFoodLogger {
        var logger = SmartFoodLogger(gateway: gateway, presets: presets, userFoods: {
            await MainActor.run { Self.userFoods() + AIMemoryBridge.shared.dishFoods }
        })
        // Phase 2: learned meal windows (F02/F05) and the user's own portion sizes (F04).
        logger.mealWindows = {
            await MainActor.run { MealWindows.learn(Self.recentMeals(days: 28).map { ($0.meal, $0.date) }) }
        }
        logger.portionHints = { await MainActor.run { AIMemoryBridge.shared.portionHints } }
        return logger
    }

    @MainActor
    static func userFoods() -> [UserFood] {
        let db = FoodDatabaseManager.shared
        func map(_ foods: [FoodItem], _ kind: UserFood.Kind) -> [UserFood] {
            foods.map { UserFood(name: $0.name, macros: Macros(kcal: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat),
                                 servingDescription: $0.servingSize, kind: kind) }
        }
        // Custom foods are the user's own numbers; recents only count when they
        // were entered manually (AI-logged recents would just echo the catalog).
        let recents = db.recentFoods.filter { $0.source == nil || $0.source == .manual || $0.source == .barcode }
        return map(db.customFoods, .custom) + map(db.favoriteFoods, .favorite) + map(recents, .recent)
    }

    /// Last 30 days of the food log, grouped by meal, for the routine miner.
    @MainActor
    static func recentMeals(days: Int = 30, now: Date = Date()) -> [LoggedMeal] {
        let calendar = Calendar.current
        let db = FoodDatabaseManager.shared
        return (0..<days).flatMap { offset -> [LoggedMeal] in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: now) else { return [] }
            let log = db.dailyLog(for: day)
            let foods = log.breakfast + log.lunch + log.dinner + log.snacks
            return Dictionary(grouping: foods, by: \.mealType).map { meal, items in
                LoggedMeal(date: items.map(\.timestamp).min() ?? day, meal: ParsedMeal.MealSlot(meal),
                           items: items.map { .init(name: $0.name,
                                                    macros: Macros(kcal: $0.calories, protein: $0.protein, carbs: $0.carbs, fat: $0.fat),
                                                    servingDescription: $0.servingSize) })
            }
        }
    }

    /// Food names for speech recognition hints: presets, the user's foods, catalog.
    @MainActor
    func speechVocabulary() async -> [String] {
        let presetNames = await presets.all().map(\.name)
        let mine = Self.userFoods().map(\.name)
        return Array(Set(presetNames + mine + FoodCatalog.all.map(\.name))).sorted()
    }
}

extension ParsedMeal.MealSlot {
    init(_ meal: MealType) {
        switch meal {
        case .breakfast: self = .breakfast
        case .lunch: self = .lunch
        case .dinner: self = .dinner
        case .snacks: self = .snacks
        }
    }

    var mealType: MealType? {
        switch self {
        case .breakfast: .breakfast
        case .lunch: .lunch
        case .dinner: .dinner
        case .snacks: .snacks
        case .unknown: nil
        }
    }
}
