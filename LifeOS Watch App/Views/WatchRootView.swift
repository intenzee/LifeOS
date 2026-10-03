import SwiftUI

struct WatchRootView: View {
    @StateObject private var session = WatchSessionManager.shared
    @State private var page = Page.today

    /// Pages a complication can open (WCH-15): `lifeos://watch/workout` and
    /// `lifeos://watch/water` open those pages; any other link opens Today.
    enum Page: Hashable {
        case today, water, workout, rest, weight, todos
    }

    var body: some View {
        TabView(selection: $page) {
            WatchDashboardView(session: session)
                .tag(Page.today)
            WatchWaterView(session: session)
                .tag(Page.water)
            WatchWorkoutView(session: session)
                .tag(Page.workout)
            NavigationStack { WatchRestTimerView() }
                .tag(Page.rest)
            NavigationStack { WatchWeightView(session: session) }
                .tag(Page.weight)
            WatchTodosView(session: session)
                .tag(Page.todos)
        }
        .tabViewStyle(.verticalPage)
        .onOpenURL { url in
            guard url.host == "watch" else { page = .today; return }
            switch url.path {
            case "/workout": page = .workout
            case "/water": page = .water
            default: page = .today
            }
        }
    }
}
