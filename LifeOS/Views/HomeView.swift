import SwiftUI

// MARK: - Home View
struct HomeView: View {
    @ObservedObject var healthManager: HealthManager
    @Environment(\.colorScheme) private var colorScheme
    
    @StateObject private var streakManager = StreakManager.shared
    @StateObject private var foodDatabase = FoodDatabaseManager.shared
    @StateObject private var workoutDatabase = WorkoutDatabaseManager.shared
    @State private var showQuickActions = false
    @State private var showMealDetail = false
    @State private var selectedMeal: MealType = .breakfast
    @State private var showFoodSearch = false
    @State private var showBarcodeScanner = false
    @State private var showAIMealScan = false
    @State private var showBarcodeUnrecognizedPrompt = false
    @State private var showManualBarcodeEntry = false
    @State private var pendingBarcode: String? = nil
    @State private var showProfileHub = false
    @State private var waterCount: Int
    @State private var showPortionSelector = false
    @State private var scannedFood: FoodItem? = nil
    @State private var showDatePicker = false
    
    @State private var currentWeight: Double
    @State private var targetWeight: Double
    @State private var showWeightPicker = false
    @State private var showCurrentWeight = true
    
    @State private var moodIndex: Int
    
    @State private var showFoodWeekView = false
    @State private var showGymWeekView = false
    
    @State private var weekFoodLog: [String: DayMeals]
    @State private var weekTodoList: [String: [TodoItem]]
    @State private var weekGymLog: [String: DayWorkout]
    
