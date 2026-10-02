import Foundation
import Testing
@testable import LifeOSAI

@Suite("SchemaValidator")
struct SchemaValidatorTests {

    @Test("Valid JSON decodes; prose and code fences around it are tolerated")
    func decodesWrapped() throws {
        let raw = "Sure! Here you go:\n```json\n\(Fixtures.parsedMealJSON)\n```"
        let meal = try SchemaValidator.decode(raw, as: ParsedMeal.self).get()
        #expect(meal.items.count == 2)
        #expect(meal.items[0].quantity == 2)
        #expect(meal.refersToPreset == false)
    }

    @Test("Braces inside string values don't end the object early")
    func stringAwareIsolation() {
        let text = #"noise {"name":"curly {brace} dal","quantity":1} trailing"#
        #expect(SchemaValidator.isolateJSONObject(text) == #"{"name":"curly {brace} dal","quantity":1}"#)
    }

    @Test("Conservative coercions: numeric strings, ranges, clamping, enum case, extra keys, lone item")
    func coercions() throws {
        let raw = #"""
        {"items":{"name":"Roti","quantity":"2 pcs","unit":"piece","extra":"x"},
         "mealType":"LUNCH","refersToPreset":"no"}
        """#
        let meal = try SchemaValidator.decode(raw, as: ParsedMeal.self).get()
        #expect(meal.items.count == 1)
        #expect(meal.items[0].quantity == 2)
        #expect(meal.mealType == .lunch)
        #expect(meal.refersToPreset == false)

        #expect(SchemaValidator.numericValue(.string("200-300 kcal")) == 250)
        #expect(SchemaValidator.numericValue(.string("~1,200")) == 1200)
        #expect(SchemaValidator.numericValue(.string("lots")) == nil)

        let clamped = try SchemaValidator.decode(#"{"items":[{"name":"rice","quantity":90000,"unit":"g"}],"mealType":"dinner"}"#,
                                                 as: ParsedMeal.self).get()
        #expect(clamped.items[0].quantity == 5_000)
    }

    @Test("Failures list precise, repairable issues")
    func failures() {
        guard case .failure(let failure) = SchemaValidator.decode(#"{"items":[{"quantity":1}],"mealType":"brunch"}"#,
                                                                 as: ParsedMeal.self) else {
            Issue.record("expected failure"); return
        }
        #expect(failure.issues.contains("$.items[0].name is required"))
        #expect(failure.issues.contains { $0.hasPrefix("$.mealType must be one of") })
        #expect(failure.repairFeedback.contains("Return a corrected JSON object only."))

        guard case .failure(let notJSON) = SchemaValidator.decode("I can't help with that", as: ParsedMeal.self) else {
            Issue.record("expected failure"); return
        }
        #expect(notJSON.issues == ["response is not valid JSON"])
    }

    @Test("Semantic checks reject empty meal estimates unless a local engine vouches for them")
    func semantic() throws {
        guard case .failure(let failure) = SchemaValidator.decode(#"{"name":"Plate","calories":0}"#, as: MealPhotoEstimate.self) else {
            Issue.record("expected failure"); return
        }
        #expect(failure.issues == ["estimate has no calories or macros"])
        let local = try SchemaValidator.decode(#"{"name":"Kimchi","calories":0,"confidence":0.4}"#, as: MealPhotoEstimate.self).get()
        #expect(local.displayName == "Kimchi")
    }

    @Test("Meal estimate totals: explicit totals win, otherwise items are summed")
    func mealTotals() throws {
        let itemised = try SchemaValidator.decode(#"{"items":[{"name":"rice","calories":300,"protein":6},{"name":"","calories":999},{"name":"egg","calories":70,"protein":6}]}"#,
                                                  as: MealPhotoEstimate.self).get()
        #expect(itemised.namedItems.count == 2)
        #expect(itemised.totals.calories == 370)
        #expect(itemised.totals.protein == 12)
        #expect(itemised.displayName == "Meal")
        #expect(itemised.displayServing == "1 plate")
    }

    @Test("Plain-text outputs accept prose or {text:…}")
    func plainText() throws {
        #expect(try SchemaValidator.decode("  Drink water.  ", as: AIText.self).get().text == "Drink water.")
        #expect(try SchemaValidator.decode(#"{"text":"Hi"}"#, as: AIText.self).get().text == "Hi")
        #expect(throws: SchemaValidator.Failure.self) { try SchemaValidator.decode("   ", as: AIText.self).get() }
    }
}

@Suite("AISchema rendering")
struct AISchemaTests {

    @Test("JSON Schema lists required fields, enums and ranges")
    func jsonSchema() throws {
        let rendered = ParsedMeal.schema.jsonSchema().serialized()
        let object = try #require(JSONValue.parse(rendered))
        #expect(object["type"] == .string("object"))
        #expect(object["required"] == .array([.string("items"), .string("mealType")]))
        #expect(object["additionalProperties"] == .bool(false))
        let quantity = object["properties"]?["items"]?["items"]?["properties"]?["quantity"]
        #expect(quantity?["minimum"] == .number(0))
        #expect(quantity?["maximum"] == .number(5_000))
        #expect(object["properties"]?["mealType"]?["enum"] == .array(ParsedMeal.MealSlot.allCases.map { .string($0.rawValue) }))
        #expect(ParsedMeal.schema.promptInstruction().contains("JSON Schema"))
    }

    @Test("Gemini schema uses OpenAPI types and property ordering")
    func geminiSchema() {
        let schema = ParsedMeal.schema.geminiSchema()
        #expect(schema["type"] == .string("OBJECT"))
        #expect(schema["propertyOrdering"] == .array(["items", "mealType", "statedTime", "refersToPreset", "presetPhrase"].map { .string($0) }))
        #expect(schema["properties"]?["items"]?["type"] == .string("ARRAY"))
        #expect(schema["properties"]?["mealType"]?["format"] == .string("enum"))
        #expect(schema["additionalProperties"] == nil)
    }

    @Test("JSONValue serialises deterministically and escapes safely")
    func serialisation() {
        let value = JSONValue.object([.init("b", .number(1)), .init("a", .string("quote\" newline\n")), .init("n", .null),
                                      .init("f", .number(0.25)), .init("l", .array([.bool(true)]))])
        #expect(value.serialized() == #"{"b":1,"a":"quote\" newline\n","n":null,"f":0.25,"l":[true]}"#)
        #expect(JSONValue.parse(value.serialized()) != nil)
        #expect(value.serialized(pretty: true).contains("\n  \"b\": 1"))
    }

    #if canImport(FoundationModels)
    @Test("Every output schema converts to a valid Apple GenerationSchema (unique nested names)")
    func appleSchemaConversion() throws {
        guard #available(macOS 26.0, iOS 26.0, *) else { return }
        _ = try AppleFMRunner.generationSchema(for: ParsedMeal.schema)
        _ = try AppleFMRunner.generationSchema(for: MealPhotoEstimate.schema)
        _ = try AppleFMRunner.generationSchema(for: AIText.schema)
    }
    #endif
}

@Suite("Remote config")
struct RemoteConfigTests {

    @Test("Partial config falls back to defaults; unknown providers are dropped")
    func partialDecode() throws {
        let json = #"{"ai":{"groqVisionModels":["new/vision-1"],"flags":{"photoAppleVision":true},"routing":{"foodTextParse":["deterministic","quantumModel"]},"disabledProviders":["applePCC","nope"]}}"#
        let config = try AIRemoteConfig.decode(from: Data(json.utf8))
        #expect(config.groqVisionModels == ["new/vision-1"])
        #expect(config.geminiModels == AIRemoteConfig.default.geminiModels)
        #expect(config.flags.photoAppleVision)
        #expect(config.flags.pccEnabled == AIRemoteConfig.Flags.default.pccEnabled)
        #expect(config.routing["foodTextParse"] == [.deterministic])
        #expect(config.disabledProviders == [.applePCC])
        #expect(config.quotaLimits[.groqBYOK]?.perMinute == 25)
    }

    @Test("Bare `ai` object and empty lists are handled")
    func bareObject() throws {
        let config = try AIRemoteConfig.decode(from: Data(#"{"groqVisionModels":[],"promptVersion":"x"}"#.utf8))
        #expect(config.groqVisionModels == AIRemoteConfig.default.groqVisionModels)
        #expect(config.promptVersion == "x")
    }

    @Test("Routing table honours feature flags")
    func flaggedRouting() {
        var config = AIRemoteConfig.default
        #expect(RoutingTable.v1.chain(for: .mealPhotoAnalyze, config: config) == [.groqBYOK, .visionLegacy])
        config.flags.photoAppleVision = true
        #expect(RoutingTable.v1.chain(for: .mealPhotoAnalyze, config: config)
                == [.appleOnDevice, .applePCC, .geminiBYOK, .groqBYOK, .visionLegacy])
        config.flags.pccEnabled = false
        #expect(!RoutingTable.v1.chain(for: .foodTextParse, config: config).contains(.applePCC))
        #expect(RoutingTable.v1.chain(for: .memoryExtract, config: config) == [.appleOnDevice])
    }

    @Test("Store fetches, caches to disk, and survives a failed refresh")
    func storeFetchAndCache() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cfg-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let cacheURL = dir.appendingPathComponent("config.json")
        let (session, _) = StubURLProtocol.session { _ in (200, Data(#"{"ai":{"geminiModels":["g-next"]}}"#.utf8)) }
        let store = AIRemoteConfigStore(remoteURL: URL(string: "https://config.example/ai.json"), cacheURL: cacheURL, session: session)
        #expect(await store.refreshIfStale().geminiModels == ["g-next"])

        let (failing, _) = StubURLProtocol.session { _ in (500, Data()) }
        let restarted = AIRemoteConfigStore(remoteURL: URL(string: "https://config.example/ai.json"), cacheURL: cacheURL, session: failing)
        #expect(await restarted.current.geminiModels == ["g-next"], "cached copy loads at launch")
        #expect(await restarted.refreshIfStale(force: true).geminiModels == ["g-next"], "failed fetch keeps last good")
    }
}
