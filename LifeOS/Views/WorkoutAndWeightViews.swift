import SwiftUI

struct GymWeekView: View {
    @StateObject private var workoutDatabase = WorkoutDatabaseManager.shared
    @ObservedObject var healthManager: HealthManager
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    let currentWeight: Double

    @State private var selectedBodyPart: BodyPart = .chest
    @State private var selectedMaxSets: Int = 3
    @State private var showAddExercise = false
    @State private var selectedDay: String = ""
    @State private var showTreadmillTimePicker = false
    @State private var treadmillTime: Double = 20.0

    let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var currentDay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                    isPresented = false
                }

            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
                        Text("Weekly Workout")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)

                        Text("Today: \(Int(workoutDatabase.getCaloriesBurnedForDay(currentDay, weightKg: currentWeight))) cal burned")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    VStack(spacing: 16) {
                        ForEach(daysOfWeek, id: \.self) { day in
                            dayCard(for: day)
                        }
                    }

                    Button(action: {
                        onDismiss()
                        isPresented = false
                    }) {
                        Text("Done")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                }
                .padding(24)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .padding(.horizontal, 32)
            .padding(.vertical, 60)

            if showAddExercise {
                addExercisePopup
            }

            if showTreadmillTimePicker {
                treadmillTimePicker
            }
        }
        .onAppear {
            workoutDatabase.checkWeeklyReset()
        }
    }

    private func dayCard(for day: String) -> some View {
        let workout = workoutDatabase.loadWorkoutForDay(day)
        let caloriesBurned = workoutDatabase.getCaloriesBurnedForDay(day, weightKg: currentWeight)
        let intensityLevel = workout.intensity(weightKg: currentWeight)

        return VStack(spacing: 12) {
            HStack {
                Text(day)
                    .font(.headline)
                    .foregroundColor(day == currentDay ? .blue : .white)

                if day == currentDay {
                    Text("(Today)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                Spacer()

                VStack(alignment: .trailing) {
                    Text(intensityLevel)
                        .font(.caption)
                        .foregroundColor(intensityColor(for: intensityLevel))
                    Text("\(Int(caloriesBurned)) cal")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.green)
                }

                Button(action: {
                    selectedDay = day
                    showAddExercise = true
                }) {
                    Image(systemName: "plus.circle")
                        .foregroundColor(.blue)
                        .font(.title3)
                }
            }

            HStack(spacing: 0) {
                Button(action: {
                    selectedDay = day
                    treadmillTime = workout.treadmillDuration
                    showTreadmillTimePicker = true
                }) {
                    HStack {
                        Image(systemName: "figure.run")
                            .foregroundColor(.white)
                        VStack(alignment: .leading) {
                            Text("Treadmill")
                                .font(.subheadline)
                                .foregroundColor(.white)
                            Text("\(Int(workout.treadmillDuration)) min • 15% incline")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                    .padding(.leading, 12)
                }

                Button(action: {
                    workoutDatabase.toggleTreadmillForDay(day, durationMinutes: workout.treadmillDuration)
                    syncWorkoutToAppleHealth(day: day)
                }) {
                    Image(systemName: workout.treadmillDone ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(workout.treadmillDone ? .green : .gray)
                        .font(.title3)
                        .frame(width: 50, height: 40)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(workout.treadmillDone ? Color.green.opacity(0.2) : Color.gray.opacity(0.2))
            )

            if workout.exercises.isEmpty {
                Text("No exercises")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(workout.exercises) { exercise in
                        exerciseRow(exercise: exercise, day: day)
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(day == currentDay ? Color.blue.opacity(0.6) : .clear, lineWidth: 2)
                )
        )
    }

    private func exerciseRow(exercise: Exercise, day: String) -> some View {
        HStack {
            Text(exercise.bodyPart.rawValue)
                .foregroundColor(.white)
                .frame(width: 80, alignment: .leading)

            HStack(spacing: 6) {
                ForEach(0..<exercise.maxSets, id: \.self) { i in
                    Circle()
                        .fill(i < exercise.setsCompleted ? Color.green : Color.gray.opacity(0.3))
                        .frame(width: 12, height: 12)
                }
            }

            Spacer()

            Button(action: {
                cycleExerciseSets(day: day, exerciseId: exercise.id)
            }) {
                Text("\(exercise.setsCompleted)/\(exercise.maxSets)")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(6)
            }

            Button(action: {
                deleteExercise(day: day, exerciseId: exercise.id)
            }) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
                    .font(.caption)
            }
        }
    }

    private var addExercisePopup: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("Add Exercise for \(selectedDay)")
                    .font(.headline)
                    .foregroundColor(.white)

                Picker("Body Part", selection: $selectedBodyPart) {
                    ForEach(BodyPart.allCases, id: \.self) { part in
                        Text(part.rawValue).tag(part)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 120)

                HStack {
                    Text("Max Sets")
                        .foregroundColor(.white)
                    Spacer()
                    ForEach(3...6, id: \.self) { sets in
                        Button(action: { selectedMaxSets = sets }) {
                            Text("\(sets)")
                                .fontWeight(selectedMaxSets == sets ? .bold : .regular)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(selectedMaxSets == sets ? Color.blue : Color.gray.opacity(0.3))
                                .cornerRadius(8)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button("Cancel") {
                        showAddExercise = false
                        selectedDay = ""
                    }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .cornerRadius(10)

                    Button("Add") {
                        addExercise(day: selectedDay, bodyPart: selectedBodyPart, maxSets: selectedMaxSets)
                        showAddExercise = false
                        selectedDay = ""
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(10)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .padding(.horizontal, 48)
        }
    }

    private var treadmillTimePicker: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Treadmill for \(selectedDay)")
                    .font(.headline)
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Duration")
                        .font(.subheadline)
                        .foregroundColor(.gray)

                    Text("\(Int(treadmillTime)) minutes")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                }

                VStack {
                    Slider(value: $treadmillTime, in: 5...60, step: 5)
                        .accentColor(.blue)

                    HStack {
                        Text("5 min")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        Text("30 min")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                        Text("60 min")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                Text("Calories: \(Int(CalorieCalculator.treadmillCalories(weightKg: currentWeight, durationMinutes: treadmillTime))) cal")
                    .font(.subheadline)
                    .foregroundColor(.green)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        showTreadmillTimePicker = false
                    }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .cornerRadius(10)

                    Button("Log Workout") {
                        let dateKey = workoutDatabase.dayToDateKeyPublic(selectedDay)
                        var workout = workoutDatabase.allDailyWorkouts[dateKey] ?? DayWorkout()
                        workout.treadmillDuration = treadmillTime

                        if !workout.treadmillDone {
                            workout.treadmillDone = true
                        }

                        workoutDatabase.allDailyWorkouts[dateKey] = workout
                        workoutDatabase.saveAllWorkoutsPublic()

                        syncWorkoutToAppleHealth(day: selectedDay)
                        showTreadmillTimePicker = false
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(10)
                }
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .padding(.horizontal, 40)
        }
    }

    private func cycleExerciseSets(day: String, exerciseId: UUID) {
        workoutDatabase.cycleExerciseSetsForDay(day, exerciseId: exerciseId)
        syncWorkoutToAppleHealth(day: day)
    }

    private func deleteExercise(day: String, exerciseId: UUID) {
        workoutDatabase.deleteExerciseForDay(day, exerciseId: exerciseId)
        syncWorkoutToAppleHealth(day: day)
    }

    private func addExercise(day: String, bodyPart: BodyPart, maxSets: Int) {
        let newExercise = Exercise(bodyPart: bodyPart, setsCompleted: 0, maxSets: maxSets)
        workoutDatabase.addExerciseForDay(day, exercise: newExercise)
        syncWorkoutToAppleHealth(day: day)
    }

    private func syncWorkoutToAppleHealth(day: String) {
        let workout = workoutDatabase.loadWorkoutForDay(day)
        let totalBurned = CalorieCalculator.totalWorkoutCalories(workout: workout, weightKg: currentWeight)
        print("📅 \(day): \(Int(totalBurned)) calories burned")

        if day == currentDay && healthManager.isAuthorized {
            healthManager.saveWorkoutCalories(totalBurned)
        }
    }

    private func intensityColor(for intensity: String) -> Color {
        switch intensity {
        case "High": return .green
        case "Medium": return .blue
        case "Low": return .orange
        default: return .gray
        }
    }
}

struct WeightPickerView: View {
    @Binding var currentWeight: Double
    @Binding var targetWeight: Double
    @Binding var isPresented: Bool
    @ObservedObject var healthManager: HealthManager
    let onSave: () -> Void

    @State private var tempCurrent: Double
    @State private var tempTarget: Double
    @State private var syncWithHealth: Bool = true

    init(currentWeight: Binding<Double>, targetWeight: Binding<Double>, isPresented: Binding<Bool>, healthManager: HealthManager, onSave: @escaping () -> Void) {
        _currentWeight = currentWeight
        _targetWeight = targetWeight
        _isPresented = isPresented
        self.healthManager = healthManager
        self.onSave = onSave
        _tempCurrent = State(initialValue: currentWeight.wrappedValue)
        _tempTarget = State(initialValue: targetWeight.wrappedValue)
    }

    var weightRemaining: Double {
        tempCurrent - tempTarget
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 24) {
                Text("Weight")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                VStack(spacing: 20) {
                    currentWeightField
                    targetWeightField

                    if healthManager.isAuthorized {
                        healthSyncToggle
                    }

                    weightRemainingText
                }

                saveButton
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .padding(.horizontal, 32)
        }
    }

    private var currentWeightField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current Weight")
                .font(.caption)
                .foregroundColor(.gray)

            HStack {
                TextField("", value: $tempCurrent, format: .number)
                    .keyboardType(.decimalPad)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
                    )

                Text("kg")
                    .foregroundColor(.gray)
            }
        }
    }

    private var targetWeightField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Target Weight")
                .font(.caption)
                .foregroundColor(.gray)

            HStack {
                TextField("", value: $tempTarget, format: .number)
                    .keyboardType(.decimalPad)
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
                    )

                Text("kg")
                    .foregroundColor(.gray)
            }
        }
    }

    private var healthSyncToggle: some View {
        HStack {
            Text("Sync with Apple Health")
                .font(.subheadline)
                .foregroundColor(.white)

            Spacer()

            Toggle("", isOn: $syncWithHealth)
                .labelsHidden()
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var weightRemainingText: some View {
        if weightRemaining > 0 {
            HStack {
                Text("\(String(format: "%.1f", weightRemaining)) kg left to go")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                Spacer()
            }
            .padding(.horizontal, 4)
        } else if weightRemaining < 0 {
            HStack {
                Text("Target achieved! \(String(format: "%.1f", abs(weightRemaining))) kg below")
                    .font(.subheadline)
                    .foregroundColor(.green)
                Spacer()
            }
            .padding(.horizontal, 4)
        } else {
            HStack {
                Text("Target achieved!")
                    .font(.subheadline)
                    .foregroundColor(.green)
                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    private var saveButton: some View {
        Button(action: {
            currentWeight = tempCurrent
            targetWeight = tempTarget

            if syncWithHealth && healthManager.isAuthorized {
                healthManager.saveWeight(tempCurrent)
            }

            onSave()
            isPresented = false
        }) {
            Text("Save")
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .cornerRadius(12)
        }
    }
}
