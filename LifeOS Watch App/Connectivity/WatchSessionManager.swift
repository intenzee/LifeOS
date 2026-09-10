import Foundation
import Combine
import WatchConnectivity

/// Watch-side bridge to the phone. Receives day snapshots and sends user
/// mutations (water, todos, workout sets). Applies optimistic local updates so
/// the UI feels instant, then reconciles with the phone's authoritative reply.
final class WatchSessionManager: NSObject, ObservableObject {
    static let shared = WatchSessionManager()

    @Published private(set) var snapshot: WatchSnapshot = .empty
    @Published private(set) var isReachable = false
    @Published private(set) var hasReceivedData = false

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
        send(["action": "requestSnapshot"])
    }

    func setWater(_ count: Int) {
        let clamped = max(0, count)
        snapshot.waterCount = clamped // optimistic
        send(["action": "setWater", "value": clamped])
    }

    func setWeight(_ kg: Double) {
        let rounded = (kg * 10).rounded() / 10
        snapshot.currentWeight = rounded // optimistic
        send(["action": "setWeight", "value": rounded])
    }

    func toggleTodo(_ id: UUID) {
        if let idx = snapshot.todos.firstIndex(where: { $0.id == id }) {
            snapshot.todos[idx].done.toggle() // optimistic
        }
        send(["action": "toggleTodo", "id": id.uuidString])
    }

    func updateExerciseSets(_ id: UUID, setsCompleted: Int) {
        if let idx = snapshot.exercises.firstIndex(where: { $0.id == id }) {
            let maxSets = snapshot.exercises[idx].maxSets
            snapshot.exercises[idx].setsCompleted = min(max(setsCompleted, 0), maxSets) // optimistic
        }
        send(["action": "updateExerciseSets", "id": id.uuidString, "setsCompleted": setsCompleted])
    }

    func addExercise(bodyPart: String, name: String, maxSets: Int) {
        send([
            "action": "addExercise",
            "bodyPart": bodyPart,
            "name": name,
            "maxSets": maxSets
        ])
    }

    // MARK: - Transport

    /// Sends a mutation. Uses an interactive message (with reply carrying a fresh
    /// snapshot) when the phone is reachable, else queues it for background delivery.
    private func send(_ message: [String: Any]) {
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

    private func ingest(_ dict: [String: Any]) {
        guard let parsed = WatchSnapshot(dictionary: dict) else { return }
        Task { @MainActor in
            self.snapshot = parsed
            self.hasReceivedData = true
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
