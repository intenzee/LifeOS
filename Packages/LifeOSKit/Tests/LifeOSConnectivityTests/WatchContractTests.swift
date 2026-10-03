import Foundation
import Testing
import LifeOSCore
@testable import LifeOSConnectivity

@Suite("Watch contract")
struct WatchContractTests {
    let day = DayKey("2026-10-03")!

    let snapshot = WatchSnapshot(day: DayKey("2026-10-03")!, caloriesConsumed: 1450, calorieLimit: 2100, caloriesBurned: 230, waterGlasses: 5,
                      waterTarget: 8, perfectStreak: 4, currentWeightKg: 78.2, targetWeightKg: 72, steps: 8123,
                      todos: [.init(id: UUID(), title: "Stretch", done: true)],
                      exercises: [Exercise(bodyPart: .chest, name: "Bench Press", setsCompleted: 2)])

    @Test func snapshotRoundTripsThroughWireDictionary() throws {
        let wire = try WatchWire.encode(snapshot)
        #expect(WatchWire.isTyped(wire))
        #expect(wire["lifeos.v"] as? Int == WatchContract.schemaVersion)
        // WatchConnectivity only accepts property-list values.
        #expect(PropertyListSerialization.propertyList(wire, isValidFor: .binary))
        #expect(try WatchWire.decodeSnapshot(wire) == snapshot)
    }

    @Test(arguments: [
        WatchMutation.requestSnapshot,
        .setWater(glasses: 6, day: DayKey("2026-10-03")!),
        .setWeight(kg: 77.9, day: DayKey("2026-10-03")!),
        .toggleTodo(id: UUID(), day: DayKey("2026-10-03")!),
        .setExerciseSets(exerciseID: UUID(), sets: 3, day: DayKey("2026-10-03")!),
        .addExercise(bodyPart: .legs, name: "Squat", maxSets: 4, day: DayKey("2026-10-03")!),
        .addExercise(bodyPart: .abs, name: nil, maxSets: 3, day: DayKey("2026-10-03")!)
    ])
    func mutationsRoundTrip(_ mutation: WatchMutation) throws {
        #expect(try WatchWire.decodeMutation(try WatchWire.encode(mutation)) == mutation)
    }

    @Test func rejectsWrongKindNewerVersionAndJunk() throws {
        let snapshotWire = try WatchWire.encode(snapshot)
        #expect(throws: WatchWireError.wrongKind(expected: "mutation", actual: "snapshot")) {
            try WatchWire.decodeMutation(snapshotWire)
        }
        var future = snapshotWire
        future["lifeos.v"] = WatchContract.schemaVersion + 1
        #expect(throws: WatchWireError.unsupportedVersion(WatchContract.schemaVersion + 1)) {
            try WatchWire.decodeSnapshot(future)
        }
        #expect(throws: WatchWireError.notAWatchMessage) { try WatchWire.decodeSnapshot(["type": "snapshot"]) }
        var corrupt = snapshotWire
        corrupt["lifeos.payload"] = Data("{}".utf8)
        #expect(throws: WatchWireError.self) { try WatchWire.decodeSnapshot(corrupt) }
    }

    @Test func readsLegacyV1Snapshot() throws {
        let id = UUID()
        let legacy: [String: Any] = [
            "type": "snapshot", "date": "2026-10-03", "caloriesConsumed": 1200.0, "calorieLimit": 2000.0,
            "caloriesBurned": 150.0, "waterCount": 4, "waterTarget": 8, "perfectStreak": 2,
            "currentWeight": 80.0, "targetWeight": 75.0, "steps": 5000,
            "todos": [["id": id.uuidString, "title": "Walk", "done": false], ["id": "not-a-uuid"]],
            "exercises": [["id": UUID().uuidString, "bodyPart": "Legs", "name": "", "setsCompleted": 1, "maxSets": 3]]
        ]
        let decoded = try #require(WatchSnapshot(legacyDictionary: legacy))
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.day == day)
        #expect(decoded.waterGlasses == 4 && decoded.steps == 5000)
        #expect(decoded.todos.map(\.id) == [id])
        #expect(decoded.exercises.first?.displayName == "Legs")
        #expect(WatchSnapshot(legacyDictionary: ["type": "other"]) == nil)
    }

    @Test func derivedProgress() {
        #expect(snapshot.caloriesRemaining == 650)
        #expect(abs(snapshot.calorieProgress - 1450.0 / 2100) < 1e-12)
        #expect(snapshot.waterProgress == 0.625)
        #expect(snapshot.todosCompleted == 1)
        #expect(WatchSnapshot.empty(day: day).calorieProgress == 0)
    }

    @Test func v2AdditionsRoundTripAndOlderPayloadsStillDecode() throws {
        var snapshot = WatchSnapshot.empty(day: DayKey("2026-10-03")!)
        snapshot.budgetMode = "measured"
        snapshot.activeKcal = 640
        snapshot.earnedKcal = 190
        snapshot.proteinG = 82
        snapshot.proteinTargetG = 125
        snapshot.presets = [.init(id: "usual-breakfast", name: "Usual breakfast", kcal: 420, proteinG: 24)]
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        snapshot.workoutsToday = [.init(WorkoutSession(dayKey: snapshot.day, start: start,
                                                       end: start.addingTimeInterval(1800), kind: .run,
                                                       activeEnergyKcal: 310, source: .watch))]
        let decoded = try WatchWire.decodeSnapshot(try WatchWire.encode(snapshot))
        #expect(decoded == snapshot)
        #expect(decoded.workoutsToday?.first?.minutes == 30)
        #expect(decoded.workoutsToday?.first?.sourceBadge == "Apple Watch")

        // A payload written before WCH-16 has none of the new keys.
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(WatchSnapshot.empty(day: snapshot.day))) as! [String: Any]
        old.removeValue(forKey: "budgetMode")
        let legacy = try JSONDecoder().decode(WatchSnapshot.self, from: JSONSerialization.data(withJSONObject: old))
        #expect(legacy.workoutsToday == nil)
    }

    @Test func workoutEndedMutationRoundTrips() throws {
        for mutation in [WatchMutation.workoutEnded(day: DayKey("2026-10-03")!),
                         .logPreset(id: "usual-breakfast", day: DayKey("2026-10-03")!)] {
            #expect(try WatchWire.decodeMutation(try WatchWire.encode(mutation)) == mutation)
        }
    }
}
