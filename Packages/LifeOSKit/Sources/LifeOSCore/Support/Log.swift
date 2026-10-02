import os

/// Unified logging (FND-20). Subsystem `app.lifeos`, one category per area.
///
/// Mark user values private: `Log.food.info("Logged \(name, privacy: .private)")`.
/// `print` is banned by SwiftLint.
public enum Log {
    public static let subsystem = "app.lifeos"

    public static let health = Logger(subsystem: subsystem, category: Category.health.rawValue)
    public static let food = Logger(subsystem: subsystem, category: Category.food.rawValue)
    public static let ai = Logger(subsystem: subsystem, category: Category.ai.rawValue)
    public static let watch = Logger(subsystem: subsystem, category: Category.watch.rawValue)
    public static let data = Logger(subsystem: subsystem, category: Category.data.rawValue)
    public static let automation = Logger(subsystem: subsystem, category: Category.automation.rawValue)
    public static let ui = Logger(subsystem: subsystem, category: Category.ui.rawValue)

    public enum Category: String, Sendable, CaseIterable {
        case health, food, ai, watch, data, automation, ui
    }

    public static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}
