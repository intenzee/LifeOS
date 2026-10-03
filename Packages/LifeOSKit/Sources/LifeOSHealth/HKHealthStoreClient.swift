#if canImport(HealthKit) && (os(iOS) || os(watchOS))
import Foundation
import HealthKit
import LifeOSCore

/// The live `HealthStoreClient` over `HKHealthStore` (WCH-02/03/04).
public final class HKHealthStoreClient: HealthStoreClient, @unchecked Sendable {
    /// HealthKit gives a background wake about 30 s; finish well before that.
    public static let observerDeadline: Duration = .seconds(25)

    public let store: HKHealthStore
    private let lock = NSLock()
    private var observers: [HKObserverQuery] = []

    public init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    public var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    // MARK: Types

    static let workoutType = HKObjectType.workoutType()
    static let activeEnergy = HKQuantityType(.activeEnergyBurned)
    static let basalEnergy = HKQuantityType(.basalEnergyBurned)
    static let steps = HKQuantityType(.stepCount)
    static let heartRate = HKQuantityType(.heartRate)
    static let distanceWalkingRunning = HKQuantityType(.distanceWalkingRunning)
    static let distanceCycling = HKQuantityType(.distanceCycling)
    static let distanceSwimming = HKQuantityType(.distanceSwimming)

    /// Everything the ingestion pipeline reads.
    public static let readTypes: Set<HKObjectType> = [
        workoutType, activeEnergy, basalEnergy, steps, heartRate, distanceWalkingRunning, distanceCycling,
        distanceSwimming
    ]

    public func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    // MARK: Workouts (WCH-02)

