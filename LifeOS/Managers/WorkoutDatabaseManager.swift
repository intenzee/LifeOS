import Foundation
import Combine

final class WorkoutDatabaseManager: ObservableObject {
    static let shared = WorkoutDatabaseManager()

    @Published var allDailyWorkouts: [String: DayWorkout] = [:]
    @Published var selectedDate: Date = Date()
    private let allDailyWorkoutsKey = "allDailyWorkouts"

    private init() {
        loadAllWorkouts()
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        objectWillChange.send()
    }

    var dailyWorkout: DayWorkout {
        let dayName = dayNameFromDate(selectedDate)
        return loadWorkoutForDay(dayName)
    }

    func getTotalCaloriesBurned(weight: Double) -> Double {
        let dayName = dayNameFromDate(selectedDate)
        return getCaloriesBurnedForDay(dayName, weightKg: weight)
    }

    private func dayNameFromDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    func getCaloriesBurnedForDay(_ day: String, weightKg: Double) -> Double {
        let workout = loadWorkoutForDay(day)
        return CalorieCalculator.totalWorkoutCalories(workout: workout, weightKg: weightKg)
    }

    func checkWeeklyReset() {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)

        if weekday == 2 {
            let lastSundayKey = dayToDateKey("Sunday")
            allDailyWorkouts.removeValue(forKey: lastSundayKey)
            saveAllWorkouts()
        }
    }

    func loadWorkoutForDay(_ day: String) -> DayWorkout {
        let dateKey = dayToDateKey(day)
        return allDailyWorkouts[dateKey] ?? DayWorkout()
    }

    func toggleTreadmillForDay(_ day: String, durationMinutes: Double) {
        let dateKey = dayToDateKey(day)
        var workout = allDailyWorkouts[dateKey] ?? DayWorkout()
        workout.treadmillDone.toggle()
        workout.treadmillDuration = durationMinutes
        allDailyWorkouts[dateKey] = workout
        saveAllWorkouts()
    }

    func cycleExerciseSetsForDay(_ day: String, exerciseId: UUID) {
        let dateKey = dayToDateKey(day)
        var workout = allDailyWorkouts[dateKey] ?? DayWorkout()

        if let index = workout.exercises.firstIndex(where: { $0.id == exerciseId }) {
            let current = workout.exercises[index].setsCompleted
            let max = workout.exercises[index].maxSets
            workout.exercises[index].setsCompleted = (current + 1) % (max + 1)
        }

        allDailyWorkouts[dateKey] = workout
        saveAllWorkouts()
    }

    func deleteExerciseForDay(_ day: String, exerciseId: UUID) {
        let dateKey = dayToDateKey(day)
        var workout = allDailyWorkouts[dateKey] ?? DayWorkout()
        workout.exercises.removeAll { $0.id == exerciseId }
        allDailyWorkouts[dateKey] = workout
        saveAllWorkouts()
    }

    func addExerciseForDay(_ day: String, exercise: Exercise) {
        let dateKey = dayToDateKey(day)
        var workout = allDailyWorkouts[dateKey] ?? DayWorkout()
        workout.exercises.append(exercise)
        allDailyWorkouts[dateKey] = workout
        saveAllWorkouts()
    }

    func dayToDateKeyPublic(_ dayName: String) -> String {
        dayToDateKey(dayName)
    }

    func saveAllWorkoutsPublic() {
        saveAllWorkouts()
    }

    private func dayToDateKey(_ dayName: String) -> String {
        let calendar = Calendar.current
        let today = Date()
        let todayWeekday = calendar.component(.weekday, from: today)
        let todayIndex = (todayWeekday + 5) % 7

        let dayIndex: Int
        switch dayName {
        case "Monday": dayIndex = 0
        case "Tuesday": dayIndex = 1
        case "Wednesday": dayIndex = 2
        case "Thursday": dayIndex = 3
        case "Friday": dayIndex = 4
        case "Saturday": dayIndex = 5
        case "Sunday": dayIndex = 6
        default: dayIndex = 0
        }

        let daysOffset = dayIndex - todayIndex
        let targetDate = calendar.date(byAdding: .day, value: daysOffset, to: today)!

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: targetDate)
    }

    private func saveAllWorkouts() {
        if let encoded = try? JSONEncoder().encode(allDailyWorkouts) {
            UserDefaults.standard.set(encoded, forKey: allDailyWorkoutsKey)
        }
        objectWillChange.send()
    }

    private func loadAllWorkouts() {
        guard let data = UserDefaults.standard.data(forKey: allDailyWorkoutsKey),
              let decoded = try? JSONDecoder().decode([String: DayWorkout].self, from: data) else {
            return
        }
        allDailyWorkouts = decoded
    }
}