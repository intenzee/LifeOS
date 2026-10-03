import Foundation
import LifeOSData

// `MealCorrection`, `ImageSignature` and `CorrectionLibrary` (the upsert and
// pruning rules) live in LifeOSCore since FOOD-14.

/// The meal scanner's learned corrections, kept in the LifeOSData store
/// (`documents/mealCorrections.json`).
/// Reads are synchronous, from memory. The first launch after the update moves
/// the old `meal_corrections.json` across with every id intact; the AI memory
/// index keys photo corrections as "correction.<uuid>".
final class CorrectionStore {
    private let repository: any MealCorrectionRepository
    private var library = CorrectionLibrary()
    /// Changes made before the first load finished; replayed on top of it.
    private var pending: [(inout CorrectionLibrary) -> Void] = []
    private var loaded = false
    /// A store that couldn't be read is never overwritten.
    private var readFailed = false
    private var writeTail: Task<Void, Never>?

    /// `repository` defaults to the app's store.
    init(repository: (any MealCorrectionRepository)? = nil, legacyFile: URL? = CorrectionMigrator.legacyURL()) {
        self.repository = repository ?? LocalStore.shared.database.mealCorrections
        Task { await self.load(legacyFile: legacyFile) }
    }

    // MARK: - Access

    var all: [MealCorrection] { library.corrections }

    var count: Int { library.corrections.count }

    /// Inserts a correction, or reinforces the existing one `predicate` matches.
    @discardableResult
    func upsert(_ correction: MealCorrection,
                matching predicate: @escaping (MealCorrection, MealCorrection) -> Bool) -> MealCorrection {
        let now = Date()
        return apply { $0.upsert(correction, now: now, matching: predicate) }
    }

    func remove(id: UUID) {
        apply { $0.remove(id: id) }
    }

    func removeAll() {
        apply { $0 = CorrectionLibrary() }
    }

    // MARK: - Persistence

    @discardableResult
    private func apply<T>(_ change: @escaping (inout CorrectionLibrary) -> T) -> T {
        let result = change(&library)
        if loaded {
            persist()
        } else {
            pending.append { _ = change(&$0) }
        }
        return result
    }

    private func load(legacyFile: URL?) async {
        do {
            let outcome = try await CorrectionMigrator.run(legacyFile: legacyFile, into: repository)
            switch outcome {
            case .migrated(let count): Log.food.info("Moved \(count) meal corrections into the store")
            case .unreadable: Log.food.error("meal_corrections.json is unreadable; left in place")
            case .alreadyMigrated, .noLegacyFile: break
            }
            library = try await repository.load()
        } catch {
            readFailed = true
            Log.food.error("Meal corrections unavailable: \(error.localizedDescription, privacy: .public)")
        }
        loaded = true
        let replay = pending
        pending = []
        for change in replay { change(&library) }
        if !replay.isEmpty { persist() }
    }

    /// Saves in order; each save writes the whole (small) library.
    private func persist() {
        guard !readFailed else { return }
        let snapshot = library
        let previous = writeTail
        writeTail = Task { [repository] in
            await previous?.value
            do {
                try await repository.save(snapshot)
            } catch {
                // Non-fatal: this lesson just isn't persisted.
                Log.food.error("Saving meal corrections failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
