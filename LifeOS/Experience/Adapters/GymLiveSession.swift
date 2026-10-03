import ActivityKit
import Combine
import Foundation

/// Phase 5 §4: an in-app gym session shown as a Live Activity (Lock Screen and
/// Dynamic Island). "Log set" adds a set to the first unfinished exercise of
/// today's log and starts the rest countdown; "Skip" ends rest early.
@MainActor
final class GymLiveSession: ObservableObject {
    static let shared = GymLiveSession()

    @Published private(set) var isActive = false
    @Published private(set) var state: LifeOSActivityAttributes.ContentState?
    @Published var restSeconds: Int {
        didSet { UserDefaults.standard.set(restSeconds, forKey: "lx.gym.restSeconds") }
    }

    private var activity: Activity<LifeOSActivityAttributes>?
    private var restEnd: Task<Void, Never>?

    private init() {
        restSeconds = UserDefaults.standard.object(forKey: "lx.gym.restSeconds") as? Int ?? 90
        // Pick up a session that survived an app relaunch.
        if let running = Activity<LifeOSActivityAttributes>.activities.first {
            activity = running
            state = running.content.state
            isActive = true
        }
    }

    var activitiesEnabled: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    func start() async {
        let store = await IntentRuntime.store()
        let s = makeState(store, restEndsAt: nil)
        state = s
        isActive = true
        guard activitiesEnabled, activity == nil else { return }
        do {
            activity = try Activity.request(attributes: LifeOSActivityAttributes(startedAt: Date()),
                                            content: .init(state: s, staleDate: nil))
        } catch {
            Log.ui.error("Live Activity failed: \(String(describing: error), privacy: .public)")
        }
    }

    func logSet() async {
        let store = await IntentRuntime.store()
        let today = DayKey.today()
        var workout = store.workouts.workout(on: today)
        guard let i = workout.exercises.firstIndex(where: { $0.setsCompleted < $0.maxSets }) ?? workout.exercises.indices.last else {
            await push(makeState(store, restEndsAt: nil))
            return
        }
        workout.exercises[i].setsCompleted += 1
        store.workouts.replaceWorkout(workout, on: today)
        store.reload()
        store.afterWrite()
        let ends = Date().addingTimeInterval(TimeInterval(restSeconds))
        await push(makeState(store, restEndsAt: ends))
        restEnd?.cancel()
        restEnd = Task { [weak self] in
            try? await Task.sleep(for: .seconds(self?.restSeconds ?? 90))
            guard !Task.isCancelled else { return }
            await self?.endRest()
        }
    }

    func skipRest() {
        restEnd?.cancel()
        Task { await endRest() }
    }

    func end() async {
        restEnd?.cancel()
        let final = state.map { s -> LifeOSActivityAttributes.ContentState in
            var f = s
            f.finished = true
            f.restEndsAt = nil
            return f
        }
        if let activity, let final {
            await activity.end(.init(state: final, staleDate: nil), dismissalPolicy: .after(Date().addingTimeInterval(15 * 60)))
        }
        activity = nil
        state = nil
        isActive = false
    }

    private func endRest() async {
        let store = await IntentRuntime.store()
        await push(makeState(store, restEndsAt: nil))
    }

    private func push(_ s: LifeOSActivityAttributes.ContentState) async {
        state = s
        await activity?.update(.init(state: s, staleDate: nil))
    }

    private func makeState(_ store: ExperienceStore, restEndsAt: Date?) -> LifeOSActivityAttributes.ContentState {
        let exercises = store.workouts.workout(on: DayKey.today()).exercises
        let current = exercises.first { $0.setsCompleted < $0.maxSets } ?? exercises.last
        let next = current.flatMap { c in exercises.first { $0.id != c.id && $0.setsCompleted < $0.maxSets } }
        return .init(exercise: current?.displayName ?? "Add an exercise in Training",
                     setsDone: current?.setsCompleted ?? 0, setsTotal: current?.maxSets ?? 0,
                     setsToday: exercises.reduce(0) { $0 + $1.setsCompleted },
                     restEndsAt: restEndsAt, restSeconds: restSeconds,
                     nextExercise: next?.displayName, finished: false)
    }
}