    let caloriesLimit = 2200.0
    let cardOrder: [MiniCardType] = [.todo, .gym, .water, .food]

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }
    
    init(healthManager: HealthManager) {
        self.healthManager = healthManager
        let persistence = PersistenceManager.shared
        _waterCount = State(initialValue: persistence.loadWaterCount(for: Date()))
        _currentWeight = State(initialValue: persistence.loadCurrentWeight())
        _targetWeight = State(initialValue: persistence.loadTargetWeight())
        _moodIndex = State(initialValue: persistence.loadMoodIndex())
        _weekFoodLog = State(initialValue: persistence.loadWeekFoodLog())
        _weekTodoList = State(initialValue: persistence.loadWeekTodoList())
        _weekGymLog = State(initialValue: persistence.loadWeekGymLog())
    }
    
    var currentDay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }
    
    var todayMeals: DayMeals {
        weekFoodLog[currentDay] ?? DayMeals()
    }
    
    var todayTodos: [TodoItem] {
        weekTodoList[currentDay] ?? []
    }
    
    var todayTodosCompleted: Int {
        todayTodos.filter { $0.isCompleted }.count
    }
    
    var todayTodosTotal: Int {
        todayTodos.count
    }
    
    var todayWorkout: DayWorkout {
        workoutDatabase.dailyWorkout
    }
    
    var adjustedCalorieLimit: Double {
        let baseLimit = CalorieLimitSettings.shared.loadLimit()
        let caloriesBurned = workoutDatabase.getTotalCaloriesBurned(weight: currentWeight)
        let percentage = CalorieSettings.shared.loadPercentage()
        let adjustment = caloriesBurned * percentage
        return baseLimit + adjustment
    }
    
    var displayDate: String {
        let formatter = DateFormatter()
        if Calendar.current.isDateInToday(foodDatabase.selectedDate) {
            return "Today"
        } else if Calendar.current.isDateInYesterday(foodDatabase.selectedDate) {
            return "Yesterday"
        } else if Calendar.current.isDateInTomorrow(foodDatabase.selectedDate) {
            return "Tomorrow"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: foodDatabase.selectedDate)
        }
    }
    
    var body: some View {
        ZStack {
            palette.screenBackground
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    headerView
                    
                    CaloriesRing(
                        consumed: foodDatabase.dailyLog.totalCalories(),
                        limit: adjustedCalorieLimit,
                        burned: workoutDatabase.getTotalCaloriesBurned(weight: currentWeight)
                    )
                    .padding(.top, 10)
                    .onTapGesture {
                        showMealDetail = true
                    }
                    
                    perfectDayCard

                    DailyProgressContainer(
                        order: cardOrder,
                        waterCount: waterCount,
                        todayTodosCompleted: todayTodosCompleted,
                        todayTodosTotal: todayTodosTotal,
                        currentWeight: currentWeight,
                        targetWeight: targetWeight,
                        showCurrentWeight: showCurrentWeight,
                        todayWorkout: todayWorkout,
                        moodIndex: moodIndex,
                        todayMeals: todayMeals,
                        onCardTap: handleCardTap,
                        onCardLongPress: handleCardLongPress,
                        onWaterChange: { newValue in
                            waterCount = newValue
                            PersistenceManager.shared.saveWaterCount(newValue, for: Date())
                        }
                    )
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
            }
            
            overlays
            
            if shouldShowFloatingActionButton {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showQuickActions = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(.blue)
                                .background(Circle().fill(Color(red: 0.06, green: 0.06, blue: 0.07)).padding(5))
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            
            if showQuickActions {
                QuickActionsMenu(
                    isPresented: $showQuickActions,
                    onAction: handleQuickAction
                )
            }
            
            if showMealDetail {
                MealDetailView(
                    foodLog: $foodDatabase.dailyLog,
                    isPresented: $showMealDetail,
                    selectedDate: foodDatabase.selectedDate,
                    onDateChange: { newDate in
                        foodDatabase.selectDate(newDate)
                    },
                    onAddFood: { meal in
                        selectedMeal = meal
                        showFoodSearch = true
                    }
                )
            }
            
            if showFoodSearch {
                FoodSearchView(
                    isPresented: $showFoodSearch,
                    selectedMeal: selectedMeal,
                    onFoodSelected: { food in
                        foodDatabase.addFood(food)
                    }
                )
            }

            if showBarcodeUnrecognizedPrompt, let barcode = pendingBarcode {
                BarcodeUnrecognizedPromptView(
                    isPresented: $showBarcodeUnrecognizedPrompt,
                    barcode: barcode,
                    onRetryScan: {
                        showBarcodeUnrecognizedPrompt = false
                        showBarcodeScanner = true
                    },
                    onLogManually: {
                        showBarcodeUnrecognizedPrompt = false
                        showManualBarcodeEntry = true
                    }
                )
            }

            if showManualBarcodeEntry {
                CustomFoodView(
                    isPresented: $showManualBarcodeEntry,
                    mealType: selectedMeal,
                    barcode: pendingBarcode,
                    initialFoodName: pendingBarcode == nil ? "" : "Unrecognized Item",
                    initialServingSize: "1 serving",
                    onSave: { food in
                        foodDatabase.addCustomFood(food)
                        foodDatabase.addFood(food)
                        pendingBarcode = nil
                    }
                )
            }

        }
        .sheet(isPresented: $showProfileHub) {
            ProfileHubView(isPresented: $showProfileHub)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            healthManager.requestFullAuthorization()
            workoutDatabase.selectDate(foodDatabase.selectedDate)
            refreshTodoState()
            syncWorkoutToAppleHealth()
            syncStreaks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .weekTodoListDidChange)) { _ in
            refreshTodoState()
            syncStreaks()
        }
        .onChange(of: foodDatabase.selectedDate) { oldValue, newValue in
            workoutDatabase.selectDate(newValue)
            syncStreaks()
        }
        .onChange(of: foodDatabase.dailyLog.totalCalories()) { _, _ in
            syncStreaks()
        }
        .onChange(of: waterCount) { _, _ in
            syncStreaks()
        }
        .onChange(of: currentWeight) { _, _ in
            syncStreaks()
        }
        .onChange(of: todayTodosCompleted) { _, _ in
            syncStreaks()
        }
        .onChange(of: todayTodosTotal) { _, _ in
            syncStreaks()
        }
        .onChange(of: workoutDatabase.getTotalCaloriesBurned(weight: currentWeight)) { _, _ in
            syncStreaks()
        }
    }
    
    private var perfectDayCard: some View {
        let streak = streakManager.perfectDayStreak
        let today = streakManager.summaries[streakManager.dateKey(for: Date())]
        let score = today?.score ?? 0

        return HStack(spacing: 14) {
            Text(streak > 0 ? "🏆" : "🎯")
                .font(.title2)

            VStack(alignment: .leading, spacing: 2) {
                Text("Perfect Day Streak")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(palette.textPrimary)
                Text("Today: \(score)/4 goals hit")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }

            Spacer()

            Text("\(streak)")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(streak > 0 ? .yellow : .gray)

            Text(streak == 1 ? "day" : "days")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(streak > 0 ? Color.yellow.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        )
    }

    private func refreshTodoState() {
        weekTodoList = PersistenceManager.shared.loadWeekTodoList()
    }
    
    private func syncStreaks() {
        let intensity = todayWorkout.intensity(weightKg: currentWeight)
        streakManager.recordToday(
            caloriesConsumed: foodDatabase.dailyLog.totalCalories(),
            calorieLimit: adjustedCalorieLimit,
            waterGlasses: waterCount,
            waterTarget: 8,
            gymIntensity: intensity,
            todosCompleted: todayTodosCompleted,
            todosTotal: todayTodosTotal
        )
    }
    
    private var headerView: some View {
        VStack(spacing: 10) {
            HStack {
                Text(displayDate)
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .foregroundColor(palette.textPrimary)

                Spacer()

                Button(action: { showProfileHub = true }) {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.blue)
                        .padding(6)
                        .background(Circle().fill(palette.surface))
                }
            }

            HStack(spacing: 16) {
                Button(action: {
                    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: foodDatabase.selectedDate)!
                    foodDatabase.selectDate(yesterday)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Previous")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }

                Button(action: { showDatePicker = true }) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text("Pick Date")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }

                Button(action: {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: foodDatabase.selectedDate)!
                    foodDatabase.selectDate(tomorrow)
                }) {
                    HStack(spacing: 4) {
                        Text("Next")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $foodDatabase.selectedDate, isPresented: $showDatePicker)
        }
    }

    private var shouldShowFloatingActionButton: Bool {
        !(showQuickActions || showMealDetail || showFoodSearch || showBarcodeScanner || showAIMealScan || showBarcodeUnrecognizedPrompt || showManualBarcodeEntry || showWeightPicker || showDatePicker || showFoodWeekView || showGymWeekView)
    }
    
    @ViewBuilder
    private var overlays: some View {
        if showWeightPicker {
            WeightPickerView(
                currentWeight: $currentWeight,
                targetWeight: $targetWeight,
                isPresented: $showWeightPicker,
                healthManager: healthManager,
                onSave: {
                    PersistenceManager.shared.saveCurrentWeight(currentWeight)
                    PersistenceManager.shared.saveTargetWeight(targetWeight)
                }
            )
        }
        
        if showFoodWeekView {
            FoodWeekView(
                weekFoodLog: $weekFoodLog,
                currentDay: currentDay,
                isPresented: $showFoodWeekView,
                onDismiss: {
                    PersistenceManager.shared.saveWeekFoodLog(weekFoodLog)
                }
            )
        }
        if showBarcodeScanner {
            BarcodeScannerView(
                isPresented: $showBarcodeScanner,
                selectedMeal: selectedMeal,
                onBarcodeScanned: { barcode in
                    BarcodeFoodLookup.lookup(barcode: barcode) { food in
                        if var scannedFoodItem = food {
                            scannedFoodItem.mealType = selectedMeal
                            scannedFood = scannedFoodItem
                            showBarcodeScanner = false
                            showPortionSelector = true
                        } else {
                            pendingBarcode = barcode
                            showBarcodeScanner = false
                            showBarcodeUnrecognizedPrompt = true
                        }
                    }
                }
            )
        }
        
        if showPortionSelector, let food = scannedFood {
            PortionSizeSelectorView(
                isPresented: $showPortionSelector,
                baseFood: food,
                onConfirm: { scaledFood in
                    foodDatabase.addFood(scaledFood)
                }
            )
        }
        
        if showAIMealScan {
            AIMealScanView(
                isPresented: $showAIMealScan,
                selectedMeal: selectedMeal,
                onFoodDetected: { food in
                    foodDatabase.addFood(food)
                }
            )
        }
    }
    
    func handleCardTap(_ type: MiniCardType) {
        switch type {
        case .todo:
            break
        case .gym:
            workoutDatabase.selectDate(foodDatabase.selectedDate)
            showGymWeekView = true
        case .mood:
            moodIndex = (moodIndex + 1) % 3
            PersistenceManager.shared.saveMoodIndex(moodIndex)
        case .water:
            if waterCount < 12 {
                waterCount += 1
                PersistenceManager.shared.saveWaterCount(waterCount, for: Date())
            }
        case .food:
            showFoodWeekView = true
        case .weight:
            showWeightPicker = true
        }
    }
    
    func syncWorkoutToAppleHealth() {
        guard Calendar.current.isDateInToday(foodDatabase.selectedDate) else {
            print("📅 Viewing past/future date - skipping Apple Health sync")
            return
        }
        
        let totalBurned = workoutDatabase.getTotalCaloriesBurned(weight: currentWeight)
        
        if healthManager.isAuthorized && totalBurned > 0 {
            healthManager.saveWorkoutCalories(totalBurned)
        }

        let percentage = CalorieSettings.shared.loadPercentage()
        let caloriesToBank = totalBurned * percentage

        print("🔥 Burned: \(Int(totalBurned)) cal | Added to bank: \(Int(caloriesToBank)) cal (\(Int(percentage * 100))%)")
    }

    func handleCardLongPress(_ type: MiniCardType) {
        // Water long-press is handled internally by WaterMiniCard.
        // Reserved for future long-press actions on other card types.
    }
    
    func handleQuickAction(_ action: QuickActionType) {
        switch action {
        case .breakfast:
            selectedMeal = .breakfast
            showFoodSearch = true
        case .lunch:
            selectedMeal = .lunch
            showFoodSearch = true
        case .dinner:
            selectedMeal = .dinner
            showFoodSearch = true
        case .snacks:
            selectedMeal = .snacks
            showFoodSearch = true
        case .exercise:
            showGymWeekView = true
        case .water:
            if waterCount < 12 {
                waterCount += 1
                PersistenceManager.shared.saveWaterCount(waterCount, for: Date())
            }
        case .weight:
            showWeightPicker = true
        case .barcodeScan:
            showBarcodeScanner = true
        case .aiMealScan:
            showAIMealScan = true
        }
    }
}
