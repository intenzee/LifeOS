import Foundation
import LifeOSCore

/// The typed, versioned phone ↔ watch contract (FND-11). It replaces the
/// hand-mirrored `[String: Any]` dictionaries in `WatchConnectivityManager`
/// and `WatchSessionManager`.
///
/// On the wire every message is a WatchConnectivity dictionary:
/// `["lifeos.v": schemaVersion, "lifeos.kind": "snapshot" | "mutation", "lifeos.payload": <JSON Data>]`.
/// Bump `schemaVersion` on any breaking change. A receiver rejects newer major
/// versions with `WatchWireError.unsupportedVersion` and keeps its last snapshot.
public enum WatchContract {
    public static let schemaVersion = 2 // v1 = the untyped legacy dictionaries

    enum Key {
        static let version = "lifeos.v"
        static let kind = "lifeos.kind"
        static let payload = "lifeos.payload"
    }

    enum Kind: String {
        case snapshot, mutation
    }
}

public enum WatchWireError: Error, Equatable, Sendable {
    case notAWatchMessage
    case unsupportedVersion(Int)
    case wrongKind(expected: String, actual: String)
    case undecodable(String)
}

// MARK: - Snapshot (phone → watch)

/// Today's state, pushed with `updateApplicationContext` (latest wins).
public struct WatchSnapshot: Codable, Sendable, Equatable {
    public var schemaVersion: Int
    public var day: DayKey
    public var caloriesConsumed: Double
    public var calorieLimit: Double
    public var caloriesBurned: Double
    public var waterGlasses: Int
    public var waterTarget: Int
    public var perfectStreak: Int
    public var currentWeightKg: Double
    public var targetWeightKg: Double
    public var steps: Int
    public var todos: [Todo]
    public var exercises: [Exercise]

    public struct Todo: Codable, Sendable, Equatable, Identifiable {
        public let id: UUID
        public var title: String
        public var done: Bool

        public init(id: UUID, title: String, done: Bool) {
            self.id = id
            self.title = title
            self.done = done
        }
    }

    public init(day: DayKey, caloriesConsumed: Double, calorieLimit: Double, caloriesBurned: Double,
                waterGlasses: Int, waterTarget: Int, perfectStreak: Int, currentWeightKg: Double,
                targetWeightKg: Double, steps: Int, todos: [Todo], exercises: [Exercise]) {
        self.schemaVersion = WatchContract.schemaVersion
        self.day = day
        self.caloriesConsumed = caloriesConsumed
        self.calorieLimit = calorieLimit
        self.caloriesBurned = caloriesBurned
        self.waterGlasses = waterGlasses
        self.waterTarget = waterTarget
        self.perfectStreak = perfectStreak
        self.currentWeightKg = currentWeightKg
        self.targetWeightKg = targetWeightKg
        self.steps = steps
        self.todos = todos
        self.exercises = exercises
    }

    public static func empty(day: DayKey) -> WatchSnapshot {
        WatchSnapshot(day: day, caloriesConsumed: 0, calorieLimit: 0, caloriesBurned: 0, waterGlasses: 0,
                      waterTarget: 8, perfectStreak: 0, currentWeightKg: 0, targetWeightKg: 0, steps: 0,
                      todos: [], exercises: [])
    }

    public var caloriesRemaining: Double { max(calorieLimit - caloriesConsumed, 0) }
    public var calorieProgress: Double { calorieLimit > 0 ? min(caloriesConsumed / calorieLimit, 1) : 0 }
    public var waterProgress: Double { waterTarget > 0 ? min(Double(waterGlasses) / Double(waterTarget), 1) : 0 }
    public var todosCompleted: Int { todos.filter(\.done).count }
}

// MARK: - Mutations (watch → phone)

/// Changes the watch asks the phone to make. The phone is the source of truth.
/// Every mutation names its day, so a message delivered after midnight can't
/// land on the wrong date.
public enum WatchMutation: Codable, Sendable, Equatable {
    case requestSnapshot
    case setWater(glasses: Int, day: DayKey)
    case setWeight(kg: Double, day: DayKey)
    case toggleTodo(id: UUID, day: DayKey)
    case setExerciseSets(exerciseID: UUID, sets: Int, day: DayKey)
    case addExercise(bodyPart: BodyPart, name: String?, maxSets: Int, day: DayKey)
}

