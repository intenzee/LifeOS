import Foundation
import CryptoKit
import LifeOSCore

/// The app's data layer: every repository over one storage backend, plus the
/// change bus. Create one per process and inject it through `AppDependencies`.
public struct LifeOSDatabase: Sendable {
    public let food: any FoodLogRepository
    public let workouts: any WorkoutRepository
    public let water: any WaterRepository
    public let weight: any WeightRepository
    public let tasks: any TaskRepository
    public let proteinChecklist: any ProteinChecklistRepository
    public let summaries: any SummaryRepository
    public let profile: any ProfileRepository
    public let foodLibrary: any FoodLibraryRepository
    public let workoutSessions: any WorkoutSessionRepository
    public let energy: any EnergyRepository
    public let energySettings: any EnergySettingsRepository
    public let healthSync: any HealthSyncStateRepository
    public let healthWrites: any HealthWriteStateRepository
    public let changes: ChangeBus
    public let backend: any StorageBackend

    let stores: Stores

    struct Stores: Sendable {
        let food: RecordStore<FoodEntry>
        let workouts: RecordStore<WorkoutDay>
        let water: RecordStore<WaterDay>
        let weight: RecordStore<WeightEntry>
        let tasks: RecordStore<TaskItem>
        let proteinChecklist: RecordStore<ProteinChecklist>
        let summaries: RecordStore<DailySummary>
        let profile: DocumentStore<UserProfile>
        let foodLibrary: DocumentStore<FoodLibrary>
        let workoutSessions: RecordStore<WorkoutSession>
        let energy: RecordStore<EnergyDay>
        let energySettings: DocumentStore<EnergySettings>
        let healthSync: DocumentStore<HealthSyncState>
        let healthWrites: DocumentStore<HealthWriteState>
    }

    public init(backend: any StorageBackend) {
        let bus = ChangeBus()
        let stores = Stores(
            food: RecordStore(backend: backend, bus: bus),
            workouts: RecordStore(backend: backend, bus: bus),
            water: RecordStore(backend: backend, bus: bus),
            weight: RecordStore(backend: backend, bus: bus),
            tasks: RecordStore(backend: backend, bus: bus),
            proteinChecklist: RecordStore(backend: backend, bus: bus),
            summaries: RecordStore(backend: backend, bus: bus),
            profile: DocumentStore(name: "profile", backend: backend, bus: bus),
            foodLibrary: DocumentStore(name: "foodLibrary", backend: backend, bus: bus),
            workoutSessions: RecordStore(backend: backend, bus: bus),
            energy: RecordStore(backend: backend, bus: bus),
            energySettings: DocumentStore(name: EnergySettings.documentName, backend: backend, bus: bus),
            // Bookkeeping only: no change events.
            healthSync: DocumentStore(name: "healthSync", backend: backend),
            healthWrites: DocumentStore(name: "healthWrites", backend: backend)
        )
        self.stores = stores
        self.backend = backend
        self.changes = bus
        self.food = StoreFoodLogRepository(store: stores.food)
        self.workouts = StoreWorkoutRepository(store: stores.workouts)
        self.water = StoreWaterRepository(store: stores.water)
        self.weight = StoreWeightRepository(store: stores.weight)
        self.tasks = StoreTaskRepository(store: stores.tasks)
        self.proteinChecklist = StoreProteinChecklistRepository(store: stores.proteinChecklist)
        self.summaries = StoreSummaryRepository(store: stores.summaries)
        self.profile = StoreProfileRepository(store: stores.profile)
        self.foodLibrary = StoreFoodLibraryRepository(store: stores.foodLibrary)
        self.workoutSessions = StoreWorkoutSessionRepository(store: stores.workoutSessions)
        self.energy = StoreEnergyRepository(store: stores.energy)
        self.energySettings = StoreEnergySettingsRepository(store: stores.energySettings)
        self.healthSync = StoreHealthSyncStateRepository(store: stores.healthSync)
        self.healthWrites = StoreHealthWriteStateRepository(store: stores.healthWrites)
    }

    /// The on-device store in Application Support.
    public static func live() throws -> LifeOSDatabase {
        LifeOSDatabase(backend: try FileStorageBackend(root: FileStorageBackend.defaultRoot()))
    }

    /// An empty in-memory store for tests, previews and fixtures.
    public static func inMemory() -> LifeOSDatabase {
        LifeOSDatabase(backend: InMemoryStorageBackend())
    }
}

/// Everything in the store, read in one pass. The app preloads this at launch
/// (off the main thread) and serves synchronous reads from memory.
/// At P0 scale (about a year of data) that's a few hundred KB.
public struct DataSnapshot: Sendable {
    public var food: [FoodEntry]
    public var workouts: [WorkoutDay]
    public var water: [WaterDay]
    public var weight: [WeightEntry]
    public var tasks: [TaskItem]
    public var proteinChecklist: [ProteinChecklist]
    public var summaries: [DailySummary]
    public var profile: UserProfile?
    public var foodLibrary: FoodLibrary
    public var workoutSessions: [WorkoutSession]
    public var energy: [EnergyDay]
    public var energySettings: EnergySettings
}

public extension LifeOSDatabase {
    func loadAll() async throws -> DataSnapshot {
        async let food = stores.food.allRecords()
        async let workouts = stores.workouts.allRecords()
        async let water = stores.water.allRecords()
        async let weight = stores.weight.allRecords()
        async let tasks = stores.tasks.allRecords()
        async let protein = stores.proteinChecklist.allRecords()
        async let summaries = stores.summaries.allRecords()
        async let profile = stores.profile.load()
        async let library = stores.foodLibrary.load()
        async let sessions = stores.workoutSessions.allRecords()
        async let energy = stores.energy.allRecords()
        async let settings = stores.energySettings.load()
        return try await DataSnapshot(food: food, workouts: workouts, water: water, weight: weight, tasks: tasks,
                                      proteinChecklist: protein, summaries: summaries, profile: profile,
                                      foodLibrary: library ?? FoodLibrary(), workoutSessions: sessions,
                                      energy: energy, energySettings: settings ?? EnergySettings())
    }
}

/// Deterministic UUIDs from stable inputs, so re-running a migration or
/// re-importing the same reading upserts instead of duplicating.
public enum StableID {
    public static func make(_ parts: String...) -> UUID {
        let digest = SHA256.hash(data: Data(parts.joined(separator: "|").utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5 style (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}
