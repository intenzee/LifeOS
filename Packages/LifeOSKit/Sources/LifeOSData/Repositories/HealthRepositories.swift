import Foundation
import LifeOSCore

// Phase 1 repositories (doc 02, doc 03): imported workouts, per-day energy and
// budget, the budget settings, and HealthKit sync bookkeeping.

public protocol WorkoutSessionRepository: Sendable {
    func sessions(on day: DayKey) async throws -> [WorkoutSession]
    func sessions(from start: DayKey, through end: DayKey) async throws -> [WorkoutSession]
    /// Replaces the day's sessions in one write (no change event when identical).
    func replaceSessions(on day: DayKey, with sessions: [WorkoutSession]) async throws
}

public protocol EnergyRepository: Sendable {
    func day(_ day: DayKey) async throws -> EnergyDay?
    func days(from start: DayKey, through end: DayKey) async throws -> [EnergyDay]
    /// Atomic read-modify-write. Creates the day if missing. Writes only on change.
    @discardableResult
    func update(_ day: DayKey, _ mutate: @Sendable (inout EnergyDay) -> Void) async throws -> EnergyDay
}

public protocol EnergySettingsRepository: Sendable {
    func load() async throws -> EnergySettings
    func save(_ settings: EnergySettings) async throws
}

/// HealthKit sync bookkeeping (doc 01 `SyncAnchor`), one document.
public struct HealthSyncState: Codable, Sendable, Equatable {
    /// Archived `HKQueryAnchor`s by sync key (e.g. `"workouts"`).
    public var anchors: [String: Data]
    /// Where each imported workout lives, so a HealthKit deletion (which only
    /// carries the UUID) can find its day.
    public var workoutDays: [UUID: DayKey]
    /// End of the last sync pass that completed without error.
    public var lastCompletedSync: Date?

    public init(anchors: [String: Data] = [:], workoutDays: [UUID: DayKey] = [:], lastCompletedSync: Date? = nil) {
        self.anchors = anchors
        self.workoutDays = workoutDays
        self.lastCompletedSync = lastCompletedSync
    }
}

public protocol HealthSyncStateRepository: Sendable {
    func load() async throws -> HealthSyncState
    func save(_ state: HealthSyncState) async throws
}

/// What LifeOS has written to Apple Health (WCH-08), so edits and deletes can
/// be mirrored. It's a ledger beside the records rather than a flag on
/// `FoodEntry`, so the food schema (owned by food logging) doesn't change.
public struct HealthWriteState: Codable, Sendable, Equatable {
    /// The first day mirrored to Health. `nil` while "Save to Apple Health" is off.
    public var enabledFrom: DayKey?
    public var days: [DayKey: HealthWriteDay]

    public init(enabledFrom: DayKey? = nil, days: [DayKey: HealthWriteDay] = [:]) {
        self.enabledFrom = enabledFrom
        self.days = days
    }
}

/// One day's writes.
public struct HealthWriteDay: Codable, Sendable, Equatable {
    public struct Water: Codable, Sendable, Equatable {
        public var id: UUID
        public var ml: Double

        public init(id: UUID, ml: Double) {
            self.id = id
            self.ml = ml
        }
    }

    /// Food entry id → the write id stamped on its samples. The write id changes
    /// whenever the entry's content does.
    public var food: [UUID: UUID]
    /// Water samples, oldest first. Their sum is the day's water in Health.
    public var water: [Water]

    public init(food: [UUID: UUID] = [:], water: [Water] = []) {
        self.food = food
        self.water = water
    }

    public var isEmpty: Bool { food.isEmpty && water.isEmpty }
}

public protocol HealthWriteStateRepository: Sendable {
    func load() async throws -> HealthWriteState
    func save(_ state: HealthWriteState) async throws
}

// MARK: - Store implementations

struct StoreWorkoutSessionRepository: WorkoutSessionRepository {
    let store: RecordStore<WorkoutSession>

    func sessions(on day: DayKey) async throws -> [WorkoutSession] {
        try await store.records(on: day).sorted { $0.start < $1.start }
    }
    func sessions(from start: DayKey, through end: DayKey) async throws -> [WorkoutSession] {
        try await store.records(from: start, through: end)
    }
    func replaceSessions(on day: DayKey, with sessions: [WorkoutSession]) async throws {
        try await store.replaceAll(on: day, with: sessions.sorted { $0.start < $1.start })
    }
}

struct StoreEnergyRepository: EnergyRepository {
    let store: RecordStore<EnergyDay>

    func day(_ day: DayKey) async throws -> EnergyDay? { try await store.record(id: day, on: day) }
    func days(from start: DayKey, through end: DayKey) async throws -> [EnergyDay] {
        try await store.records(from: start, through: end)
    }
    func update(_ day: DayKey, _ mutate: @Sendable (inout EnergyDay) -> Void) async throws -> EnergyDay {
        try await store.update(id: day, on: day, default: { EnergyDay(dayKey: day) }, mutate)
    }
}

struct StoreEnergySettingsRepository: EnergySettingsRepository {
    let store: DocumentStore<EnergySettings>

    func load() async throws -> EnergySettings { try await store.load() ?? EnergySettings() }
    func save(_ settings: EnergySettings) async throws { try await store.save(settings) }
}

struct StoreHealthSyncStateRepository: HealthSyncStateRepository {
    let store: DocumentStore<HealthSyncState>

    func load() async throws -> HealthSyncState { try await store.load() ?? HealthSyncState() }
    func save(_ state: HealthSyncState) async throws { try await store.save(state) }
}

struct StoreHealthWriteStateRepository: HealthWriteStateRepository {
    let store: DocumentStore<HealthWriteState>

    func load() async throws -> HealthWriteState { try await store.load() ?? HealthWriteState() }
    func save(_ state: HealthWriteState) async throws { try await store.save(state) }
}
