import Foundation
import Combine
import LifeOSData

/// Owns the on-device store (LifeOSData) for the app's lifetime.
///
/// At launch, `bootstrap()`:
/// 1. migrates the legacy UserDefaults blobs once (backup first, verified),
/// 2. reads every collection off the main thread, and
/// 3. hands the data to the managers, which serve the views' synchronous reads.
///
/// Writes go through `enqueue`, a serial queue, so they reach disk in the order
/// they were made, never on the main thread (FND-15). The UI waits behind a
/// launch screen until `phase == .ready`.
@MainActor
final class LocalStore: ObservableObject {
    static let shared = LocalStore()

    enum Phase: Equatable {
        case loading
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase = .loading
    let database: LifeOSDatabase

    private let writes: AsyncStream<@Sendable () async throws -> Void>.Continuation

    init(database: LifeOSDatabase? = nil) {
        if let database {
            self.database = database
        } else {
            do {
                self.database = try LifeOSDatabase.live()
            } catch {
                // Can't create Application Support. Keep the app usable but say so in logs.
                Log.data.fault("Live store unavailable, using memory: \(String(describing: error), privacy: .public)")
                self.database = .inMemory()
            }
        }
        let (stream, continuation) = AsyncStream.makeStream(of: (@Sendable () async throws -> Void).self)
        self.writes = continuation
        Task.detached(priority: .utility) {
            for await write in stream {
                do {
                    try await write()
                } catch {
                    Log.data.error("Store write failed: \(String(describing: error), privacy: .private)")
                }
            }
        }
    }

    /// Queues a write. Writes run one at a time, in order.
    func enqueue(_ write: @escaping @Sendable () async throws -> Void) {
        writes.yield(write)
    }

    /// Safe to call from several places at once (the launch screen and a
    /// HealthKit background launch): later callers wait for the first run.
    func bootstrap() async {
        if let bootstrapping {
            await bootstrapping.value
            return
        }
        let run = Task { await performBootstrap() }
        bootstrapping = run
        await run.value
        bootstrapping = nil
    }

    private var bootstrapping: Task<Void, Never>?

    private func performBootstrap() async {
        guard phase != .ready else { return }
        phase = .loading
        let database = self.database
        let legacy = LegacySnapshot.capture(from: .standard)
        do {
            let outcome = try await LegacyMigrator(database: database).run(snapshot: legacy)
            if case .migrated(let report) = outcome {
                Log.data.notice("Migrated legacy data: \(report.counts.description, privacy: .public), skipped \(report.skipped.description, privacy: .public)")
            }
            let snapshot = try await database.loadAll()
            apply(snapshot)
            phase = .ready
        } catch {
            Log.data.fault("Store bootstrap failed: \(String(describing: error), privacy: .private)")
            phase = .failed((error as? AppError)?.userMessage ?? "Your data couldn't be loaded.")
        }
    }

    private func apply(_ snapshot: DataSnapshot) {
        PersistenceManager.shared.load(from: snapshot, store: self)
        FoodDatabaseManager.shared.load(from: snapshot, store: self)
        WorkoutDatabaseManager.shared.load(from: snapshot, store: self)
        StreakManager.shared.load(from: snapshot, store: self)
        HealthSync.shared.load(from: snapshot)
    }
}

// MARK: - Legacy model bridges

extension DayWorkout {
    init(_ day: WorkoutDay) {
        self.init(exercises: day.exercises, treadmillDone: day.treadmillDone, treadmillDuration: day.treadmillMinutes)
    }

    func record(on day: DayKey) -> WorkoutDay {
        WorkoutDay(dayKey: day, exercises: exercises, treadmillDone: treadmillDone, treadmillMinutes: treadmillDuration)
    }
}

extension FoodItem {
    init(_ entry: FoodEntry) {
        self.init(id: entry.id, name: entry.name, calories: entry.calories, protein: entry.proteinG,
                  carbs: entry.carbsG, fat: entry.fatG, servingSize: entry.servingDescription,
                  barcode: entry.barcode, mealType: entry.meal, timestamp: entry.loggedAt)
    }

    init(_ template: FoodTemplate) {
        self.init(id: template.id, name: template.name, calories: template.calories, protein: template.protein,
                  carbs: template.carbs, fat: template.fat, servingSize: template.servingSize,
                  barcode: template.barcode, mealType: template.defaultMeal)
    }

    func entry(on day: DayKey) -> FoodEntry {
        FoodEntry(id: id, dayKey: day, loggedAt: timestamp, meal: mealType, name: name,
                  servingDescription: servingSize, calories: calories, proteinG: protein, carbsG: carbs, fatG: fat,
                  barcode: barcode, source: barcode == nil ? .manual : .barcode)
    }

    var template: FoodTemplate {
        FoodTemplate(id: id, name: name, calories: calories, protein: protein, carbs: carbs, fat: fat,
                     servingSize: servingSize, barcode: barcode, defaultMeal: mealType)
    }
}

/// Weekday names used by the week pickers. They mean "that day in the current
/// Monday-first week", resolved to a real date before anything is stored.
enum WeekDays {
    static let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    static func dayKey(for name: String, today: DayKey = .today()) -> DayKey? {
        LegacyWeekdayName.dayKey(for: name, inWeekOf: today)
    }

    /// English name → date for the current week.
    static func currentWeek(today: DayKey = .today()) -> [(name: String, day: DayKey)] {
        let monday = today.startOfWeek(firstWeekday: .monday)
        return names.enumerated().map { ($0.element, monday.adding(days: $0.offset)) }
    }
}
