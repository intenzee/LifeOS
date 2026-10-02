import Foundation
import Combine
import LifeOSConnectivity
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
/// Wire format (FND-11): every snapshot carries the typed, versioned
/// `LifeOSConnectivity` envelope **and** the legacy v1 keys, so an older watch
/// app keeps working. Mutations are accepted in either format. Typed ones name
/// their day, so a message delivered after midnight lands on the right date.
/// `FeatureFlag.typedWatchContract` is a kill switch: off means v1 keys only.
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

    // MARK: - Snapshot (phone -> watch)

    /// Today's typed snapshot. The single source for both wire formats.
    func makeTypedSnapshot() -> LifeOSConnectivity.WatchSnapshot {
        let today = DayKey.today()
        let currentWeight = persistence.loadCurrentWeight()
        let todayLog = foodDatabase.dailyLog(for: Date())
        let workout = workoutDatabase.workout(on: today)
        let burned = CalorieCalculator.totalWorkoutCalories(workout: workout, weightKg: currentWeight)
        let adjustedLimit = CalorieLimitSettings.shared.loadLimit() + burned * CalorieSettings.shared.loadPercentage()

        return LifeOSConnectivity.WatchSnapshot(
            day: today,
            caloriesConsumed: todayLog.totalCalories(),
            calorieLimit: adjustedLimit,
            caloriesBurned: burned,
            waterGlasses: persistence.loadWaterCount(for: Date()),
            waterTarget: persistence.loadUserProfile()?.waterGoalGlasses ?? 8,
            perfectStreak: streakManager.perfectDayStreak,
            currentWeightKg: currentWeight,
            targetWeightKg: persistence.loadTargetWeight(),
            steps: Int(latestSteps),
            todos: persistence.todos(on: Date()).map { .init(id: $0.id, title: $0.title, done: $0.isCompleted) },
            exercises: workout.exercises
        )
    }

    /// The application-context dictionary: legacy v1 keys plus, unless the
    /// kill switch is off, the typed envelope.
    func makeSnapshot() -> [String: Any] {
        let typed = makeTypedSnapshot()
        var message: [String: Any] = [
            "type": "snapshot",
            "date": typed.day.rawValue,
            "caloriesConsumed": typed.caloriesConsumed,
            "calorieLimit": typed.calorieLimit,
            "caloriesBurned": typed.caloriesBurned,
            "waterCount": typed.waterGlasses,
            "waterTarget": typed.waterTarget,
            "perfectStreak": typed.perfectStreak,
            "currentWeight": typed.currentWeightKg,
            "targetWeight": typed.targetWeightKg,
            "steps": typed.steps,
            "todos": typed.todos.map { ["id": $0.id.uuidString, "title": $0.title, "done": $0.done] as [String: Any] },
            "exercises": typed.exercises.map {
                ["id": $0.id.uuidString, "bodyPart": $0.bodyPart.rawValue, "name": $0.name ?? "",
                 "setsCompleted": $0.setsCompleted, "maxSets": $0.maxSets] as [String: Any]
            }
        ]
        if FeatureFlags.shared.isEnabled(.typedWatchContract) {
            do {
                message.merge(try WatchWire.encode(typed)) { _, typedValue in typedValue }
            } catch {
                Log.watch.error("Typed snapshot encode failed: \(String(describing: error), privacy: .public)")
            }
        }
        return message
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

    /// Applies a mutation from the watch (typed or legacy v1), then re-sends the snapshot.
    @MainActor
    func applyMutation(_ message: [String: Any]) {
        if WatchWire.isTyped(message) {
            do {
                apply(try WatchWire.decodeMutation(message))
            } catch {
                Log.watch.error("Rejected watch message: \(String(describing: error), privacy: .public)")
            }
        } else {
            applyLegacyMutation(message)
        }
        NotificationCenter.default.post(name: .watchDidMutateData, object: nil)
        sendSnapshot()
    }

    @MainActor
    private func apply(_ mutation: WatchMutation) {
        switch mutation {
        case .requestSnapshot:
            break
        case .setWater(let glasses, let day):
            persistence.saveWaterCount(max(0, glasses), for: day.startDate())
        case .setWeight(let kg, let day):
            guard kg > 0 else { return }
            if day == .today() {
                persistence.saveCurrentWeight(kg) // also records history
            } else {
                persistence.recordWeightPoint(kg, on: day.startDate())
            }
        case .toggleTodo(let id, let day):
            persistence.toggleTodo(id: id, on: day)
        case .setExerciseSets(let exerciseID, let sets, let day):
            workoutDatabase.updateWorkout(on: day) { workout in
                guard let index = workout.exercises.firstIndex(where: { $0.id == exerciseID }) else { return }
                workout.exercises[index].setsCompleted = min(max(sets, 0), workout.exercises[index].maxSets)
            }
        case .addExercise(let bodyPart, let name, let maxSets, let day):
            workoutDatabase.updateWorkout(on: day) {
                $0.exercises.append(Exercise(bodyPart: bodyPart, name: name, maxSets: maxSets))
            }
        }
    }

    /// v1 dictionaries from a watch app that predates FND-11. They always mean today.
    @MainActor
    private func applyLegacyMutation(_ message: [String: Any]) {
        guard let action = message["action"] as? String else { return }
        let today = DayKey.today()
        switch action {
        case "setWater":
            if let value = message["value"] as? Int { apply(.setWater(glasses: value, day: today)) }
        case "setWeight":
            if let value = message["value"] as? Double { apply(.setWeight(kg: value, day: today)) }
        case "toggleTodo":
            if let id = (message["id"] as? String).flatMap(UUID.init(uuidString:)) { apply(.toggleTodo(id: id, day: today)) }
        case "updateExerciseSets":
            if let id = (message["id"] as? String).flatMap(UUID.init(uuidString:)),
               let sets = message["setsCompleted"] as? Int {
                apply(.setExerciseSets(exerciseID: id, sets: sets, day: today))
            }
        case "addExercise":
            if let bodyPart = (message["bodyPart"] as? String).flatMap(BodyPart.init(rawValue:)) {
                let name = (message["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                apply(.addExercise(bodyPart: bodyPart, name: name, maxSets: message["maxSets"] as? Int ?? 3, day: today))
            }
        default:
            break // includes "requestSnapshot"
        }
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
