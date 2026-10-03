import Foundation
import Combine
import HealthKit
import LifeOSData
import LifeOSHealth

extension Notification.Name {
    /// Posted on the main actor when Apple Health delivers a workout the app hasn't
    /// seen before. `object` is the `WorkoutSession` (WCH-10).
    static let healthWorkoutSynced = Notification.Name("healthWorkoutSynced")
}

/// The app's view of Phase 1 Health & Energy (doc 02, doc 03).
///
/// - Owns `HealthIngestionService` (Apple Health → store) and `BudgetService`
///   (store → `EnergyDay.budgetKcal`).
/// - Keeps every `EnergyDay` in memory, so views read budgets synchronously.
///   `budget(on:)` is **the** daily budget for Home, the Watch, streaks and the
///   new Experience screens (CAL-03).
/// - Publishes today's breakdown, workouts and the Health connection state.
@MainActor
final class HealthSync: ObservableObject {
    static let shared = HealthSync()

    enum HealthStatus: Equatable {
        /// No Health on this device (iPad).
        case unavailable
        /// The permission sheet hasn't been answered.
        case notDetermined
        case connected
        /// Access was requested but no energy has arrived for 7 days (doc 02 §3.6).
        case likelyDenied
    }

    @Published private(set) var energyByDay: [DayKey: EnergyDay] = [:]
    @Published private(set) var todayBreakdown: BudgetBreakdown?
    @Published private(set) var todaySessions: [WorkoutSession] = []
    @Published private(set) var settings = EnergySettings()
    @Published private(set) var status: HealthStatus = .notDetermined
    @Published private(set) var lastSync: Date?
    @Published private(set) var isSyncing = false
    /// "Save food & water to Apple Health" (WCH-08).
    @Published private(set) var savesToHealth = false
    /// What the user let LifeOS write in Health.
    @Published private(set) var writableKinds: Set<HealthWriteKind> = []

    let client: HKHealthStoreClient
    private var database: LifeOSDatabase { LocalStore.shared.database }
    private var ingestion: HealthIngestionService?
    private var budgets: BudgetService?
    private var writeBack: HealthWriteBackService?
    private var listenTask: Task<Void, Never>?
    private var started = false
    private var allowanceCheckedOn: DayKey?
    private var profileWeightKg: Double = 70

    init(client: HKHealthStoreClient = HKHealthStoreClient()) {
        self.client = client
        status = client.isAvailable ? .notDetermined : .unavailable
    }

    private var ingestionEnabled: Bool { FeatureFlags.shared.isEnabled(.healthKitIngestion) }

    // MARK: Launch

    /// Seeds the cache from the launch snapshot (called by `LocalStore`).
    func load(from snapshot: DataSnapshot) {
        energyByDay = Dictionary(snapshot.energy.map { ($0.dayKey, $0) }, uniquingKeysWith: { $1 })
        todaySessions = snapshot.workoutSessions.filter { $0.dayKey == .today() }.sorted { $0.start < $1.start }
        settings = snapshot.energySettings
        profileWeightKg = snapshot.profile?.currentWeightKg ?? profileWeightKg
    }

    /// Starts the services and registers HealthKit observers. Call from
    /// `application(_:didFinishLaunchingWithOptions:)`: background delivery
    /// relaunches the app without UI, and observers must exist before HealthKit
    /// hands over the update (WCH-04).
    func start() {
        guard !started else { return }
        started = true
        Task {
            await LocalStore.shared.bootstrap()
            guard LocalStore.shared.phase == .ready else { return }
            await migrateLegacySettingsIfNeeded()

            let budgets = BudgetService(database: database)
            self.budgets = budgets
            await budgets.start()
            listen()
            await budgets.invalidateOpenDays()
            await startWriteBack()

            if ingestionEnabled, client.isAvailable {
                let ingestion = HealthIngestionService(client: client, database: database)
                self.ingestion = ingestion
                await client.startObserving { [weak self] _ in
                    await self?.sync(.observer)
                }
            }
            await refreshStatus()
            await sync(.launch)
        }
    }

