import Foundation
import UserNotifications

/// The app's single `UNUserNotificationCenter` delegate.
///
/// Phase 4 automations use it for "Log it", "Not now" and "Why am I seeing this?".
/// Other features (e.g. Platform AUTO-03) register a category prefix and a
/// handler instead of installing a second delegate; categories are merged,
/// never overwritten. Installed at launch so cold-start taps are not lost.
final class ExperienceNotifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ExperienceNotifications()

    static let logCategory = "lx.auto.log"
    static let infoCategory = "lx.auto.info"
    static let logAction = "lx.auto.action.log"
    static let notNowAction = "lx.auto.action.notNow"
    static let whyAction = "lx.auto.action.why"

    typealias Handler = @MainActor (UNNotificationResponse) async -> Void
    @MainActor private var handlers: [(prefix: String, handler: Handler)] = []

    /// Routes responses whose category identifier starts with `categoryPrefix` to `handler`,
    /// and merges `categories` into the registered set.
    @MainActor
    func register(categoryPrefix: String, categories: Set<UNNotificationCategory> = [], handler: @escaping Handler) {
        handlers.removeAll { $0.prefix == categoryPrefix }
        handlers.append((categoryPrefix, handler))
        if !categories.isEmpty { Self.mergeCategories(categories) }
    }

    /// Call once from `LifeOSApp.init`.
    func install() {
        let log = UNNotificationAction(identifier: Self.logAction, title: "Log it", options: [.foreground])
        let notNow = UNNotificationAction(identifier: Self.notNowAction, title: "Not now", options: [])
        let why = UNNotificationAction(identifier: Self.whyAction, title: "Why am I seeing this?", options: [.foreground])
        Self.mergeCategories([
            UNNotificationCategory(identifier: Self.logCategory, actions: [log, notNow, why], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.infoCategory, actions: [notNow, why], intentIdentifiers: []),
        ])
        UNUserNotificationCenter.current().delegate = self
    }

    /// Adds or replaces categories by identifier, keeping everyone else's.
    static func mergeCategories(_ new: Set<UNNotificationCategory>) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationCategories { existing in
            let ids = Set(new.map(\.identifier))
            center.setNotificationCategories(existing.filter { !ids.contains($0.identifier) }.union(new))
        }
    }

    static func category(for action: AutomationRule.Action) -> String {
        if case .suggestUsual = action { return logCategory }
        return infoCategory
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let category = response.notification.request.content.categoryIdentifier
        let registered: Handler? = await MainActor.run { handlers.first { category.hasPrefix($0.prefix) }?.handler }
        if let registered {
            await registered(response)
            return
        }

        let info = response.notification.request.content.userInfo
        let ruleID = info["ruleID"] as? String ?? ""
        let presetID = info["presetID"] as? String ?? ""
        let action = response.actionIdentifier
        await MainActor.run {
            let store = IntelligenceStore.shared
            switch action {
            case Self.notNowAction:
                return
            case Self.whyAction:
                store.pendingRoute = .automation(ruleID)
            case Self.logAction where !presetID.isEmpty:
                store.pendingRoute = .logPreset(presetID)
            default:
                let rule = store.rules.first { $0.id == ruleID }
                switch rule?.action {
                case .weeklyReview: store.pendingRoute = .weeklyReview
                case .eveningRecap: store.pendingRoute = .recap
                case .suggestUsual where !presetID.isEmpty: store.pendingRoute = .logPreset(presetID)
                default: store.pendingRoute = .today
                }
            }
        }
    }
}
