import Foundation

// The meal scanner's learned corrections (FOOD-14), moved from the app's
// `CorrectionStore` JSON file into the LifeOSData store. Field names are
// unchanged, so the legacy file decodes as-is and every id survives: the AI
// memory index keys photo corrections as "correction.<uuid>".

/// A comparable fingerprint of a meal photo. Built in the app
/// (`ImageSignatureBuilder`, Vision); stored here as plain data.
public struct ImageSignature: Codable, Sendable, Equatable, Hashable {
    /// 64-bit average hash of an 8×8 luminance thumbnail.
    public let pHash: UInt64
    /// Archived `VNFeaturePrintObservation`. `nil` when Vision failed.
    public let featurePrintData: Data?

    public init(pHash: UInt64, featurePrintData: Data?) {
        self.pHash = pHash
        self.featurePrintData = featurePrintData
    }
}

/// One learned correction: what the scanner said, what the user says it is,
/// and the photo fingerprint that lets the scanner recognise the dish again.
public struct MealCorrection: Codable, Sendable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public var createdAt: Date
    public var updatedAt: Date

    public var signature: ImageSignature

    /// What the model predicted (the mistake being taught against).
    public var originalName: String
    /// The user's ground-truth label.
    public var correctedName: String

    public var calories: Double
    public var protein: Double
    public var carbs: Double
    public var fat: Double
    public var servingSize: String

    /// The user's own words when they corrected by text. `nil` in older records.
    public var note: String?

    /// How often this correction was confirmed. Higher ranks earlier as a hint.
    public var reinforcement: Int

    public init(id: UUID = UUID(), createdAt: Date = Date(), updatedAt: Date = Date(), signature: ImageSignature,
                originalName: String, correctedName: String, calories: Double, protein: Double, carbs: Double,
                fat: Double, servingSize: String, note: String? = nil, reinforcement: Int = 1) {
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

/// Every correction, stored as one document (a personal history is small).
public struct CorrectionLibrary: Codable, Sendable, Equatable {
    public static let documentName = "mealCorrections"
    /// Least-reinforced, then oldest, entries are pruned beyond this.
    public static let maxEntries = 500

    public var corrections: [MealCorrection]

    public init(corrections: [MealCorrection] = []) {
        self.corrections = corrections
    }

    /// Inserts `correction`, or reinforces the existing entry `predicate`
    /// matches: repeated confirmations strengthen a lesson instead of piling up
    /// duplicates. The existing entry keeps its id.
    @discardableResult
    public mutating func upsert(_ correction: MealCorrection, now: Date = Date(),
                                matching predicate: (MealCorrection, MealCorrection) -> Bool) -> MealCorrection {
        guard let index = corrections.firstIndex(where: { predicate($0, correction) }) else {
            corrections.append(correction)
            prune()
            return correction
        }
        var existing = corrections[index]
        existing.correctedName = correction.correctedName
        existing.calories = correction.calories
        existing.protein = correction.protein
        existing.carbs = correction.carbs
        existing.fat = correction.fat
        existing.servingSize = correction.servingSize
        existing.originalName = correction.originalName
        if let note = correction.note, !note.isEmpty { existing.note = note }
        existing.reinforcement += 1
        existing.updatedAt = now
        // The latest sighting's fingerprint.
        existing.signature = correction.signature
        corrections[index] = existing
        return existing
    }

    public mutating func remove(id: UUID) {
        corrections.removeAll { $0.id == id }
    }

    private mutating func prune() {
        guard corrections.count > Self.maxEntries else { return }
        corrections.sort { lhs, rhs in
            if lhs.reinforcement != rhs.reinforcement { return lhs.reinforcement > rhs.reinforcement }
            return lhs.updatedAt > rhs.updatedAt
        }
        corrections = Array(corrections.prefix(Self.maxEntries))
    }
}
