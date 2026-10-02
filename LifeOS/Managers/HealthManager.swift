import Foundation
import HealthKit
import Combine

final class HealthManager: ObservableObject {
    let healthStore = HKHealthStore()

    /// `nil` until HealthKit answers (or when access is denied). Never a
    /// placeholder number (FND-06).
    @Published var caloriesConsumed: Double?
    @Published var healthWeight: Double?
    @Published var sleepDurationHours: Double = 0.0
    @Published var stepsToday: Double = 0
    @Published var activeEnergyToday: Double = 0

    /// Reflects whether we can actually *write* to HealthKit. HealthKit never
    /// reveals read-grant status (by design), and the `requestAuthorization`
    /// completion's `success` flag only means the user answered the sheet — not
    /// that anything was granted. So we derive this from the real per-type write
    /// (share) authorization status instead of trusting `success`.
    @Published var isAuthorized = false

    /// The body-mass write type, if available.
    private var bodyMassType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .bodyMass)
    }
    /// The active-energy write type, if available.
    private var activeEnergyType: HKQuantityType? {
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)
    }

    /// Recomputes `isAuthorized` from the actual share-authorization status of the
    /// types we write. `.sharingAuthorized` is the only value that means "granted";
    /// `.notDetermined` and `.sharingDenied` both mean we must not assume access.
    func refreshAuthorizationStatus() {
        let statuses = [bodyMassType, activeEnergyType]
            .compactMap { $0 }
            .map { healthStore.authorizationStatus(for: $0) }
        // Authorized only when every write type we depend on is granted.
        let authorized = !statuses.isEmpty && statuses.allSatisfy { $0 == .sharingAuthorized }
        DispatchQueue.main.async { self.isAuthorized = authorized }
    }

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            Log.health.notice("HealthKit not available on this device")
            return
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!
        ]

        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { _, error in
            if let error { Log.health.error("HealthKit authorization error: \(error.localizedDescription, privacy: .public)") }
            DispatchQueue.main.async {
                // Reads are best-effort regardless of the (uninformative) success flag;
                // `isAuthorized` is derived from real write status.
                self.refreshAuthorizationStatus()
                self.fetchTodayCalories()
                self.fetchLatestWeight()
                self.fetchLastNightSleep()
            }
        }
    }

    func fetchTodayCalories() {
        guard let calorieType = HKQuantityType.quantityType(forIdentifier: .dietaryEnergyConsumed) else { return }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: calorieType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            guard let result = result, let sum = result.sumQuantity() else { return }

            let calories = sum.doubleValue(for: HKUnit.kilocalorie())
            DispatchQueue.main.async {
                self.caloriesConsumed = calories
            }
        }

        healthStore.execute(query)
    }

    func fetchLatestWeight() {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let query = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            guard let sample = samples?.first as? HKQuantitySample else { return }

            let weight = sample.quantity.doubleValue(for: HKUnit.gramUnit(with: .kilo))
            DispatchQueue.main.async {
                self.healthWeight = weight
            }
        }

        healthStore.execute(query)
    }

    func saveWeight(_ weight: Double) {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return }

        let quantity = HKQuantity(unit: HKUnit.gramUnit(with: .kilo), doubleValue: weight)
        let sample = HKQuantitySample(type: weightType, quantity: quantity, start: Date(), end: Date())

        healthStore.save(sample) { success, _ in
            if success {
                DispatchQueue.main.async {
                    self.healthWeight = weight
                }
            }
        }
    }
}

extension HealthManager {
    /// Deletes today's active-energy samples **written by LifeOS only**. Samples
    /// from Apple Watch or other apps are never touched (FND-07). HealthKit
    /// refuses to delete them anyway, which used to abort the whole save.
    func deleteTodaysWorkoutSamples(completion: @escaping (Bool) -> Void) {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(false)
            return
        }