    // MARK: Triggers (WCH-05)

    /// Syncs Health and refreshes today's budget. Concurrent calls coalesce in
    /// the ingestion service.
    func sync(_ trigger: SyncTrigger) async {
        await budgets?.invalidateOpenDays()
        await writeBack?.invalidateOpenDays()
        await refreshAllowanceIfNeeded()
        guard let ingestion else {
            await reloadToday()
            return
        }
        isSyncing = true
        defer { isSyncing = false }
        do {
            let report = try await ingestion.syncAll(trigger: trigger)
            lastSync = report.finishedAt
            await budgets?.invalidate(report.touchedDays)
            await budgets?.flush()
            await reloadToday()
            await refreshStatus()
            // The "Workout synced" moment, only for today's foreground arrivals.
            if trigger != .launch {
                for session in report.newWorkouts where session.dayKey == .today() {
                    NotificationCenter.default.post(name: .healthWorkoutSynced, object: session)
                }
            }
        } catch {
            Log.health.error("Health sync (\(trigger.rawValue, privacy: .public)) failed: \(String(describing: error), privacy: .private)")
        }
    }

    func syncInBackground(_ trigger: SyncTrigger) {
        Task { await sync(trigger) }
    }

    /// The Health permission sheet, asked in context (doc 02 §3.6). It includes
    /// HealthManager's types, so the user sees a single sheet.
    func requestAuthorization() async {
        do {
            try await client.requestAuthorization()
        } catch {
            Log.health.error("Health authorization failed: \(error.localizedDescription, privacy: .public)")
        }
        await refreshStatus()
        await sync(.manual)
    }

    // MARK: Reads (CAL-03: the only budget)

    /// The stored budget for `day`. Before `BudgetService` has stored one, it
    /// computes the same formula from what's cached, so the number never flickers
    /// to a placeholder.
    func budget(on day: DayKey = .today()) -> Double {
        if let stored = energyByDay[day]?.budgetKcal { return stored }
        if day == .today(), let todayBreakdown { return todayBreakdown.budget.rounded() }
        Task { await budgets?.invalidate([day]) }
        if let profile = PersistenceManager.shared.loadUserProfile() {
            let energy = energyByDay[day] ?? EnergyDay(dayKey: day)
            return BudgetPlanner.budget(for: energy, recent: Array(energyByDay.values), profile: profile,
                                        settings: settings).budget.rounded()
        }
        return CalorieLimitSettings.shared.loadLimit()
    }

    /// Apple Health active energy for `day` (all sources merged), if any.
    func activeKcal(on day: DayKey = .today()) -> Double? { energyByDay[day]?.activeKcal }

    /// Exercise energy the budget used for `day`: measured active kcal or the estimate.
    func exerciseKcal(on day: DayKey = .today()) -> Double {
        let energy = energyByDay[day]
        if energy?.budgetMode == .measured { return energy?.activeKcal ?? 0 }
        return energy?.estimatedSessionKcal ?? 0
    }

    // MARK: Settings (CAL-05)

    /// Changes the budget settings. Today and the open days recompute; frozen days don't.
    func updateSettings(_ mutate: (inout EnergySettings) -> Void) {
        var next = settings
        mutate(&next)
        next.eatBack = EnergySettings.snapEatBack(next.eatBack)
        guard next != settings else { return }
        settings = next
        let database = self.database
        LocalStore.shared.enqueue { try await database.energySettings.save(next) }
    }

    // MARK: Write-back (WCH-08)

    /// Turns the food and water mirror on (asking for Health permission) or off.
    func setSavesToHealth(_ enabled: Bool) async {
        guard let writeBack else { return }
        do {
            try await writeBack.setEnabled(enabled)
        } catch {
            Log.health.error("Save to Health toggle failed: \(error.localizedDescription, privacy: .public)")
        }
        savesToHealth = (try? await writeBack.isEnabled()) ?? false
        writableKinds = await writeBack.writableKinds()
    }

