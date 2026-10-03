//
//  LifeOSApp.swift
//  LifeOS
//
//  Created by Tanmay Roy on 12/22/25.
//

import SwiftUI
import LifeOSHealth

struct AppDependencies {
    let healthManager: HealthManager
    let streakManager: StreakManager
    let foodDatabase: FoodDatabaseManager
    let workoutDatabase: WorkoutDatabaseManager
    let persistence: PersistenceManager
    let notificationService: NotificationService
    let watchConnectivity: WatchConnectivityManager
    let apiClient: any APIClient
    let dailyMetricsRepository: any DailyMetricsRepository
    let weeklyLogRepository: any WeeklyLogRepository

    init(
        healthManager: HealthManager = HealthManager(),
        streakManager: StreakManager = .shared,
        foodDatabase: FoodDatabaseManager = .shared,
        workoutDatabase: WorkoutDatabaseManager = .shared,
        persistence: PersistenceManager = .shared,
        notificationService: NotificationService = .shared,
        watchConnectivity: WatchConnectivityManager = .shared,
        apiClient: any APIClient = URLSessionAPIClient(),
        dailyMetricsRepository: (any DailyMetricsRepository)? = nil,
        weeklyLogRepository: (any WeeklyLogRepository)? = nil
    ) {
        self.healthManager = healthManager
        self.streakManager = streakManager
        self.foodDatabase = foodDatabase
        self.workoutDatabase = workoutDatabase
        self.persistence = persistence
        self.notificationService = notificationService
        self.watchConnectivity = watchConnectivity
        self.apiClient = apiClient
        self.dailyMetricsRepository = dailyMetricsRepository ?? LocalDailyMetricsRepository(persistence: persistence)
        self.weeklyLogRepository = weeklyLogRepository ?? LocalWeeklyLogRepository(persistence: persistence)
    }
}

/// Starts HealthKit observers in `didFinishLaunching`, before any UI: a
/// background-delivery wake launches the app without a scene (WCH-04).
final class LifeOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("UITEST_MEALRESULT") { return true }
        #endif
        MainActor.assumeIsolated { HealthSync.shared.start() }
        return true
    }
}

@main
struct LifeOSApp: App {
    @UIApplicationDelegateAdaptor(LifeOSAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    private let dependencies = AppDependencies()
    @StateObject private var store = LocalStore.shared

    init() {
        #if DEBUG
        // Keep UI screenshot harness free of system permission prompts.
        if ProcessInfo.processInfo.arguments.contains("UITEST_MEALRESULT") { return }
        #endif
        dependencies.notificationService.requestPermission()
        dependencies.watchConnectivity.activate()
        AIServices.shared.start()
        // UI/UX Phase 4: actionable automation notifications (set before launch finishes).
        ExperienceNotifications.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("UITEST_MEALRESULT") {
                    MealResultHarness()
                } else if ProcessInfo.processInfo.arguments.contains("LX_DIRECTION_LAB") {
                    // On-device design verification (Phase 1 spike, Phase 2 gallery).
                    DirectionLabView()
                } else {
                    LaunchGate(store: store, dependencies: dependencies)
                }
                #else
                LaunchGate(store: store, dependencies: dependencies)
                #endif
            }
            // The design direction chosen in Settings → Direction Lab.
            .modifier(LXDirectionRoot())
        }
        .onChange(of: scenePhase) { _, phase in
            // Foreground trigger (WCH-05). Background delivery is best-effort.
            if phase == .active, store.phase == .ready { HealthSync.shared.syncInBackground(.foreground) }
        }
    }
}

#if DEBUG
/// Launch-argument-gated harness so the meal result screen can be rendered in
/// isolation (with the keyboard raised) for UI verification. No production impact.
private struct MealResultHarness: View {
    @State private var presented = true
    var body: some View {
        MealResultView(
            analysis: MealAnalysis(
                name: "Fried Rice",
                calories: 520, protein: 14, carbs: 78, fat: 16,
                servingSize: "1 plate",
                source: .groq,
                components: [
                    .init(name: "Rice", calories: 300, protein: 6, carbs: 65, fat: 2),
                    .init(name: "Vegetables", calories: 120, protein: 4, carbs: 12, fat: 6)
                ]
            ),
            mealType: .lunch,
            isPresented: $presented,
            onRefine: { _ in },
            onLog: { _ in },
            autoFocusFeedback: true
        )
    }
}
#endif