        let today = DayKey.today()
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForSamples(withStart: today.startDate(), end: today.endDate(), options: .strictStartDate),
            HKQuery.predicateForObjects(from: HKSource.default())
        ])

        let query = HKSampleQuery(sampleType: energyType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            if let error {
                Log.health.error("Querying own energy samples failed: \(error.localizedDescription, privacy: .public)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard let samples, !samples.isEmpty else {
                DispatchQueue.main.async { completion(true) }
                return
            }

            self.healthStore.delete(samples) { success, error in
                DispatchQueue.main.async {
                    if !success {
                        Log.health.error("Deleting own energy samples failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                    }
                    completion(success)
                }
            }
        }

        healthStore.execute(query)
    }

    /// Writes the MET *estimate* of workout energy to Apple Health.
    ///
    /// Disabled by default (`FeatureFlag.healthKitEstimatedEnergyWrite`): on top of
    /// Apple Watch data it double-counts Activity rings, and HealthKit's terms
    /// forbid writing inaccurate data. Doc 02 replaces it with real `HKWorkout` writes.
    func saveWorkoutCalories(_ calories: Double, workoutType: HKWorkoutActivityType = .traditionalStrengthTraining) {
        guard FeatureFlags.shared.isEnabled(.healthKitEstimatedEnergyWrite) else { return }
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }

        deleteTodaysWorkoutSamples { success in
            guard success else { return }

            let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: calories)
            let now = Date()
            let sample = HKQuantitySample(type: energyType, quantity: quantity, start: now.addingTimeInterval(-3600), end: now)

            self.healthStore.save(sample) { success, error in
                if !success {
                    Log.health.error("Saving estimated energy failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
                }
            }
        }
    }

    func requestFullAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            Log.health.notice("HealthKit not available on this device")
            return
        }

        var readTypes: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        ]
        if let steps = HKObjectType.quantityType(forIdentifier: .stepCount) {
            readTypes.insert(steps)
        }

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        healthStore.requestAuthorization(toShare: typesToWrite, read: readTypes) { _, error in
            if let error { Log.health.error("HealthKit authorization error: \(error.localizedDescription, privacy: .public)") }
            DispatchQueue.main.async {
                self.refreshAuthorizationStatus()
                self.fetchTodayCalories()
                self.fetchLatestWeight()
                self.fetchLastNightSleep()
                self.fetchTodaySteps()
                self.fetchTodayActiveEnergy()
            }
        }
    }

    /// Total step count since midnight.
    func fetchTodaySteps() {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return }
        let start = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let query = HKStatisticsQuery(quantityType: stepType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            let steps = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
            DispatchQueue.main.async { self.stepsToday = steps }
        }
        healthStore.execute(query)
    }

    /// Total active energy (kcal) burned since midnight.
    func fetchTodayActiveEnergy() {
        fetchWalkingCalories { [weak self] kcal in
            self?.activeEnergyToday = kcal
        }
    }

    /// Daily body-mass history (kg) for the last `days` days, oldest first.
    func fetchWeightHistory(days: Int = 90, completion: @escaping ([(date: Date, weightKg: Double)]) -> Void) {
        guard let weightType = HKQuantityType.quantityType(forIdentifier: .bodyMass) else {
            completion([]); return
        }
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end) else {
            completion([]); return
        }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
        let query = HKSampleQuery(sampleType: weightType, predicate: predicate,
                                  limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
            let points: [(Date, Double)] = (samples as? [HKQuantitySample] ?? []).map {
                ($0.endDate, $0.quantity.doubleValue(for: .gramUnit(with: .kilo)))
            }
            DispatchQueue.main.async { completion(points) }
        }
        healthStore.execute(query)
    }

    func fetchWalkingCalories(completion: @escaping (Double) -> Void) {
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(0)
            return
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)

        let query = HKStatisticsQuery(quantityType: activeEnergyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, _ in
            guard let result = result, let sum = result.sumQuantity() else {
                completion(0)
                return
            }

            let calories = sum.doubleValue(for: HKUnit.kilocalorie())
            DispatchQueue.main.async {
                completion(calories)
            }
        }

        healthStore.execute(query)
    }

    func fetchLastNightSleep() {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
        
        // From yesterday evening to now
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Calendar.current.startOfDay(for: now))!
        let endOfToday = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        
        let predicate = HKQuery.predicateForSamples(withStart: yesterday, end: endOfToday, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        
        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sortDescriptor]) { _, samples, _ in
            guard let samples = samples as? [HKCategorySample] else { return }
            
            // Filter for actual sleep (asleepUnspecified, asleepCore, asleepDeep, asleepREM)
            let sleepSamples = samples.filter { sample in
                sample.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue ||
                sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue ||
                sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue
            }
            
            let totalSleepSeconds = sleepSamples.reduce(0.0) { result, sample in
                result + sample.endDate.timeIntervalSince(sample.startDate)
            }
            
            DispatchQueue.main.async {
                self.sleepDurationHours = totalSleepSeconds / 3600.0
            }
        }
        
        healthStore.execute(query)
    }
}