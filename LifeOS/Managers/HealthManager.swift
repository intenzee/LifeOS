import Foundation
import HealthKit
import Combine

final class HealthManager: ObservableObject {
    let healthStore = HKHealthStore()

    @Published var caloriesConsumed: Double = 1450
    @Published var healthWeight: Double = 72.5
    @Published var isAuthorized = false

    func requestAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit not available")
            return
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!
        ]

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!
        ]

        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, _ in
            DispatchQueue.main.async {
                self.isAuthorized = success
                if success {
                    self.fetchTodayCalories()
                    self.fetchLatestWeight()
                }
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
    func deleteTodaysWorkoutSamples(completion: @escaping (Bool) -> Void) {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(false)
            return
        }

        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!

        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)

        let query = HKSampleQuery(sampleType: energyType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
            if let error = error {
                print("❌ Error querying samples: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(false) }
                return
            }

            guard let samples = samples, !samples.isEmpty else {
                print("ℹ️ No existing workout samples to delete")
                DispatchQueue.main.async { completion(true) }
                return
            }

            self.healthStore.delete(samples) { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("✅ Deleted \(samples.count) old workout samples from Apple Health")
                    } else {
                        print("❌ Failed to delete samples: \(error?.localizedDescription ?? "Unknown error")")
                    }
                    completion(success)
                }
            }
        }

        healthStore.execute(query)
    }

    func saveWorkoutCalories(_ calories: Double, workoutType: HKWorkoutActivityType = .traditionalStrengthTraining) {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }

        deleteTodaysWorkoutSamples { success in
            guard success else {
                print("❌ Could not delete old samples, aborting save")
                return
            }

            let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: calories)
            let now = Date()
            let sample = HKQuantitySample(type: energyType, quantity: quantity, start: now.addingTimeInterval(-3600), end: now)

            self.healthStore.save(sample) { success, error in
                if success {
                    print("✅ Saved \(Int(calories)) calories to Apple Health")
                } else {
                    print("❌ Failed to save calories: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }
    }

    func requestFullAuthorization() {
        guard HKHealthStore.isHealthDataAvailable() else {
            print("HealthKit not available")
            return
        }

        let typesToRead: Set<HKObjectType> = [
            HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!,
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        let typesToWrite: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, _ in
            DispatchQueue.main.async {
                self.isAuthorized = success
                if success {
                    self.fetchTodayCalories()
                    self.fetchLatestWeight()
                }
            }
        }
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
}