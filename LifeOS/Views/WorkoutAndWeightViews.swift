import SwiftUI

// MARK: - Redesigned Gym Week View
struct GymWeekView: View {
    @StateObject private var workoutDatabase = WorkoutDatabaseManager.shared
    @ObservedObject var healthManager: HealthManager
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    let currentWeight: Double
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedDayIndex: Int = 0
    @State private var showAddExercise = false
    @State private var selectedBodyPart: BodyPart = .chest
    @State private var selectedMaxSets: Int = 3
    @State private var showTreadmillTimePicker = false
    @State private var treadmillTime: Double = 20.0

    let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    let dayAbbreviations = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    var currentDay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }

    var currentDayIndex: Int {
        daysOfWeek.firstIndex(of: currentDay) ?? 0
    }

    var selectedDay: String {
        daysOfWeek[selectedDayIndex]
    }

    var selectedWorkout: DayWorkout {
        workoutDatabase.loadWorkoutForDay(selectedDay)
    }

    var selectedCalories: Double {
        workoutDatabase.getCaloriesBurnedForDay(selectedDay, weightKg: currentWeight)
    }

    var intensityPercent: Int {
        // Map calories to a 0–100% intensity scale (450 cal = 100%)
        let maxCalories: Double = 450
        return min(100, Int((selectedCalories / maxCalories) * 100))
    }

    var intensityLevel: String {
        selectedWorkout.intensity(weightKg: currentWeight)
    }

    // Calendar info for the selected day
    var selectedDate: Date {
        let calendar = Calendar.current
        let today = Date()
        let todayIndex = currentDayIndex
        let offset = selectedDayIndex - todayIndex
        return calendar.date(byAdding: .day, value: offset, to: today)!
    }

    var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        return formatter.string(from: selectedDate)
    }

    var weekNumber: Int {
        Calendar.current.component(.weekOfYear, from: selectedDate)
    }

    var body: some View {
        ZStack {
            // Backdrop
            palette.screenBackground
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                    isPresented = false
                }

            VStack(spacing: 0) {
                // Top bar
                topBar
                
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 28) {
                        // Intensity Ring
                        intensityRing

                        // Month + Week selector
                        weekSelector

                        // Active Session card
                        activeSessionCard

                        // Exercises list
                        exercisesSection

                        Spacer(minLength: 100)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }

            // Floating Add button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: { showAddExercise = true }) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.black)
                            .frame(width: 56, height: 56)
                            .background(
                                Circle()
                                    .fill(palette.primaryAccent)
                                    .shadow(color: palette.primaryAccent.opacity(0.4), radius: 12, y: 4)
                            )
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 36)
                }
            }

            // Popups
            if showAddExercise {
                addExerciseSheet
            }

            if showTreadmillTimePicker {
                treadmillSheet
            }
        }
        .onAppear {
            selectedDayIndex = currentDayIndex
            workoutDatabase.checkWeeklyReset()
        }
    }

    // MARK: - Top Bar
    private var topBar: some View {
        HStack {
            Button(action: {
                onDismiss()
                isPresented = false
            }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(palette.textSecondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(palette.surface))
            }

            Spacer()

            Text("FITNESS")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .kerning(2)
                .foregroundColor(palette.primaryAccent)

            Spacer()

            // Placeholder for symmetry
            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Intensity Ring
    private var intensityRing: some View {
        VStack(spacing: 16) {
            ZStack {
                // Outer track
                Circle()
                    .stroke(palette.elevatedSurface, lineWidth: 16)

                // Progress arc
                Circle()
                    .trim(from: 0, to: CGFloat(intensityPercent) / 100)
                    .stroke(
                        palette.primaryAccent,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: palette.primaryAccent.opacity(0.45), radius: 10, x: 0, y: 0)

                // Center label
                VStack(spacing: 4) {
                    Text("INTENSITY")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .kerning(1.5)
                        .foregroundColor(palette.textSecondary)

                    Text("\(intensityPercent)%")
                        .font(.system(size: 38, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 170, height: 170)

            // Recovery chip
            HStack(spacing: 8) {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 11))
                    .foregroundColor(palette.primaryAccent)

                Text(intensityLevel.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .kerning(1)
                    .foregroundColor(palette.textPrimary)

                // Mini bar
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barColor(index: i))
                            .frame(width: 18, height: 5)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(palette.surface)
            )
        }
        .padding(.top, 4)
    }

    private func barColor(index: Int) -> Color {
        let filled: Int
        switch intensityLevel {
        case "High": filled = 4
        case "Medium": filled = 3
        case "Low": filled = 2
        default: filled = 0
        }
        return index < filled ? palette.primaryAccent : palette.elevatedSurface
    }

    // MARK: - Week Selector
    private var weekSelector: some View {
        VStack(spacing: 16) {
            // Month & Week
            HStack {
                Text(monthName)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundColor(palette.textPrimary)

                Spacer()

                Text("Week \(weekNumber)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)
            }

            // Day pills
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    let isSelected = i == selectedDayIndex
                    let isToday = i == currentDayIndex
                    let dayDate = Calendar.current.date(byAdding: .day, value: i - currentDayIndex, to: Date())!
                    let dayNum = Calendar.current.component(.day, from: dayDate)

                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedDayIndex = i
                        }
                    }) {
                        VStack(spacing: 6) {
                            Text(dayAbbreviations[i])
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(isSelected ? .black : palette.textSecondary)

                            Text("\(dayNum)")
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(isSelected ? .black : (isToday ? palette.primaryAccent : palette.textPrimary))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isSelected ? palette.primaryAccent : Color.clear)
                        )
                    }
                }
            }
        }
    }

    // MARK: - Active Session Card
    private var activeSessionCard: some View {
        let workout = selectedWorkout
        let bodyParts = Array(Set(workout.exercises.map { $0.bodyPart.rawValue }))
        let sessionName = bodyParts.isEmpty ? "Rest Day" : bodyParts.prefix(2).joined(separator: " & ")
        let totalSets = workout.exercises.reduce(0) { $0 + $1.setsCompleted }
        let maxSets = workout.exercises.reduce(0) { $0 + $1.maxSets }

        return VStack(alignment: .leading, spacing: 14) {
            // Header row
            HStack {
                Text("ACTIVE SESSION")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(1.2)
                    .foregroundColor(palette.textSecondary)

                Spacer()

                if !workout.exercises.isEmpty || workout.treadmillDone {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(palette.primaryAccent)
                            .frame(width: 6, height: 6)
                        Text("\(totalSets)/\(maxSets) sets")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }

            // Session name
            Text(sessionName)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            // Stats row
            HStack(spacing: 24) {
                // Treadmill
                HStack(spacing: 8) {
                    Image(systemName: "figure.run")
                        .font(.system(size: 14))
                        .foregroundColor(palette.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TREADMILL")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .kerning(0.8)
                            .foregroundColor(palette.textSecondary)
                        Text(workout.treadmillDone ? "\(Int(workout.treadmillDuration)) Min" : "–")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(palette.textPrimary)
                    }
                }
                .onTapGesture {
                    treadmillTime = workout.treadmillDuration
                    showTreadmillTimePicker = true
                }

                // Calories
                HStack(spacing: 8) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 14))
                        .foregroundColor(palette.textSecondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("EST. CALORIES")
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .kerning(0.8)
                            .foregroundColor(palette.textSecondary)
                        Text("\(Int(selectedCalories)) kcal")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundColor(palette.textPrimary)
                    }
                }

                Spacer()

                // Treadmill toggle
                Button(action: {
                    workoutDatabase.toggleTreadmillForDay(selectedDay, durationMinutes: workout.treadmillDuration)
                    syncWorkoutToAppleHealth(day: selectedDay)
                }) {
                    Image(systemName: workout.treadmillDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 22))
                        .foregroundColor(workout.treadmillDone ? palette.primaryAccent : palette.textSecondary)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(
                            selectedDay == currentDay ? palette.primaryAccent.opacity(0.3) : Color.clear,
                            lineWidth: 1
                        )
                )
        )
    }

    // MARK: - Exercises Section
    private var exercisesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Exercises")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            let workout = selectedWorkout

            if workout.exercises.isEmpty {
                emptyExerciseCard
            } else {
                ForEach(workout.exercises) { exercise in
                    exerciseCard(exercise: exercise)
                }
            }
        }
    }

    private var emptyExerciseCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 32))
                .foregroundColor(palette.textSecondary.opacity(0.5))

            Text("No exercises yet")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(palette.textSecondary)

            Text("Tap + to add your first exercise")
                .font(.system(size: 12, weight: .regular, design: .rounded))
                .foregroundColor(palette.textSecondary.opacity(0.7))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(palette.elevatedSurface, style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                )
        )
    }

    private func exerciseCard(exercise: Exercise) -> some View {
        HStack(spacing: 16) {
            // Body part icon
            ZStack {
                Circle()
                    .fill(palette.elevatedSurface)
                    .frame(width: 52, height: 52)

                Image(systemName: iconForBodyPart(exercise.bodyPart))
                    .font(.system(size: 20))
                    .foregroundColor(palette.primaryAccent)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.bodyPart.rawValue)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundColor(palette.textPrimary)

                Text("\(exercise.setsCompleted)/\(exercise.maxSets) Sets")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)
            }

            Spacer()

            // Set cycle button
            Button(action: {
                workoutDatabase.cycleExerciseSetsForDay(selectedDay, exerciseId: exercise.id)
                syncWorkoutToAppleHealth(day: selectedDay)
            }) {
                intensityBadge(for: exercise)
            }

            // Delete
            Button(action: {
                workoutDatabase.deleteExerciseForDay(selectedDay, exerciseId: exercise.id)
                syncWorkoutToAppleHealth(day: selectedDay)
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(palette.textSecondary.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(palette.elevatedSurface))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(palette.surface)
        )
    }

    private func intensityBadge(for exercise: Exercise) -> some View {
        let progress = exercise.maxSets > 0 ? Double(exercise.setsCompleted) / Double(exercise.maxSets) : 0
        let label: String
        let color: Color

        if progress >= 1.0 {
            label = "DONE"
            color = palette.primaryAccent
        } else if progress >= 0.5 {
            label = "MED"
            color = .blue
        } else if progress > 0 {
            label = "LOW"
            color = .orange
        } else {
            label = "START"
            color = palette.textSecondary
        }

        return Text(label)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .kerning(0.5)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(color)
            )
    }

    private func iconForBodyPart(_ bp: BodyPart) -> String {
        switch bp {
        case .chest: return "figure.strengthtraining.traditional"
        case .back: return "figure.rowing"
        case .shoulders: return "figure.boxing"
        case .arms: return "figure.arms.open"
        case .legs: return "figure.walk"
        case .abs: return "figure.core.training"
        case .cardio: return "figure.run"
        }
    }

    // MARK: - Add Exercise Sheet
    private var addExerciseSheet: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { showAddExercise = false }

            VStack(spacing: 20) {
                // Header
                HStack {
                    Text("Add Exercise")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimary)

                    Spacer()

                    Button(action: { showAddExercise = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(palette.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(palette.elevatedSurface))
                    }
                }

                Text(selectedDay)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(palette.primaryAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Body part picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("BODY PART")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .kerning(1)
                        .foregroundColor(palette.textSecondary)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(BodyPart.allCases, id: \.self) { part in
                            Button(action: { selectedBodyPart = part }) {
                                HStack(spacing: 6) {
                                    Image(systemName: iconForBodyPart(part))
                                        .font(.system(size: 12))
                                    Text(part.rawValue)
                                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                                }
                                .foregroundColor(selectedBodyPart == part ? .black : palette.textPrimary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(selectedBodyPart == part ? palette.primaryAccent : palette.elevatedSurface)
                                )
                            }
                        }
                    }
                }

                // Sets picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("MAX SETS")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .kerning(1)
                        .foregroundColor(palette.textSecondary)

                    HStack(spacing: 8) {
                        ForEach(3...6, id: \.self) { sets in
                            Button(action: { selectedMaxSets = sets }) {
                                Text("\(sets)")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .foregroundColor(selectedMaxSets == sets ? .black : palette.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(selectedMaxSets == sets ? palette.primaryAccent : palette.elevatedSurface)
                                    )
                            }
                        }
                    }
                }

                // Add button
                Button(action: {
                    let newExercise = Exercise(bodyPart: selectedBodyPart, setsCompleted: 0, maxSets: selectedMaxSets)
                    workoutDatabase.addExerciseForDay(selectedDay, exercise: newExercise)
                    syncWorkoutToAppleHealth(day: selectedDay)
                    showAddExercise = false
                }) {
                    Text("Add Exercise")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(palette.primaryAccent)
                        )
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(palette.surface)
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            )
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Treadmill Sheet
    private var treadmillSheet: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { showTreadmillTimePicker = false }

            VStack(spacing: 20) {
                HStack {
                    Text("Treadmill")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                    Spacer()
                    Button(action: { showTreadmillTimePicker = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(palette.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(palette.elevatedSurface))
                    }
                }

                Text(selectedDay)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(palette.primaryAccent)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Duration display
                VStack(spacing: 4) {
                    Text("\(Int(treadmillTime))")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("minutes")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(palette.textSecondary)
                }

                // Slider
                VStack(spacing: 8) {
                    Slider(value: $treadmillTime, in: 5...60, step: 5)
                        .tint(palette.primaryAccent)

                    HStack {
                        Text("5")
                        Spacer()
                        Text("30")
                        Spacer()
                        Text("60")
                    }
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)
                }

                // Calories estimate
                HStack {
                    Image(systemName: "flame.fill")
                        .foregroundColor(palette.primaryAccent)
                    Text("\(Int(CalorieCalculator.treadmillCalories(weightKg: currentWeight, durationMinutes: treadmillTime))) cal estimated")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(palette.textSecondary)
                }

                // Log button
                Button(action: {
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
                }) {
                    Text("Log Workout")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(palette.primaryAccent)
                        )
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(palette.surface)
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            )
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Helpers
    private func syncWorkoutToAppleHealth(day: String) {
        let workout = workoutDatabase.loadWorkoutForDay(day)
        let totalBurned = CalorieCalculator.totalWorkoutCalories(workout: workout, weightKg: currentWeight)
        if day == currentDay && healthManager.isAuthorized {
            healthManager.saveWorkoutCalories(totalBurned)
        }
    }
}

