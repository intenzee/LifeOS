import Foundation
import Testing
@testable import LifeOSAI

@Suite("Photo schema v2 → nutrition resolver")
struct PhotoV2Tests {

    @Test("Catalog foods use catalog nutrition at the model's grams; unknown foods keep the model's estimate")
    func resolution() throws {
        let analysis = try SchemaValidator.decode(#"""
        {"mealName":"veg thali","notFood":false,"items":[
          {"name":"roti","estimatedGrams":80,"householdMeasure":"2 pieces","identificationConfidence":0.95,"kcal":200},
          {"name":"dal makhani","estimatedGrams":150,"identificationConfidence":0.8,"kcal":250},
          {"name":"mystery pickle chutney thing","estimatedGrams":20,"identificationConfidence":0.4,"kcal":35,"fat":3}
        ]}
        """#, as: PhotoMealAnalysis.self).get()

        let items = PhotoMealResolver.resolve(analysis)
        #expect(items.count == 3)
        #expect(items[0].sourceRef.hasSuffix(":roti") && abs(items[0].macros.kcal - 237.6) < 0.5)
        #expect(items[0].servingDescription == "80 g")
        #expect(items[1].macros.kcal == 225)
        #expect(items[2].matchKind == .modelEstimate && items[2].macros.kcal == 35)
        // Honest confidence: identification × match × single-view portion factor.
        #expect(abs(items[0].confidence - 0.95 * 0.9 * 0.75) < 0.001)
        #expect(PhotoMealResolver.confidence(items) < 0.6)
    }

    @Test("Validation: notFood is a valid answer; empty or weightless items are not")
    func validation() {
        #expect((try? SchemaValidator.decode(#"{"mealName":"","items":[],"notFood":true}"#, as: PhotoMealAnalysis.self).get()) != nil)
        guard case .failure(let empty) = SchemaValidator.decode(#"{"mealName":"x","items":[],"notFood":false}"#, as: PhotoMealAnalysis.self) else {
            Issue.record("expected failure"); return
        }
        #expect(empty.issues.first?.contains("no items") == true)
    }

    @Test("v2 schema converts to Apple guided generation and Gemini schema")
    func schemas() throws {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, iOS 26.0, *) { _ = try AppleFMRunner.generationSchema(for: PhotoMealAnalysis.schema) }
        #endif
        #expect(PhotoMealAnalysis.schema.geminiSchema()["properties"]?["items"]?["type"] == .string("ARRAY"))
        #expect(PromptRegistry.mealPhotoAnalyzeV2().embedsSchema == false, "REST providers append the JSON schema")
    }

    @Test("Photo v2 is on by default and can be switched off remotely")
    func flag() throws {
        #expect(AIRemoteConfig.default.flags.photoSchemaV2)
        let off = try AIRemoteConfig.decode(from: Data(#"{"flags":{"photoSchemaV2":false}}"#.utf8))
        #expect(!off.flags.photoSchemaV2)
    }
}

@Suite("Barcode offline cache")
struct BarcodeCacheTests {
    @Test("Stores, normalises EAN/UPC, persists and evicts")
    func cache() async {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("barcodes-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let cache = BarcodeCache(url: url, capacity: 2)
        let product = BarcodeCache.Product(name: "Parle-G", per100g: Macros(kcal: 455, protein: 6.5, carbs: 77, fat: 13.5),
                                           servingDescription: "100g", cachedAt: Date(timeIntervalSince1970: 1))
        await cache.store(product, for: "0012345678905")
        #expect(await cache.product(for: "012345678905")?.name == "Parle-G")
        #expect(await BarcodeCache(url: url).product(for: "0012345678905")?.per100g.kcal == 455)
        var newer = product
        newer.cachedAt = Date()
        await cache.store(newer, for: "111")
        await cache.store(newer, for: "222")
        #expect(await cache.count == 2)
        #expect(await cache.product(for: "012345678905") == nil, "oldest evicted")
    }
}
