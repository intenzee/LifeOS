import Foundation

/// The shared error model (FND-25). Each error carries a user-facing message,
/// a recovery suggestion and the log category it belongs to, so persistence
/// paths can stop swallowing errors with `try?`.
public struct AppError: Error, LocalizedError, Sendable, Equatable {
    public enum Code: String, Sendable {
        case storageRead
        case storageWrite
        case storageCorrupt
        case migrationFailed
        case migrationVerificationFailed
        case healthUnavailable
        case healthDenied
        case network
        case invalidInput
        case unknown
    }

    public let code: Code
    public let userMessage: String
    public let recoverySuggestion: String?
    public let category: Log.Category
    /// Developer detail. Never shown to users and logged as private.
    public let underlying: String?

    public init(_ code: Code, userMessage: String, recoverySuggestion: String? = nil,
                category: Log.Category, underlying: (any Error)? = nil) {
        self.code = code
        self.userMessage = userMessage
        self.recoverySuggestion = recoverySuggestion
        self.category = category
        self.underlying = underlying.map { String(describing: $0) }
    }

    public var errorDescription: String? { userMessage }

    public static func storageRead(_ error: any Error) -> AppError {
        AppError(.storageRead, userMessage: "Your data couldn't be loaded.",
                 recoverySuggestion: "Restart LifeOS. If this keeps happening, contact support.",
                 category: .data, underlying: error)
    }

    public static func storageWrite(_ error: any Error) -> AppError {
        AppError(.storageWrite, userMessage: "Your change couldn't be saved.",
                 recoverySuggestion: "Check that your iPhone has free storage, then try again.",
                 category: .data, underlying: error)
    }

    public static func storageCorrupt(_ detail: String) -> AppError {
        AppError(.storageCorrupt, userMessage: "Some saved data is damaged and was skipped.",
                 recoverySuggestion: "A backup was kept. Contact support to recover it.",
                 category: .data, underlying: StringError(detail))
    }
}

/// Wraps a plain message as an `Error`.
public struct StringError: Error, CustomStringConvertible, Sendable {
    public let description: String
    public init(_ description: String) { self.description = description }
}
