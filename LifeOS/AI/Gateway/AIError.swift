import Foundation

/// Gateway-wide error taxonomy (F01 FR6), generalised from `MealScanError`.
///
/// Two questions decide what happens next:
///  - `isRecoverable` → the gateway silently moves on to the next provider.
///  - `isUserActionable` → the UI should tell the user (bad key, rate limit),
///    but the gateway *still* tries non-cloud fallbacks first.
nonisolated enum AIError: Error, Sendable, Hashable, Codable {
    case unavailable(AIUnavailableReason)
    case consentRequired(ProviderID)
    case authFailed(ProviderID)
    case rateLimited(ProviderID)
    case quotaExhausted(ProviderID)
    case circuitOpen(ProviderID)
    case contextOverflow
    case guardrail
    case refusal
    case unsupportedLocale
    case unsupportedInput
    case modelRetired(String)
    case noModelAvailable
    case invalidOutput(String)
    case network(String)
    case server(Int)
    case timeout
    case cancelled
    /// Every provider in the chain failed. Carries the attempts for diagnostics.
    case exhausted([AIAttempt])

    var isRecoverable: Bool {
        switch self {
        case .cancelled:
            return false
        case .exhausted:
            return false
        // Guardrail hits are only worth retrying elsewhere for benign tasks;
        // the gateway checks the task before treating them as recoverable.
        default:
            return true
        }
    }

    var isUserActionable: Bool {
        switch self {
        case .authFailed, .rateLimited, .consentRequired, .unavailable(.missingCredential):
            return true
        case .exhausted(let attempts):
            return attempts.contains { $0.error.isUserActionable }
        default:
            return false
        }
    }

    /// The most informative user-actionable error in an exhausted chain, if any.
    var userActionableCause: AIError? {
        switch self {
        case .exhausted(let attempts):
            return attempts.map(\.error).first { $0.isUserActionable }
        default:
            return isUserActionable ? self : nil
        }
    }

    var userMessage: String {
        switch self {
        case .unavailable(let reason):
            switch reason {
            case .osTooOld, .deviceNotEligible:
                return "Smart features need a newer iPhone. You can still log manually."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence in Settings to use smart logging."
            case .modelNotReady:
                return "Apple Intelligence is getting ready. Try again in a few minutes."
            case .missingCredential:
                return "Add your free API key to use this feature."
            case .consentRequired:
                return "Allow cloud processing to use this feature."
            case .offline:
                return "You're offline. Try again when connected."
            default:
                return "This AI feature is unavailable right now."
            }
        case .consentRequired(let provider):
            return "Allow \(provider.displayName) to process this request first."
        case .authFailed(let provider):
            return "Your \(provider.displayName) key was rejected. Check it in settings."
        case .rateLimited(let provider), .quotaExhausted(let provider):
            return "\(provider.displayName) limit reached. Wait a moment and try again."
        case .circuitOpen:
            return "AI is having trouble right now. Try again shortly."
        case .contextOverflow:
            return "That was too long for the on-device model. Try something shorter."
        case .guardrail, .refusal:
            return "That request couldn't be handled."
        case .unsupportedLocale:
            return "That language isn't supported yet."
        case .unsupportedInput:
            return "That input type isn't supported here."
        case .modelRetired, .noModelAvailable:
            return "AI is temporarily unavailable."
        case .invalidOutput:
            return "Couldn't read the AI answer."
        case .network:
            return "Network issue. Check your connection and try again."
        case .server:
            return "The AI service had a hiccup. Try again."
        case .timeout:
            return "That took too long. Try again."
        case .cancelled:
            return "Cancelled."
        case .exhausted:
            return userActionableCause?.userMessage ?? "Couldn't get an AI answer. You can still log manually."
        }
    }

    /// Stable short code for telemetry (never contains user content).
    var code: String {
        switch self {
        case .unavailable(let reason): "unavailable.\(reason.rawValue)"
        case .consentRequired: "consentRequired"
        case .authFailed: "authFailed"
        case .rateLimited: "rateLimited"
        case .quotaExhausted: "quotaExhausted"
        case .circuitOpen: "circuitOpen"
        case .contextOverflow: "contextOverflow"
        case .guardrail: "guardrail"
        case .refusal: "refusal"
        case .unsupportedLocale: "unsupportedLocale"
        case .unsupportedInput: "unsupportedInput"
        case .modelRetired: "modelRetired"
        case .noModelAvailable: "noModelAvailable"
        case .invalidOutput: "invalidOutput"
        case .network: "network"
        case .server(let status): "server.\(status)"
        case .timeout: "timeout"
        case .cancelled: "cancelled"
        case .exhausted: "exhausted"
        }
    }
}
