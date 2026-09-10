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
    }

    func applicationDidBecomeActive() {
        WatchSessionManager.shared.requestSnapshot()
    }
}
