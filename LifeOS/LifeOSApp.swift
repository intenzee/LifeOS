//
//  LifeOSApp.swift
//  LifeOS
//
//  Created by Tanmay Roy on 12/22/25.
//

import SwiftUI

struct AppDependencies {
    let healthManager: HealthManager
    let streakManager: StreakManager
    let foodDatabase: FoodDatabaseManager
    let workoutDatabase: WorkoutDatabaseManager
    let persistence: PersistenceManager
    let notificationService: NotificationService
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
        self.apiClient = apiClient
        self.dailyMetricsRepository = dailyMetricsRepository ?? LocalDailyMetricsRepository(persistence: persistence)
        self.weeklyLogRepository = weeklyLogRepository ?? LocalWeeklyLogRepository(persistence: persistence)
    }
}

@main
struct LifeOSApp: App {
    private let dependencies = AppDependencies()

    init() {
        dependencies.notificationService.requestPermission()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(dependencies: dependencies)
        }
    }
}
