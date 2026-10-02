import Foundation

// Core vocabulary of the AI Gateway (F01 §5.1).
//
// Everything here is `nonisolated` on purpose: the app target compiles with
// MainActor as its default isolation, but these values cross into the
// `AIGateway` actor and provider tasks, so they must not be main-actor bound.

/// Every AI job LifeOS can ask for. The routing table, prompt registry, cache
/// TTLs and telemetry are all keyed by task.
nonisolated enum AITask: String, Sendable, Codable, CaseIterable {
    case foodTextParse, mealPhotoAnalyze, mealPhotoRefine, nutritionLabelRead
    case memoryExtract, memoryConsolidate
    case assistantChat, briefingCompose, weeklyReview, budgetExplain
    case nudgeCompose, presetSuggestName
}

/// Data-sensitivity class carried by every request (F11 §6).
///
/// - `public`: no user data at all (e.g. naming a preset from food names only).
/// - `personal`: user content that is not health data (a food sentence, a meal photo).
/// - `health`: anything derived from HealthKit, body metrics, memory or history.
nonisolated enum PrivacyClass: String, Sendable, Codable, Comparable {
    case `public`, personal, health

    private var rank: Int {
        switch self {
        case .public: 0
        case .personal: 1
        case .health: 2
        }
    }

    static func < (lhs: PrivacyClass, rhs: PrivacyClass) -> Bool { lhs.rank < rhs.rank }
}

/// Engines the gateway can route to. Tiers follow the master plan §3.
nonisolated enum ProviderID: String, Sendable, Codable, CaseIterable, Hashable {
    case appleOnDevice      // T1
    case applePCC           // T2
    case geminiBYOK         // T3
    case groqBYOK           // T3
    case visionLegacy       // T4
    case deterministic      // T0

    var tier: AITier {
        switch self {
        case .deterministic: .t0
        case .appleOnDevice: .t1
        case .applePCC: .t2
        case .geminiBYOK, .groqBYOK: .t3
        case .visionLegacy: .t4
        }
    }

    /// Whether content leaves Apple's privacy boundary (device or PCC).
    var isThirdPartyCloud: Bool { tier == .t3 }

    /// Short label for provenance badges and diagnostics.
    var displayName: String {
        switch self {
        case .appleOnDevice: "On-device"
        case .applePCC: "Apple Cloud"
        case .geminiBYOK: "Your key · Gemini"
        case .groqBYOK: "Your key · Groq"
        case .visionLegacy: "On-device (basic)"
        case .deterministic: "Rules"
        }
    }
}

