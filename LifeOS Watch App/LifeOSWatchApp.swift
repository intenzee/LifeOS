import SwiftUI

@main
struct LifeOSWatch_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchRootView()
        }
    }
}

/// Ensures the WatchConnectivity session is activated as soon as the app launches
/// (not only when a view that references it appears).
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchSessionManager.shared.activate()
        Task { @MainActor in ComplicationBridge.shared.start() }
    }

    func applicationDidBecomeActive() {
        WatchSessionManager.shared.requestSnapshot()
    }

    /// watchOS relaunches the app to resume a workout after a crash (WCH-12).
    func handleActiveWorkoutRecovery() {
        Task { @MainActor in await StrengthWorkoutSession.shared.recover() }
    }
}
