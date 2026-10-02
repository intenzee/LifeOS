import Foundation

/// One learned correction: what the scanner originally said, what the user says
/// it actually is, and the image fingerprint that lets us recognise the dish
/// again. This is the training signal of the whole learning loop.
struct MealCorrection: Codable, Identifiable, Equatable {
    let id: UUID
    var createdAt: Date
    var updatedAt: Date

    var signature: ImageSignature

    /// What the model predicted (the mistake we're teaching against).
    var originalName: String
    /// The user's ground-truth label.
    var correctedName: String

    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingSize: String

    /// The user's own words when they corrected via text (e.g. "added 4 eggs").
    /// Optional; decoded as nil for older records.
    var note: String?

    /// How many times this correction has been confirmed/repeated. Higher =
    /// more trusted, and it ranks earlier in the few-shot context.
    var reinforcement: Int

    init(id: UUID = UUID(),
         createdAt: Date = Date(),
         updatedAt: Date = Date(),
         signature: ImageSignature,
         originalName: String,
         correctedName: String,
         calories: Double,
         protein: Double,
         carbs: Double,
         fat: Double,
         servingSize: String,
         note: String? = nil,
         reinforcement: Int = 1) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.signature = signature
        self.originalName = originalName
        self.correctedName = correctedName
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingSize = servingSize
        self.note = note
        self.reinforcement = reinforcement
    }
}

/// Durable, on-device store of corrections. JSON in Application Support — no
/// account, no server, no cost. Loaded once into memory and rewritten on change;
/// the volume (a personal correction history) is tiny.
final class CorrectionStore {

    private let fileURL: URL
    private let queue = DispatchQueue(label: "app.lifeos.mealvision.corrections")
    private var cache: [MealCorrection]

    /// Cap so the store and the retrieval scan stay bounded. Least-reinforced,
    /// oldest entries are pruned first.
    private let maxEntries = 500

    init(filename: String = "meal_corrections.json") {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(filename)
        self.cache = Self.load(from: fileURL)
    }

    // MARK: - Access

    var all: [MealCorrection] {
        queue.sync { cache }
    }

    var count: Int {
        queue.sync { cache.count }
    }

    /// Inserts a correction, or reinforces/updates the existing one it matches.
    /// Matching an existing entry (rather than piling up duplicates) is what lets
    /// repeated confirmations strengthen a lesson.
    @discardableResult
    func upsert(_ correction: MealCorrection,
                matching predicate: (MealCorrection, MealCorrection) -> Bool) -> MealCorrection {
        queue.sync {
            if let index = cache.firstIndex(where: { predicate($0, correction) }) {
                var existing = cache[index]
                existing.correctedName = correction.correctedName
                existing.calories = correction.calories
                existing.protein = correction.protein
                existing.carbs = correction.carbs
                existing.fat = correction.fat
                existing.servingSize = correction.servingSize
                existing.originalName = correction.originalName
                if let note = correction.note, !note.isEmpty { existing.note = note }
                existing.reinforcement += 1
                existing.updatedAt = Date()
                // Refresh the signature to the latest sighting.
                existing.signature = correction.signature
                cache[index] = existing
                persist()
                return existing
            } else {
                cache.append(correction)
                prune()
                persist()
                return correction
            }
        }
    }

    func remove(id: UUID) {
        queue.sync {
            cache.removeAll { $0.id == id }
            persist()
        }
    }

    func removeAll() {
        queue.sync {
            cache.removeAll()
            persist()
        }
    }

    // MARK: - Persistence

    private func prune() {
        guard cache.count > maxEntries else { return }
        // Keep the most reinforced, then most recent.
        cache.sort { lhs, rhs in
            if lhs.reinforcement != rhs.reinforcement { return lhs.reinforcement > rhs.reinforcement }
            return lhs.updatedAt > rhs.updatedAt
        }
        cache = Array(cache.prefix(maxEntries))
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(cache)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Non-fatal: a failed write just means this lesson isn't persisted.
        }
    }

    private static func load(from url: URL) -> [MealCorrection] {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([MealCorrection].self, from: data) else {
            return []
        }
        return decoded
    }
}
