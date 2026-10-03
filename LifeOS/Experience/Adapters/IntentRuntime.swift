import Foundation

/// Phase 5 §5: the data side of Siri, Shortcuts and (later) widget intents.
///
/// App Intents run in the app's process, sometimes before any UI exists
/// (Siri launches LifeOS in the background). This hands them the live
/// `ExperienceStore` when the UI is up, so the screen updates at once, or
/// boots the store and builds one when it isn't.
@MainActor
enum IntentRuntime {
    private static weak var live: ExperienceStore?
    private static var headless: ExperienceStore?

    /// Called by `ExperienceRootView` on appear.
    static func attach(_ store: ExperienceStore) {
        live = store
        headless = nil
    }

    /// A store looking at today, with fresh data.
    static func store() async -> ExperienceStore {
        if LocalStore.shared.phase != .ready { await LocalStore.shared.bootstrap() }
        let store: ExperienceStore
        if let live {
            store = live
        } else if let headless {
            store = headless
        } else {
            let made = ExperienceStore(dependencies: AppDependencies())
            headless = made
            store = made
        }
        if !store.isToday { store.select(day: Date()) }
        store.reload()
        IntelligenceStore.shared.attach(store)
        return store
    }

    /// Phrases for Siri: "640 kcal left, 222 earned today."
    static func remainingSentence(_ b: ExperienceBudget) -> String {
        let earned = b.earned >= 1 ? ", \(Fmt.kcal(b.earned)) kcal earned today" : ""
        if b.isOver { return "You're \(Fmt.kcal(-b.remaining)) kcal over today\(earned). Tomorrow resets." }
        return "\(Fmt.kcal(b.remaining)) kcal left\(earned)."
    }
}
