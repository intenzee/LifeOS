import Foundation
import Combine
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

extension Notification.Name {
    /// Posted after the paired Apple Watch mutates data the phone UI displays
    /// (water, todos, workout sets) so open screens can reload.
    static let watchDidMutateData = Notification.Name("watchDidMutateData")
}

/// Phone-side bridge to the Apple Watch companion.
///
/// - Pushes a daily *snapshot* (calories, water, todos, today's exercises) to the
///   watch via `updateApplicationContext` (latest-state-wins, survives launches).
/// - Receives *mutation* messages from the watch and applies them to the existing
///   managers so the phone UI updates reactively, then re-sends the snapshot.
///
/// The wire format is plain `[String: Any]` dictionaries with agreed keys, mirrored
/// by the watch target's own connectivity manager — no shared source files.
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()

    private let foodDatabase: FoodDatabaseManager
    private let workoutDatabase: WorkoutDatabaseManager
    private let persistence: PersistenceManager
    private let streakManager: StreakManager

    private var cancellables = Set<AnyCancellable>()

    init(
        foodDatabase: FoodDatabaseManager = .shared,
        workoutDatabase: WorkoutDatabaseManager = .shared,
        persistence: PersistenceManager = .shared,
        streakManager: StreakManager = .shared
    ) {
        self.foodDatabase = foodDatabase
        self.workoutDatabase = workoutDatabase
        self.persistence = persistence
        self.streakManager = streakManager
        super.init()
    }

    // MARK: - Session lifecycle

    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()

        // Re-push the snapshot whenever data the watch mirrors changes on the phone.
        NotificationCenter.default.publisher(for: .weekTodoListDidChange)
            .merge(with: NotificationCenter.default.publisher(for: .watchDidMutateData))
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.sendSnapshot() }
            .store(in: &cancellables)
        #endif
    }

    // MARK: - Date helpers

    private static let dateKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static let dayNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    private var todayDayName: String { Self.dayNameFormatter.string(from: Date()) }

    // MARK: - Snapshot (phone -> watch)

    /// Builds the current day's snapshot dictionary.
    func makeSnapshot() -> [String: Any] {
        let currentWeight = persistence.loadCurrentWeight()
        let todayLog = foodDatabase.dailyLog(for: Date())
        let burned = workoutDatabase.getCaloriesBurnedForDay(todayDayName, weightKg: currentWeight)
        let baseLimit = CalorieLimitSettings.shared.loadLimit()
        let percentage = CalorieSettings.shared.loadPercentage()
        let adjustedLimit = baseLimit + burned * percentage

        let profile = persistence.loadUserProfile()
        let waterTarget = profile?.waterGoalGlasses ?? 8

        let todos = (persistence.loadWeekTodoList()[todayDayName] ?? []).map { todo -> [String: Any] in
            ["id": todo.id.uuidString, "title": todo.title, "done": todo.isCompleted]
        }

        let exercises = workoutDatabase.loadWorkoutForDay(todayDayName).exercises.map { ex -> [String: Any] in
            [
                "id": ex.id.uuidString,
                "bodyPart": ex.bodyPart.rawValue,
                "name": ex.name ?? "",
                "setsCompleted": ex.setsCompleted,
                "maxSets": ex.maxSets
            ]
        }

        return [
            "type": "snapshot",
            "date": Self.dateKeyFormatter.string(from: Date()),
            "caloriesConsumed": todayLog.totalCalories(),
            "calorieLimit": adjustedLimit,
            "caloriesBurned": burned,
            "waterCount": persistence.loadWaterCount(for: Date()),
            "waterTarget": waterTarget,
            "perfectStreak": streakManager.perfectDayStreak,
            "currentWeight": currentWeight,
            "targetWeight": persistence.loadTargetWeight(),
            "steps": Int(latestSteps),
            "todos": todos,
            "exercises": exercises
        ]
    }

    /// Latest step count, fed in by the app so the watch dashboard can show it
    /// without the (HealthKit-free) watch reading HealthKit itself. Setting it
    /// re-pushes the snapshot.
    var latestSteps: Double = 0 {
        didSet { if Int(latestSteps) != Int(oldValue) { sendSnapshot() } }
    }

    func sendSnapshot() {
        #if canImport(WatchConnectivity)
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        // Application context = latest state wins; ideal for a dashboard mirror.
        try? session.updateApplicationContext(makeSnapshot())
        #endif
    }

    // MARK: - Mutations (watch -> phone)

    /// Applies a mutation dictionary received from the watch. Runs on the main actor.
    @MainActor
    func applyMutation(_ message: [String: Any]) {
        guard let action = message["action"] as? String else { return }

        switch action {
        case "requestSnapshot":
            break // snapshot is sent below regardless

        case "setWater":
            if let value = message["value"] as? Int {
                persistence.saveWaterCount(max(0, value), for: Date())
            }

        case "setWeight":
            if let value = message["value"] as? Double, value > 0 {
                persistence.saveCurrentWeight(value) // also records weight history
            }

        case "toggleTodo":
            if let idString = message["id"] as? String, let id = UUID(uuidString: idString) {
                var week = persistence.loadWeekTodoList()
                if var todos = week[todayDayName],
                   let idx = todos.firstIndex(where: { $0.id == id }) {
                    todos[idx].isCompleted.toggle()
                    week[todayDayName] = todos
                    persistence.saveWeekTodoList(week) // posts .weekTodoListDidChange
                }
            }

        case "updateExerciseSets":
            if let idString = message["id"] as? String, let id = UUID(uuidString: idString),
               let sets = message["setsCompleted"] as? Int {
                workoutDatabase.setExerciseSetsForDay(todayDayName, exerciseId: id, setsCompleted: sets)
            }

        case "addExercise":
            if let bodyPartRaw = message["bodyPart"] as? String,
               let bodyPart = BodyPart(rawValue: bodyPartRaw) {
                let name = (message["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                let maxSets = message["maxSets"] as? Int ?? 3
                let exercise = Exercise(bodyPart: bodyPart, name: name, maxSets: maxSets)
                workoutDatabase.addExerciseForDay(todayDayName, exercise: exercise)
            }

        default:
            break
        }

        NotificationCenter.default.post(name: .watchDidMutateData, object: nil)
        sendSnapshot()
    }
}

#if canImport(WatchConnectivity)
extension WatchConnectivityManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        if activationState == .activated {
            Task { @MainActor in self.sendSnapshot() }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Reactivate for switching between paired watches.
        WCSession.default.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.applyMutation(message) }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.applyMutation(message)
            replyHandler(self.makeSnapshot())
        }
    }
}
#endif