    private func startWriteBack() async {
        guard client.isAvailable, writeBack == nil else { return }
        let writeBack = HealthWriteBackService(client: client, database: database)
        self.writeBack = writeBack
        await writeBack.start()
        savesToHealth = (try? await writeBack.isEnabled()) ?? false
        writableKinds = await writeBack.writableKinds()
        await writeBack.invalidateOpenDays()
    }

    // MARK: Private

    private func listen() {
        guard listenTask == nil else { return }
        let stream = database.changes.changes()
        let watched: Set<String> = [EnergyDay.collection, WorkoutSession.collection, "documents/profile",
                                    EnergySettings.changeCollection]
        listenTask = Task { [weak self] in
            for await change in stream where watched.contains(change.collection) {
                guard let self else { return }
                await self.reload(days: change.days, collection: change.collection)
            }
        }
    }

    private func reload(days: Set<DayKey>, collection: String) async {
        do {
            for day in days where collection == EnergyDay.collection {
                energyByDay[day] = try await database.energy.day(day)
            }
            if collection == EnergySettings.changeCollection {
                settings = try await database.energySettings.load()
            }
            if days.contains(.today()) || days.isEmpty {
                await reloadToday()
                WatchConnectivityManager.shared.sendSnapshot()
            }
        } catch {
            Log.health.error("Energy reload failed: \(String(describing: error), privacy: .private)")
        }
    }

    private func reloadToday() async {
        let today = DayKey.today()
        do {
            energyByDay[today] = try await database.energy.day(today)
            todaySessions = try await database.workoutSessions.sessions(on: today)
            todayBreakdown = try await budgets?.breakdown(on: today)
        } catch {
            Log.health.error("Today reload failed: \(String(describing: error), privacy: .private)")
        }
    }

    private func refreshAllowanceIfNeeded() async {
        let today = DayKey.today()
        guard allowanceCheckedOn != today, let budgets else { return }
        allowanceCheckedOn = today
        _ = try? await budgets.refreshAllowance()
    }

    private func refreshStatus() async {
        guard client.isAvailable else { status = .unavailable; return }
        let requestStatus = try? await client.store.statusForAuthorizationRequest(toShare: [],
                                                                                   read: HKHealthStoreClient.readTypes)
        if requestStatus == .shouldRequest {
            status = .notDetermined
            return
        }
        // HealthKit hides read denials. Seven synced days without any energy
        // while the app has been asking is the tell (doc 02 §3.6).
        let week = (0..<7).map { DayKey.today().adding(days: -$0) }
        let syncedWeek = week.compactMap { energyByDay[$0] }.filter { $0.lastSyncedAt != nil }
        let anyEnergy = syncedWeek.contains { ($0.activeKcal ?? 0) > 0 || ($0.steps ?? 0) > 0 }
        status = syncedWeek.count >= 7 && !anyEnergy ? .likelyDenied : .connected
    }

    /// One-time copy of the pre-P1 settings (eat-back %, manual target) into
    /// `EnergySettings`. The old keys stay readable for rollback.
    private func migrateLegacySettingsIfNeeded() async {
        let key = "energySettings.migrated.v1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        var migrated = settings
        migrated.eatBack = EnergySettings.snapEatBack(CalorieSettings.shared.loadPercentage())
        if CalorieLimitSettings.shared.isManual {
            migrated.manualTarget = CalorieLimitSettings.shared.loadLimit()
        }
        do {
            try await database.energySettings.save(migrated)
            settings = migrated
            UserDefaults.standard.set(true, forKey: key)
        } catch {
            Log.health.error("Energy settings migration failed: \(String(describing: error), privacy: .private)")
        }
    }
}