// MARK: - Weight Picker (unchanged)
struct WeightPickerView: View {
    @Binding var currentWeight: Double
    @Binding var targetWeight: Double
    @Binding var isPresented: Bool
    @ObservedObject var healthManager: HealthManager
    let onSave: () -> Void

    @State private var tempCurrent: Double
    @State private var tempTarget: Double
    @State private var syncWithHealth: Bool = true
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

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
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture { isPresented = false }

            VStack(spacing: 20) {
                HStack {
                    Text("Weight")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(palette.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(palette.elevatedSurface))
                    }
                }

                currentWeightField
                targetWeightField

                if healthManager.isAuthorized {
                    healthSyncToggle
                }

                weightRemainingText

                saveButton
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 28)
                    .fill(palette.surface)
                    .shadow(color: .black.opacity(0.4), radius: 30, y: 10)
            )
            .padding(.horizontal, 24)
        }
    }

    private var currentWeightField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CURRENT WEIGHT")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(1)
                .foregroundColor(palette.textSecondary)

            HStack {
                TextField("", value: $tempCurrent, format: .number)
                    .keyboardType(.decimalPad)
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(palette.elevatedSurface)
                    )

                Text("kg")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)
            }
        }
    }

    private var targetWeightField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TARGET WEIGHT")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .kerning(1)
                .foregroundColor(palette.textSecondary)

            HStack {
                TextField("", value: $tempTarget, format: .number)
                    .keyboardType(.decimalPad)
                    .foregroundColor(.white)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(palette.elevatedSurface)
                    )

                Text("kg")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(palette.textSecondary)
            }
        }
    }

    private var healthSyncToggle: some View {
        HStack {
            Text("Sync with Apple Health")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(palette.textPrimary)

            Spacer()

            Toggle("", isOn: $syncWithHealth)
                .labelsHidden()
                .tint(palette.primaryAccent)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var weightRemainingText: some View {
        if weightRemaining > 0 {
            HStack {
                Text("\(String(format: "%.1f", weightRemaining)) kg left to go")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(.orange)
                Spacer()
            }
        } else if weightRemaining < 0 {
            HStack {
                Text("Target achieved! \(String(format: "%.1f", abs(weightRemaining))) kg below")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(palette.primaryAccent)
                Spacer()
            }
        } else {
            HStack {
                Text("Target achieved!")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundColor(palette.primaryAccent)
                Spacer()
            }
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
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(palette.primaryAccent)
                )
        }
    }
}
