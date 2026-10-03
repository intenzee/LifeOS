import AppIntents
import Foundation

// Phase 5 §3/§4: the buttons on widgets, controls and the Live Activity.
//
// They conform to `LiveActivityIntent`, which makes the system run `perform()`
// in the APP's process (launched in the background if needed), so they write
// to the real store. In the widget extension the body is compiled out.

struct AddWaterWidgetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Add a glass of water"
    static let description = IntentDescription("Adds one glass of water to today.")
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let store = await IntentRuntime.store()
        store.addWater(1)
        #endif
        return .result()
    }
}

struct LogPresetWidgetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log a usual meal from a widget"
    static let isDiscoverable = false

    @Parameter(title: "Meal ID") var presetID: String

    init() {}
    init(presetID: String) { self.presetID = presetID }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        let store = await IntentRuntime.store()
        if store.logPreset(id: presetID) != nil { WidgetBridge.markLogged(presetID) }
        #endif
        return .result()
    }
}

struct LogSetActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Log a set"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        await GymLiveSession.shared.logSet()
        #endif
        return .result()
    }
}

struct SkipRestActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Skip rest"
    static let isDiscoverable = false

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        GymLiveSession.shared.skipRest()
        #endif
        return .result()
    }
}

/// Control Center "Capture": opens LifeOS on the Capture sheet (listening when speech is allowed).
struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "Capture a meal"
    static let description = IntentDescription("Opens LifeOS ready to log what you ate.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        IntelligenceStore.shared.pendingRoute = .capture
        #endif
        return .result()
    }
}
