import SwiftUI

struct WatchRootView: View {
    @StateObject private var session = WatchSessionManager.shared

    var body: some View {
        TabView {
            WatchDashboardView(session: session)
                .tag(0)
            WatchWaterView(session: session)
                .tag(1)
            WatchWorkoutView(session: session)
                .tag(2)
            WatchTodosView(session: session)
                .tag(3)
        }
        .tabViewStyle(.verticalPage)
    }
}