    public func workoutChanges(since anchor: Data?, initialStart: Date) async throws -> WorkoutChanges {
        let queryAnchor = try anchor.flatMap {
            try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
        }
        let notOurs = NSCompoundPredicate(notPredicateWithSubpredicate: HKQuery.predicateForObjects(from: .default()))
        var subpredicates: [NSPredicate] = [notOurs]
        if queryAnchor == nil {
            subpredicates.append(HKQuery.predicateForSamples(withStart: initialStart, end: nil, options: .strictStartDate))
        }
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: Self.workoutType, predicate: predicate, anchor: queryAnchor,
                                              limit: HKObjectQueryNoLimit) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let added = (samples as? [HKWorkout] ?? []).map(Self.sample(from:))
                let archived = newAnchor.flatMap {
                    try? NSKeyedArchiver.archivedData(withRootObject: $0, requiringSecureCoding: true)
                }
                continuation.resume(returning: WorkoutChanges(added: added, deleted: (deleted ?? []).map(\.uuid),
                                                              anchor: archived))
            }
            store.execute(query)
        }
    }

    static func sample(from workout: HKWorkout) -> HealthWorkoutSample {
        let kcal = workout.statistics(for: activeEnergy)?.sumQuantity()?.doubleValue(for: .kilocalorie())
        let distanceType: HKQuantityType? = switch workout.workoutActivityType {
        case .cycling: distanceCycling
        case .swimming: distanceSwimming
        case .running, .walking, .hiking: distanceWalkingRunning
        default: nil
        }
        let distance = distanceType.flatMap { workout.statistics(for: $0)?.sumQuantity()?.doubleValue(for: .meter()) }
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let heart = workout.statistics(for: heartRate)?.averageQuantity()?.doubleValue(for: bpm)
        let source = workout.sourceRevision
        let isWatch = workout.device?.model == "Watch" || (source.productType ?? "").hasPrefix("Watch")
        return HealthWorkoutSample(uuid: workout.uuid, start: workout.startDate, end: workout.endDate,
                                   kind: kind(for: workout.workoutActivityType), activeEnergyKcal: kcal,
                                   distanceMeters: distance, avgHeartRate: heart, sourceName: source.source.name,
                                   sourceBundleID: source.source.bundleIdentifier, recordedByWatch: isWatch)
    }

    static func kind(for type: HKWorkoutActivityType) -> ActivityKind {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining, .coreTraining, .crossTraining:
            return .strength
        case .highIntensityIntervalTraining, .mixedCardio, .jumpRope, .kickboxing:
            return .hiit
        case .running: return .run
        case .walking, .hiking: return .walk
        case .cycling, .handCycling: return .cycle
        case .yoga, .pilates, .flexibility, .mindAndBody: return .yoga
        case .swimming, .waterFitness: return .swim
        default: return .other
        }
    }

    // MARK: Energy statistics (WCH-03)

    public func dailyEnergy(for days: [DayKey], timeZone: TimeZone) async throws -> [DailyEnergyStat] {
        guard let first = days.min(), let last = days.max() else { return [] }
        let start = first.startDate(timeZone: timeZone), end = last.endDate(timeZone: timeZone)
        let watchOnly = HKQuery.predicateForObjects(withDeviceProperty: HKDevicePropertyKeyModel, allowedValues: ["Watch"])

        async let active = sums(Self.activeEnergy, unit: .kilocalorie(), from: start, to: end, timeZone: timeZone)
        async let basal = sums(Self.basalEnergy, unit: .kilocalorie(), from: start, to: end, timeZone: timeZone)
        async let watch = sums(Self.activeEnergy, unit: .kilocalorie(), from: start, to: end, timeZone: timeZone,
                               extra: watchOnly)
        async let steps = sums(Self.steps, unit: .count(), from: start, to: end, timeZone: timeZone)
        let (activeSums, basalSums, watchSums, stepSums) = try await (active, basal, watch, steps)

        return days.map { day in
            DailyEnergyStat(dayKey: day, activeKcal: activeSums[day], basalKcal: basalSums[day],
                            watchActiveKcal: watchSums[day], steps: stepSums[day])
        }
    }

    /// Daily cumulative sums keyed by day. A day with no samples is absent (not 0),
    /// so "no data" stays distinguishable from "sat still". Missing authorization
    /// reads as no data, as HealthKit intends.
    private func sums(_ type: HKQuantityType, unit: HKUnit, from start: Date, to end: Date, timeZone: TimeZone,
                      extra: NSPredicate? = nil) async throws -> [DayKey: Double] {
        var predicate: NSPredicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        if let extra { predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, extra]) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: predicate,
                                                    options: .cumulativeSum, anchorDate: start,
                                                    intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    if (error as? HKError)?.code == .errorNoData { continuation.resume(returning: [:]); return }
                    continuation.resume(throwing: error)
                    return
                }
                var result: [DayKey: Double] = [:]
                collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        result[DayKey.make(for: statistics.startDate, timeZone: timeZone)] = sum.doubleValue(for: unit)
                    }
                }
                continuation.resume(returning: result)
            }
            store.execute(query)
        }
    }

    // MARK: Observers + background delivery (WCH-04)

    public func startObserving(_ onUpdate: @escaping @Sendable (ObservedHealthType) async -> Void) async {
        let alreadyStarted = lock.withLock { !observers.isEmpty }
        guard isAvailable, !alreadyStarted else { return }

        let plan: [(ObservedHealthType, HKSampleType, HKUpdateFrequency)] = [
            (.workouts, Self.workoutType, .immediate),
            (.activeEnergy, Self.activeEnergy, .hourly),
            (.basalEnergy, Self.basalEnergy, .hourly),
            (.steps, Self.steps, .hourly)
        ]
        for (kind, type, frequency) in plan {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if let error {
                    Log.health.error("Observer \(kind.rawValue, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                    completion()
                    return
                }
                // HealthKit stops waking us if `completion` isn't called, so it is
                // called exactly once: when the work finishes or the deadline passes.
                let once = CompletionOnce(completion)
                Task {
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask { await onUpdate(kind) }
                        group.addTask { try? await Task.sleep(for: Self.observerDeadline) }
                        await group.next()
                        once.call()
                        group.cancelAll()
                    }
                }
            }
            lock.withLock { observers.append(query) }
            store.execute(query)
            do {
                try await store.enableBackgroundDelivery(for: type, frequency: frequency)
            } catch {
                // Missing entitlement or authorization: foreground sync still covers it.
                let reason = error.localizedDescription
                Log.health.error("Background delivery for \(kind.rawValue, privacy: .public) unavailable: \(reason, privacy: .public)")
            }
        }
    }
}