nonisolated enum AITier: String, Sendable, Codable, Comparable {
    case t0, t1, t2, t3, t4
    static func < (lhs: AITier, rhs: AITier) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// What a provider can do. Used by the router to skip incapable providers.
nonisolated enum AICapability: String, Sendable, Codable, Hashable {
    case text, vision, tools, streaming, longContext
}

// MARK: - Input

/// An image handed to the gateway. Stored as encoded bytes so it is trivially
/// `Sendable` and can be uploaded as-is; on-device providers decode it lazily.
nonisolated struct AIImage: Sendable, Hashable {
    var data: Data
    var mimeType: String
    var pixelWidth: Int?
    var pixelHeight: Int?

    init(jpegData: Data, pixelWidth: Int? = nil, pixelHeight: Int? = nil) {
        self.data = jpegData
        self.mimeType = "image/jpeg"
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }

    var dataURL: String { "data:\(mimeType);base64," + data.base64EncodedString() }
}

nonisolated enum AIInput: Sendable, Hashable {
    case text(String)
    case image(AIImage, caption: String? = nil)
    case multimodal(text: String, images: [AIImage])

    var text: String? {
        switch self {
        case .text(let text): text
        case .image(_, let caption): caption
        case .multimodal(let text, _): text
        }
    }

    var images: [AIImage] {
        switch self {
        case .text: []
        case .image(let image, _): [image]
        case .multimodal(_, let images): images
        }
    }

    var requiredCapabilities: Set<AICapability> {
        images.isEmpty ? [.text] : [.text, .vision]
    }
}

// MARK: - Context

/// The compact, privacy-filtered bundle of user state sent with a request.
///
/// Phase 0 ships the minimal shape; the Context Engine (F05) builds these with
/// token budgets. Sections are rendered as quoted data, never as instructions.
nonisolated struct ContextPacket: Sendable, Hashable, Codable {
    nonisolated struct Section: Sendable, Hashable, Codable {
        var title: String
        var body: String
        var privacy: PrivacyClass
    }

    var sections: [Section]

    init(sections: [Section] = []) { self.sections = sections }

    var isEmpty: Bool { sections.allSatisfy { $0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }

    /// Highest sensitivity present in the packet — the request is at least this sensitive.
    var privacy: PrivacyClass { sections.map(\.privacy).max() ?? .public }

    /// Drops sections above `ceiling` (used when routing to a less trusted tier).
    func filtered(maxPrivacy ceiling: PrivacyClass) -> ContextPacket {
        ContextPacket(sections: sections.filter { $0.privacy <= ceiling })
    }

    func rendered() -> String {
        sections
            .filter { !$0.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.body)
            .joined(separator: "\n\n")
    }
}

// MARK: - Request / Result

/// A typed request (F01 FR1). `Output` declares its own schema via `AIOutput`.
nonisolated struct AIRequest<Output: AIOutput>: Sendable {
    var task: AITask
    var prompt: AIPrompt
    var input: AIInput
    var context: ContextPacket?
    var privacy: PrivacyClass
    var latencyBudget: Duration
    /// Allow a cached answer for identical input (FR9). Chat-like tasks ignore this.
    var cachePolicy: AICachePolicy
    var generation: AIGenerationOptions
    /// A BYOK key typed for this request but not saved yet (the legacy scan
    /// screen lets users try a key before it is stored). Never cached or logged.
    var credentialOverrides: [ProviderID: String]

    init(task: AITask,
         prompt: AIPrompt,
         input: AIInput,
         context: ContextPacket? = nil,
         privacy: PrivacyClass,
         latencyBudget: Duration = .seconds(8),
         cachePolicy: AICachePolicy = .useTaskDefault,
         generation: AIGenerationOptions = .init(),
         credentialOverrides: [ProviderID: String] = [:]) {
        self.task = task
        self.prompt = prompt
        self.input = input
        self.context = context
        self.privacy = privacy
        self.latencyBudget = latencyBudget
        self.cachePolicy = cachePolicy
        self.generation = generation
        self.credentialOverrides = credentialOverrides.filter {
            !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// The effective privacy class: never lower than what the context carries.
    var effectivePrivacy: PrivacyClass { max(privacy, context?.privacy ?? .public) }
}

nonisolated enum AICachePolicy: Sendable, Hashable {
    case useTaskDefault
    case bypass
}

nonisolated struct AIGenerationOptions: Sendable, Hashable, Codable {
    var temperature: Double?
    var maxOutputTokens: Int?

    init(temperature: Double? = nil, maxOutputTokens: Int? = nil) {
        self.temperature = temperature
        self.maxOutputTokens = maxOutputTokens
    }
}

/// A failed attempt recorded on the way to a result (for badges and diagnostics).
nonisolated struct AIAttempt: Sendable, Hashable, Codable {
    var provider: ProviderID
    var error: AIError
    var latency: Duration
}

nonisolated struct AIResult<Output: Sendable>: Sendable {
    var output: Output
    var provider: ProviderID
    var model: String
    var promptVersion: String
    var latency: Duration
    var fromCache: Bool
    /// What failed before success, in order. Empty when the first choice answered.
    var degradedFrom: [AIAttempt]

    var didDegrade: Bool { !degradedFrom.isEmpty }
}

// MARK: - Availability

nonisolated enum AIUnavailableReason: String, Sendable, Codable, Hashable {
    case osTooOld                    // e.g. iOS < 26 for Foundation Models
    case deviceNotEligible           // no Apple Intelligence hardware
    case appleIntelligenceNotEnabled // user turned it off
    case modelNotReady               // still downloading
    case missingCredential           // BYOK provider without a key
    case consentRequired             // third-party cloud not consented for this privacy class
    case disabledByConfig            // remote config / feature flag / debug override
    case circuitOpen                 // recent repeated failures
    case quotaExhausted              // local token bucket empty
    case offline
    case unsupportedInput            // e.g. image sent to a text-only provider
    case notImplemented              // provider has no handler for this task
}

nonisolated enum AIAvailability: Sendable, Hashable, Codable {
    case available
    case unavailable(AIUnavailableReason)

    var isAvailable: Bool { if case .available = self { true } else { false } }
}

/// Per-task availability summary for UI gating and badges (C7 `availability(for:)`).
nonisolated struct AITaskAvailability: Sendable, Hashable {
    var task: AITask
    /// Status of each provider in the task's chain, in routing order.
    var chain: [(provider: ProviderID, availability: AIAvailability)]
    /// First provider that would answer right now, if any.
    var primary: ProviderID? { chain.first { $0.availability.isAvailable }?.provider }
    var isAvailable: Bool { primary != nil }

    static func == (lhs: AITaskAvailability, rhs: AITaskAvailability) -> Bool {
        lhs.task == rhs.task
            && lhs.chain.map(\.provider) == rhs.chain.map(\.provider)
            && lhs.chain.map(\.availability) == rhs.chain.map(\.availability)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(task)
        for entry in chain {
            hasher.combine(entry.provider)
            hasher.combine(entry.availability)
        }
    }
}
