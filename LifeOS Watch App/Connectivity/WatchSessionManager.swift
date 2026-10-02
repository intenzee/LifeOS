import Foundation
import Combine
import WatchConnectivity
import LifeOSCore
import LifeOSConnectivity

/// Watch-side bridge to the phone. Receives day snapshots and sends user
/// mutations (water, todos, workout sets). Applies optimistic local updates so
/// the UI feels instant, then reconciles with the phone's authoritative reply.
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published private(set) var snapshot: WatchSnapshot = .empty
    @Published private(set) var isReachable = false
    @Published private(set) var hasReceivedData = false
    /// Set once the phone sends a typed snapshot. Until then mutations go out
    /// as v1 dictionaries, so an older phone app keeps working (FND-11).
    private var phoneSpeaksTyped = false

    /// The day the watch is showing. Mutations apply to it, even if they're
    /// delivered after midnight.
    private var displayedDay: DayKey { DayKey(snapshot.date) ?? .today() }

    private override init() {
        super.init()
        activate()
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    // MARK: - Outgoing mutations

    func requestSnapshot() {
        send(.requestSnapshot, legacy: ["action": "requestSnapshot"])
    }

    func setWater(_ count: Int) {
        let clamped = max(0, count)
        snapshot.waterCount = clamped // optimistic
        send(.setWater(glasses: clamped, day: displayedDay), legacy: ["action": "setWater", "value": clamped])
    }

    func setWeight(_ kg: Double) {
        let rounded = (kg * 10).rounded() / 10
        snapshot.currentWeight = rounded // optimistic
        send(.setWeight(kg: rounded, day: displayedDay), legacy: ["action": "setWeight", "value": rounded])
    }

    func toggleTodo(_ id: UUID) {
        if let idx = snapshot.todos.firstIndex(where: { $0.id == id }) {
            snapshot.todos[idx].done.toggle() // optimistic
        }
        send(.toggleTodo(id: id, day: displayedDay), legacy: ["action": "toggleTodo", "id": id.uuidString])
    }

    func updateExerciseSets(_ id: UUID, setsCompleted: Int) {
        if let idx = snapshot.exercises.firstIndex(where: { $0.id == id }) {
            let maxSets = snapshot.exercises[idx].maxSets
            snapshot.exercises[idx].setsCompleted = min(max(setsCompleted, 0), maxSets) // optimistic
        }
        send(.setExerciseSets(exerciseID: id, sets: setsCompleted, day: displayedDay),
             legacy: ["action": "updateExerciseSets", "id": id.uuidString, "setsCompleted": setsCompleted])
    }

    func addExercise(bodyPart: String, name: String, maxSets: Int) {
        let legacy: [String: Any] = ["action": "addExercise", "bodyPart": bodyPart, "name": name, "maxSets": maxSets]
        guard let part = BodyPart(rawValue: bodyPart) else { return send(nil, legacy: legacy) }
        send(.addExercise(bodyPart: part, name: name.isEmpty ? nil : name, maxSets: maxSets, day: displayedDay),
             legacy: legacy)
    }

    // MARK: - Transport

    /// Sends a mutation. Uses an interactive message (with reply carrying a fresh
    /// snapshot) when the phone is reachable, else queues it for background delivery.
    private func send(_ mutation: WatchMutation?, legacy: [String: Any]) {
        var message = legacy
        if phoneSpeaksTyped, let mutation, let typed = try? WatchWire.encode(mutation) {
            message = typed
        }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        if session.isReachable {
            session.sendMessage(message, replyHandler: { [weak self] reply in
                self?.ingest(reply)
            }, errorHandler: { [weak self] _ in
                self?.session(session, transferUserInfoQueued: message)
            })
        } else {
            self.session(session, transferUserInfoQueued: message)
        }
    }

    private func session(_ session: WCSession, transferUserInfoQueued message: [String: Any]) {
        session.transferUserInfo(message)
    }

    /// Prefers the typed envelope and falls back to the v1 keys.
    private func ingest(_ dict: [String: Any]) {
        var typed = false
        let parsed: WatchSnapshot?
        if WatchWire.isTyped(dict), let snapshot = try? WatchWire.decodeSnapshot(dict) {
            parsed = WatchSnapshot(snapshot)
            typed = true
        } else {
            parsed = WatchSnapshot(dictionary: dict)
        }
        guard let parsed else { return }
        Task { @MainActor in
            self.snapshot = parsed
            self.hasReceivedData = true
            if typed { self.phoneSpeaksTyped = true }
        }
    }
}

extension WatchSessionManager: WCSessionDelegate {
    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith activationState: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if activationState == .activated { self.requestSnapshot() }
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.isReachable = session.isReachable
            if session.isReachable { self.requestSnapshot() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        ingest(applicationContext)
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        ingest(userInfo)
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        ingest(message)
    }
}