// MARK: - Food and water write-back (WCH-08)

extension HKHealthStoreClient: HealthWriteClient {
    /// Metadata key holding the write id on every sample LifeOS saves.
    public static let writeIDKey = "LifeOSWriteID"

    static let dietaryEnergy = HKQuantityType(.dietaryEnergyConsumed)
    static let protein = HKQuantityType(.dietaryProtein)
    static let carbs = HKQuantityType(.dietaryCarbohydrates)
    static let fat = HKQuantityType(.dietaryFatTotal)
    static let water = HKQuantityType(.dietaryWater)
    static let foodCorrelation = HKCorrelationType(.food)

    /// Types LifeOS writes. Correlations aren't authorized themselves: their
    /// contents are.
    public static let writeTypes: Set<HKSampleType> = [dietaryEnergy, protein, carbs, fat, water]

    public func requestWriteAuthorization() async throws {
        try await store.requestAuthorization(toShare: Self.writeTypes, read: [])
    }

    public func canWrite(_ kind: HealthWriteKind) -> Bool {
        switch kind {
        case .food: allowed(Self.dietaryEnergy)
        case .water: allowed(Self.water)
        }
    }

    public func save(food: [NutritionSample], water: [WaterSample]) async throws {
        var objects: [HKObject] = food.compactMap(correlation(for:))
        for sample in water {
            objects.append(HKQuantitySample(type: Self.water, quantity: HKQuantity(unit: .literUnit(with: .milli),
                                                                                    doubleValue: sample.ml),
                                            start: sample.date, end: sample.date,
                                            metadata: [Self.writeIDKey: sample.id.uuidString]))
        }
        guard !objects.isEmpty else { return }
        try await store.save(objects)
    }

    public func deleteSamples(writeIDs: [UUID]) async throws {
        guard !writeIDs.isEmpty else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.writeIDKey,
                                                    allowedValues: writeIDs.map(\.uuidString))
        // Deleting a correlation leaves its samples, so both go. Only types the
        // user lets LifeOS write can hold LifeOS samples.
        _ = try? await store.deleteObjects(of: Self.foodCorrelation, predicate: predicate)
        for type in Self.writeTypes where allowed(type) {
            _ = try await store.deleteObjects(of: type, predicate: predicate)
        }
    }

    private func allowed(_ type: HKObjectType) -> Bool {
        isAvailable && store.authorizationStatus(for: type) == .sharingAuthorized
    }

    /// Energy always; macros when they're non-zero and allowed.
    private func correlation(for food: NutritionSample) -> HKCorrelation? {
        let metadata: [String: Any] = [Self.writeIDKey: food.id.uuidString, HKMetadataKeyFoodType: food.name]
        let parts: [(HKQuantityType, HKUnit, Double)] = [
            (Self.dietaryEnergy, .kilocalorie(), food.kcal), (Self.protein, .gram(), food.proteinG),
            (Self.carbs, .gram(), food.carbsG), (Self.fat, .gram(), food.fatG)
        ]
        let samples = parts.compactMap { type, unit, value -> HKQuantitySample? in
            guard value > 0 || type == Self.dietaryEnergy, allowed(type) else { return nil }
            return HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value),
                                    start: food.date, end: food.date, metadata: metadata)
        }
        guard !samples.isEmpty else { return nil }
        return HKCorrelation(type: Self.foodCorrelation, start: food.date, end: food.date, objects: Set(samples),
                             metadata: metadata)
    }
}

/// Calls an observer completion handler at most once.
private final class CompletionOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var completion: (() -> Void)?

    init(_ completion: @escaping () -> Void) { self.completion = completion }

    func call() {
        let pending = lock.withLock { () -> (() -> Void)? in
            defer { completion = nil }
            return completion
        }
        pending?()
    }
}
#endif
