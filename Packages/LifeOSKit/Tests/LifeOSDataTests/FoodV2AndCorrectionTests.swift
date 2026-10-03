import Foundation
import Testing
@testable import LifeOSCore
@testable import LifeOSData

@Suite("FoodEntry v2 (FOOD-01)")
struct FoodEntryV2Tests {
    @Test func v1RecordsDecodeWithEmptyV2Fields() throws {
        let entry = FoodEntry(dayKey: DayKey("2026-10-03")!, loggedAt: Date(timeIntervalSince1970: 0),
                              meal: .lunch, name: "Dal", calories: 220, source: .manual)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        // What a v1 shard holds: none of the new keys.
        for key in ["fiberG", "sugarG", "sodiumMg", "presetID", "photoAssetID", "nutritionSourceRef", "grams"] {
            object.removeValue(forKey: key)
        }
        let decoded = try JSONDecoder().decode(FoodEntry.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == entry)
        #expect(decoded.fiberG == nil && decoded.presetID == nil && decoded.nutritionSourceRef == nil)
    }

    @Test func v2FieldsRoundTripThroughTheStore() async throws {
        let db = LifeOSDatabase.inMemory()
        let day = DayKey("2026-10-03")!
        let preset = UUID()
        let entry = FoodEntry(dayKey: day, loggedAt: Date(), meal: .breakfast, name: "Roti", calories: 120,
                              source: .photoAI, confidence: 0.8, fiberG: 2.7, sugarG: 0.4, sodiumMg: 190,
                              presetID: preset, photoAssetID: "photo-1",
                              nutritionSourceRef: "db:lifeos-curated-v1:roti", grams: 40)
        try await db.food.save(entry)
        let stored = try #require(try await db.food.entries(on: day).first)
        #expect(stored == entry)
        #expect(stored.presetID == preset && stored.grams == 40)
    }
}

@Suite("Meal corrections (FOOD-14)")
struct MealCorrectionTests {
    /// Written by the app's old `CorrectionStore` (default `JSONEncoder`):
    /// dates as seconds since 2001, `note` absent in older records.
    static let legacyJSON = """
    [{"id":"6F1C2A4E-8B1D-4C55-9A57-1D1F7C2B9E01","createdAt":780000000,"updatedAt":780000100,\
    "signature":{"pHash":18446744073709551615,"featurePrintData":"AQID"},"originalName":"Fried rice",\
    "correctedName":"Egg fried rice","calories":520,"protein":18,"carbs":70,"fat":17,\
    "servingSize":"1 plate","reinforcement":3},
    {"id":"0B7E9D3C-2F64-4A0E-B1C8-5E2D7A9F4C12","createdAt":780500000,"updatedAt":780500000,\
    "signature":{"pHash":42},"originalName":"Curry","correctedName":"Dal makhani","calories":350,\
    "protein":12,"carbs":30,"fat":20,"servingSize":"1 bowl","note":"added butter","reinforcement":1}]
    """

    func legacyFile(_ contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(CorrectionMigrator.legacyFilename)
        try Data(contents.utf8).write(to: url)
        return url
    }

    @Test func migratesTheLegacyFileLosslesslyOnce() async throws {
        let db = LifeOSDatabase.inMemory()
        let url = try legacyFile(Self.legacyJSON)
        let outcome = try await CorrectionMigrator.run(legacyFile: url, into: db.mealCorrections)
        #expect(outcome == .migrated(count: 2))

        let library = try await db.mealCorrections.load()
        let rice = try #require(library.corrections.first)
        #expect(rice.id == UUID(uuidString: "6F1C2A4E-8B1D-4C55-9A57-1D1F7C2B9E01"))
        #expect(rice.signature == ImageSignature(pHash: .max, featurePrintData: Data([1, 2, 3])))
        #expect(rice.createdAt == Date(timeIntervalSinceReferenceDate: 780_000_000))
        #expect(rice.note == nil && rice.reinforcement == 3)
        #expect(library.corrections[1].note == "added butter")
        #expect(library.corrections[1].signature.featurePrintData == nil)

        // The old file is kept, renamed.
        #expect(!FileManager.default.fileExists(atPath: url.path))
        let retired = url.deletingLastPathComponent().appendingPathComponent(CorrectionMigrator.migratedFilename)
        #expect(FileManager.default.fileExists(atPath: retired.path))

        #expect(try await CorrectionMigrator.run(legacyFile: url, into: db.mealCorrections) == .alreadyMigrated)
    }

    @Test func anUnreadableFileIsLeftAloneAndNothingIsWritten() async throws {
        let db = LifeOSDatabase.inMemory()
        let url = try legacyFile("{ not json")
        #expect(try await CorrectionMigrator.run(legacyFile: url, into: db.mealCorrections) == .unreadable)
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(try await db.mealCorrections.exists() == false)
        #expect(try await CorrectionMigrator.run(legacyFile: nil, into: db.mealCorrections) == .noLegacyFile)
    }

    @Test func anInterruptedRunOnlyRetiresTheFile() async throws {
        let db = LifeOSDatabase.inMemory()
        try await db.mealCorrections.save(CorrectionLibrary())
        let url = try legacyFile(Self.legacyJSON)
        #expect(try await CorrectionMigrator.run(legacyFile: url, into: db.mealCorrections) == .alreadyMigrated)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try await db.mealCorrections.load().corrections.isEmpty)
    }

    func correction(_ name: String, hash: UInt64, reinforcement: Int = 1, updated: TimeInterval = 0) -> MealCorrection {
        MealCorrection(createdAt: Date(timeIntervalSince1970: updated), updatedAt: Date(timeIntervalSince1970: updated),
                       signature: ImageSignature(pHash: hash, featurePrintData: nil), originalName: "x",
                       correctedName: name, calories: 100, protein: 1, carbs: 1, fat: 1, servingSize: "1",
                       reinforcement: reinforcement)
    }

    @Test func reinforcingKeepsTheIdAndTheOldNote() {
        var library = CorrectionLibrary()
        let first = library.upsert(correction("Poha", hash: 1)) { _, _ in false }
        var again = correction("Poha", hash: 2)
        again.calories = 250
        let now = Date(timeIntervalSince1970: 99)
        let merged = library.upsert(again, now: now) { $0.correctedName == $1.correctedName }
        #expect(library.corrections.count == 1)
        #expect(merged.id == first.id)
        #expect(merged.reinforcement == 2 && merged.calories == 250 && merged.signature.pHash == 2)
        #expect(merged.updatedAt == now)

        library.remove(id: first.id)
        #expect(library.corrections.isEmpty)
    }

    @Test func prunesTheWeakestOldestBeyondTheCap() {
        var library = CorrectionLibrary(corrections: (0..<CorrectionLibrary.maxEntries).map {
            correction("c\($0)", hash: UInt64($0), reinforcement: $0 == 0 ? 1 : 2, updated: Double($0))
        })
        let keeper = library.corrections[0].id
        library.upsert(correction("new", hash: 9_999, reinforcement: 1, updated: 10_000)) { _, _ in false }
        #expect(library.corrections.count == CorrectionLibrary.maxEntries)
        // Both weakest (reinforcement 1): the older one goes.
        #expect(!library.corrections.contains { $0.id == keeper })
        #expect(library.corrections.contains { $0.correctedName == "new" })
    }
}