// MARK: - Wire encoding

public enum WatchWire {
    public static func encode(_ snapshot: WatchSnapshot) throws -> [String: Any] {
        try envelope(.snapshot, snapshot)
    }

    public static func encode(_ mutation: WatchMutation) throws -> [String: Any] {
        try envelope(.mutation, mutation)
    }

    public static func decodeSnapshot(_ message: [String: Any]) throws -> WatchSnapshot {
        try open(message, as: .snapshot)
    }

    public static func decodeMutation(_ message: [String: Any]) throws -> WatchMutation {
        try open(message, as: .mutation)
    }

    /// `true` if the dictionary uses the typed envelope (vs. legacy v1 keys).
    public static func isTyped(_ message: [String: Any]) -> Bool {
        message[WatchContract.Key.version] != nil
    }

    private static func envelope<T: Encodable>(_ kind: WatchContract.Kind, _ value: T) throws -> [String: Any] {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return [
            WatchContract.Key.version: WatchContract.schemaVersion,
            WatchContract.Key.kind: kind.rawValue,
            WatchContract.Key.payload: try encoder.encode(value)
        ]
    }

    private static func open<T: Decodable>(_ message: [String: Any], as kind: WatchContract.Kind) throws -> T {
        guard let version = message[WatchContract.Key.version] as? Int,
              let actualKind = message[WatchContract.Key.kind] as? String,
              let payload = message[WatchContract.Key.payload] as? Data else {
            throw WatchWireError.notAWatchMessage
        }
        guard version <= WatchContract.schemaVersion else { throw WatchWireError.unsupportedVersion(version) }
        guard actualKind == kind.rawValue else {
            throw WatchWireError.wrongKind(expected: kind.rawValue, actual: actualKind)
        }
        do {
            return try JSONDecoder().decode(T.self, from: payload)
        } catch {
            throw WatchWireError.undecodable(String(describing: error))
        }
    }
}

// MARK: - Legacy v1 compatibility (remove two releases after FND-11 ships)

public extension WatchSnapshot {
    /// Reads a v1 snapshot dictionary from a phone that hasn't updated yet.
    init?(legacyDictionary dict: [String: Any]) {
        guard (dict["type"] as? String) == "snapshot" else { return nil }
        let day = (dict["date"] as? String).flatMap(DayKey.init) ?? DayKey.today()
        let todos = (dict["todos"] as? [[String: Any]] ?? []).compactMap { item -> Todo? in
            guard let id = (item["id"] as? String).flatMap(UUID.init(uuidString:)) else { return nil }
            return Todo(id: id, title: item["title"] as? String ?? "", done: item["done"] as? Bool ?? false)
        }
        let exercises = (dict["exercises"] as? [[String: Any]] ?? []).compactMap { item -> Exercise? in
            guard let id = (item["id"] as? String).flatMap(UUID.init(uuidString:)),
                  let bodyPart = (item["bodyPart"] as? String).flatMap(BodyPart.init(rawValue:)) else { return nil }
            let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            return Exercise(id: id, bodyPart: bodyPart, name: name,
                            setsCompleted: item["setsCompleted"] as? Int ?? 0, maxSets: item["maxSets"] as? Int ?? 3)
        }
        self.init(day: day,
                  caloriesConsumed: dict["caloriesConsumed"] as? Double ?? 0,
                  calorieLimit: dict["calorieLimit"] as? Double ?? 0,
                  caloriesBurned: dict["caloriesBurned"] as? Double ?? 0,
                  waterGlasses: dict["waterCount"] as? Int ?? 0,
                  waterTarget: dict["waterTarget"] as? Int ?? 8,
                  perfectStreak: dict["perfectStreak"] as? Int ?? 0,
                  currentWeightKg: dict["currentWeight"] as? Double ?? 0,
                  targetWeightKg: dict["targetWeight"] as? Double ?? 0,
                  steps: dict["steps"] as? Int ?? 0,
                  todos: todos, exercises: exercises)
        self.schemaVersion = 1
    }
}
