import SwiftUI
import Combine

struct HomeViewState {
    var waterCount: Int
    var currentWeight: Double
    var targetWeight: Double
    var showCurrentWeight: Bool = true

    var selectedMeal: MealType = .breakfast
    var showQuickActions = false
    var showMealDetail = false
    var showFoodSearch = false
    var showBarcodeScanner = false
    var showAIMealScan = false
    var showBarcodeUnrecognizedPrompt = false
    var showManualBarcodeEntry = false
    var showProfileHub = false
    var showPortionSelector = false
    var showDatePicker = false
    var showWeightPicker = false
    var showFoodWeekView = false
    var showGymWeekView = false

    var pendingBarcode: String? = nil
    var scannedFood: FoodItem? = nil

    var weekFoodLog: [String: DayMeals]
    var weekTodoList: [String: [TodoItem]]
    var weekGymLog: [String: DayWorkout]

    init(
        waterCount: Int,
        currentWeight: Double,
        targetWeight: Double,
        weekFoodLog: [String: DayMeals],
        weekTodoList: [String: [TodoItem]],
        weekGymLog: [String: DayWorkout]
    ) {
        self.waterCount = waterCount
        self.currentWeight = currentWeight
        self.targetWeight = targetWeight
        self.weekFoodLog = weekFoodLog
        self.weekTodoList = weekTodoList
        self.weekGymLog = weekGymLog
    }
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var state: HomeViewState

    let healthManager: HealthManager
    let streakManager: StreakManager
    let foodDatabase: FoodDatabaseManager
    let workoutDatabase: WorkoutDatabaseManager
    let dailyMetricsRepository: any DailyMetricsRepository
    let weeklyLogRepository: any WeeklyLogRepository

    let cardOrder: [MiniCardType] = [.todo, .gym, .water, .food]

    init(dependencies: AppDependencies) {
        self.healthManager = dependencies.healthManager
        self.streakManager = dependencies.streakManager
        self.foodDatabase = dependencies.foodDatabase
        self.workoutDatabase = dependencies.workoutDatabase
        self.dailyMetricsRepository = dependencies.dailyMetricsRepository
        self.weeklyLogRepository = dependencies.weeklyLogRepository

        self.state = HomeViewState(
            waterCount: dailyMetricsRepository.loadWaterCount(for: Date()),
            currentWeight: dailyMetricsRepository.loadCurrentWeight(),
            targetWeight: dailyMetricsRepository.loadTargetWeight(),
            weekFoodLog: weeklyLogRepository.loadWeekFoodLog(),
            weekTodoList: weeklyLogRepository.loadWeekTodoList(),
            weekGymLog: weeklyLogRepository.loadWeekGymLog()
        )
    }

    func binding<T>(_ keyPath: WritableKeyPath<HomeViewState, T>) -> Binding<T> {
        Binding(
            get: { self.state[keyPath: keyPath] },
            set: { self.state[keyPath: keyPath] = $0 }
        )
    }

    var currentDay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }

    var todayMeals: DayMeals {
        state.weekFoodLog[currentDay] ?? DayMeals()
    }

    var todayTodos: [TodoItem] {
        state.weekTodoList[currentDay] ?? []
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
        let caloriesBurned = workoutDatabase.getTotalCaloriesBurned(weight: state.currentWeight)
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

    var recentMeals: [FoodItem] {
        let all = foodDatabase.dailyLog.breakfast +
            foodDatabase.dailyLog.lunch +
            foodDatabase.dailyLog.dinner +
            foodDatabase.dailyLog.snacks
        return Array(all.sorted(by: { $0.timestamp > $1.timestamp }).prefix(2))
    }

    var shouldShowFloatingActionButton: Bool {
        !(state.showQuickActions ||
          state.showMealDetail ||
          state.showFoodSearch ||
          state.showBarcodeScanner ||
          state.showAIMealScan ||
          state.showBarcodeUnrecognizedPrompt ||
          state.showManualBarcodeEntry ||
          state.showWeightPicker ||
          state.showDatePicker ||
          state.showFoodWeekView ||
          state.showGymWeekView)
    }

    func onAppear() {
        healthManager.requestFullAuthorization()
        workoutDatabase.selectDate(foodDatabase.selectedDate)
        refreshTodoState()
        syncWorkoutToAppleHealth()
        syncStreaks()
    }

    func refreshTodoState() {
        state.weekTodoList = weeklyLogRepository.loadWeekTodoList()
    }

    func updateWaterCount(_ newValue: Int) {
        state.waterCount = newValue
        dailyMetricsRepository.saveWaterCount(newValue, for: Date())
    }

    func saveWeights() {
        dailyMetricsRepository.saveCurrentWeight(state.currentWeight)
        dailyMetricsRepository.saveTargetWeight(state.targetWeight)
    }

    func saveWeekFoodLog() {
        weeklyLogRepository.saveWeekFoodLog(state.weekFoodLog)
    }

    func syncStreaks() {
        let intensity = todayWorkout.intensity(weightKg: state.currentWeight)
        streakManager.recordToday(
            caloriesConsumed: foodDatabase.dailyLog.totalCalories(),
            calorieLimit: adjustedCalorieLimit,
            waterGlasses: state.waterCount,
            waterTarget: 8,
            gymIntensity: intensity,
            todosCompleted: todayTodosCompleted,
            todosTotal: todayTodosTotal
        )
    }

    func syncWorkoutToAppleHealth() {
        guard Calendar.current.isDateInToday(foodDatabase.selectedDate) else {
            print("📅 Viewing past/future date - skipping Apple Health sync")
            return
        }

        let totalBurned = workoutDatabase.getTotalCaloriesBurned(weight: state.currentWeight)

        if healthManager.isAuthorized && totalBurned > 0 {
            healthManager.saveWorkoutCalories(totalBurned)
        }

        let percentage = CalorieSettings.shared.loadPercentage()
        let caloriesToBank = totalBurned * percentage

        print("🔥 Burned: \(Int(totalBurned)) cal | Added to bank: \(Int(caloriesToBank)) cal (\(Int(percentage * 100))%)")
    }

    func handleCardTap(_ type: MiniCardType) {
        switch type {
        case .todo:
            break
        case .gym:
            workoutDatabase.selectDate(foodDatabase.selectedDate)
            state.showGymWeekView = true
        case .sleep:
            healthManager.fetchLastNightSleep()
        case .water:
            if state.waterCount < 12 {
                updateWaterCount(state.waterCount + 1)
            }
        case .food:
            state.showFoodWeekView = true
        case .weight:
            state.showWeightPicker = true
        }
    }

    func handleCardLongPress(_ type: MiniCardType) {
        // Water long-press is handled in WaterMiniCard.
    }

    func handleQuickAction(_ action: QuickActionType) {
        switch action {
        case .breakfast:
            state.selectedMeal = .breakfast
            state.showFoodSearch = true
        case .lunch:
            state.selectedMeal = .lunch
            state.showFoodSearch = true
        case .dinner:
            state.selectedMeal = .dinner
            state.showFoodSearch = true
        case .snacks:
            state.selectedMeal = .snacks
            state.showFoodSearch = true
        case .exercise:
            state.showGymWeekView = true
        case .water:
            if state.waterCount < 12 {
                updateWaterCount(state.waterCount + 1)
            }
        case .weight:
            state.showWeightPicker = true
        case .barcodeScan:
            state.showBarcodeScanner = true
        case .aiMealScan:
            state.showAIMealScan = true
        }
    }
}

// MARK: - Home View
struct HomeView: View {
    @ObservedObject private var healthManager: HealthManager
    @ObservedObject private var streakManager: StreakManager
    @ObservedObject private var foodDatabase: FoodDatabaseManager
    @ObservedObject private var workoutDatabase: WorkoutDatabaseManager
    @StateObject private var viewModel: HomeViewModel
    private let apiClient: any APIClient
    @Environment(\.colorScheme) private var colorScheme
    private let scrollSpaceName = "home-scroll"

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }
    
    init(dependencies: AppDependencies) {
        _healthManager = ObservedObject(wrappedValue: dependencies.healthManager)
        _streakManager = ObservedObject(wrappedValue: dependencies.streakManager)
        _foodDatabase = ObservedObject(wrappedValue: dependencies.foodDatabase)
        _workoutDatabase = ObservedObject(wrappedValue: dependencies.workoutDatabase)
        _viewModel = StateObject(wrappedValue: HomeViewModel(dependencies: dependencies))
        self.apiClient = dependencies.apiClient
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
                        limit: viewModel.adjustedCalorieLimit,
                        burned: workoutDatabase.getTotalCaloriesBurned(weight: viewModel.state.currentWeight),
                        water: viewModel.state.waterCount
                    )
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    .onTapGesture {
                        viewModel.state.showMealDetail = true
                    }
                    
                    streaksCard
                    focusListCard
                    recentFuelCard
                    
                    DailyProgressContainer(
                        order: viewModel.cardOrder,
                        waterCount: viewModel.state.waterCount,
                        todayTodosCompleted: viewModel.todayTodosCompleted,
                        todayTodosTotal: viewModel.todayTodosTotal,
                        currentWeight: viewModel.state.currentWeight,
                        targetWeight: viewModel.state.targetWeight,
                        showCurrentWeight: viewModel.state.showCurrentWeight,
                        todayWorkout: viewModel.todayWorkout,
                        sleepDuration: healthManager.sleepDurationHours,
                        todayMeals: viewModel.todayMeals,
                        onCardTap: viewModel.handleCardTap,
                        onCardLongPress: viewModel.handleCardLongPress,
                        onWaterChange: viewModel.updateWaterCount
                    )
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .background(ScrollOffsetReader(coordinateSpace: scrollSpaceName))
            }
            .coordinateSpace(name: scrollSpaceName)
            
            overlays
            
            if viewModel.shouldShowFloatingActionButton {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { viewModel.state.showQuickActions = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 60))
                                .foregroundColor(palette.primaryAccent)
                                .background(Circle().fill(palette.screenBackground).padding(5))
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 100) // Adjusted for custom tab bar
                    }
                }
            }
            
            if viewModel.state.showQuickActions {
                QuickActionsMenu(
                    isPresented: viewModel.binding(\.showQuickActions),
                    onAction: viewModel.handleQuickAction
                )
            }
            
            if viewModel.state.showMealDetail {
                MealDetailView(
                    foodLog: $foodDatabase.dailyLog,
                    isPresented: viewModel.binding(\.showMealDetail),
                    selectedDate: foodDatabase.selectedDate,
                    onDateChange: { newDate in
                        foodDatabase.selectDate(newDate)
                    },
                    onAddFood: { meal in
                        viewModel.state.selectedMeal = meal
                        viewModel.state.showFoodSearch = true
                    }
                )
            }
            
            if viewModel.state.showFoodSearch {
                FoodSearchView(
                    isPresented: viewModel.binding(\.showFoodSearch),
                    selectedMeal: viewModel.state.selectedMeal,
                    onFoodSelected: { food in
                        foodDatabase.addFood(food)
                    }
                )
            }

            if viewModel.state.showBarcodeUnrecognizedPrompt, let barcode = viewModel.state.pendingBarcode {
                BarcodeUnrecognizedPromptView(
                    isPresented: viewModel.binding(\.showBarcodeUnrecognizedPrompt),
                    barcode: barcode,
                    onRetryScan: {
                        viewModel.state.showBarcodeUnrecognizedPrompt = false
                        viewModel.state.showBarcodeScanner = true
                    },
                    onLogManually: {
                        viewModel.state.showBarcodeUnrecognizedPrompt = false
                        viewModel.state.showManualBarcodeEntry = true
                    }
                )
            }

            if viewModel.state.showManualBarcodeEntry {
                CustomFoodView(
                    isPresented: viewModel.binding(\.showManualBarcodeEntry),
                    mealType: viewModel.state.selectedMeal,
                    barcode: viewModel.state.pendingBarcode,
                    initialFoodName: viewModel.state.pendingBarcode == nil ? "" : "Unrecognized Item",
                    initialServingSize: "1 serving",
                    onSave: { food in
                        foodDatabase.addCustomFood(food)
                        foodDatabase.addFood(food)
                        viewModel.state.pendingBarcode = nil
                    }
                )
            }

        }
        .sheet(isPresented: viewModel.binding(\.showProfileHub)) {
            ProfileHubView(isPresented: viewModel.binding(\.showProfileHub))
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onReceive(NotificationCenter.default.publisher(for: .weekTodoListDidChange)) { _ in
            viewModel.refreshTodoState()
            viewModel.syncStreaks()
        }
        .onChange(of: foodDatabase.selectedDate) { oldValue, newValue in
            workoutDatabase.selectDate(newValue)
            viewModel.syncStreaks()
        }
        .onChange(of: foodDatabase.dailyLog.totalCalories()) { _, _ in
            viewModel.syncStreaks()
        }
        .onChange(of: viewModel.state.waterCount) { _, _ in
            viewModel.syncStreaks()
        }
        .onChange(of: viewModel.state.currentWeight) { _, _ in
            viewModel.syncStreaks()
        }
        .onChange(of: viewModel.todayTodosCompleted) { _, _ in
            viewModel.syncStreaks()
        }
        .onChange(of: viewModel.todayTodosTotal) { _, _ in
            viewModel.syncStreaks()
        }
        .onChange(of: workoutDatabase.getTotalCaloriesBurned(weight: viewModel.state.currentWeight)) { _, _ in
            viewModel.syncStreaks()
        }
    }
    
    private var streaksCard: some View {
        let streak = streakManager.perfectDayStreak
        let today = streakManager.summaries[streakManager.dateKey(for: Date())]
        let score = today?.score ?? 0

        return VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("STREAKS")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(1.2)
                    .foregroundColor(palette.textSecondary)
                
                Spacer()
                
                Image(systemName: "flame.fill")
                    .foregroundColor(palette.primaryAccent)
                    .font(.system(size: 14))
            }
            
            // Stats
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(streak)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(streak == 1 ? "Day" : "Days")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(palette.textSecondary)
                }
                
                Text(streak > 0 ? "Perfect day streak is on fire!" : "Let's build a new streak today!")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Progress segments (4 goals)
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index < score ? palette.primaryAccent : palette.inputSurface)
                        .frame(height: 6)
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(palette.surface)
        )
    }
    
    private var focusListCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("FOCUS LIST")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(1.2)
                    .foregroundColor(palette.textSecondary)
                
                Spacer()
                
                Button(action: {
                    // Navigate handled somewhere else, keeping visual parity.
                }) {
                    Text("ADD TASK")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .kerning(1.2)
                        .foregroundColor(palette.primaryAccent)
                }
            }
            
            // Tasks
            let tasksToShow = Array(viewModel.todayTodos.prefix(3))
            if tasksToShow.isEmpty {
                Text("No tasks left. You're all caught up!")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(palette.textSecondary)
                    .padding(.vertical, 8)
            } else {
                ForEach(tasksToShow) { task in
                    HStack(spacing: 16) {
                        Circle()
                            .stroke(task.isCompleted ? palette.primaryAccent : palette.textSecondary, lineWidth: 1.5)
                            .frame(width: 20, height: 20)
                            .overlay(
                                Circle()
                                    .fill(task.isCompleted ? palette.primaryAccent : Color.clear)
                                    .frame(width: 10, height: 10)
                            )
                        
                        Text(task.title)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(2)
                        
                        Spacer()
                        
                        if let date = task.reminderDate {
                            Text(date, format: .dateTime.hour().minute())
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(palette.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(palette.inputSurface))
                        }
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 24).fill(palette.elevatedSurface))
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(palette.surface)
        )
    }

    private var recentFuelCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Text("RECENT FUEL")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .kerning(1.2)
                    .foregroundColor(palette.textSecondary)
                
                Spacer()
                
                Image(systemName: "fork.knife")
                    .foregroundColor(palette.textSecondary)
                    .font(.system(size: 14))
            }
            
            // Meals
            ForEach(viewModel.recentMeals) { food in
                HStack(spacing: 16) {
                    Circle()
                        .fill(palette.elevatedSurface)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(String(food.name.prefix(1)).uppercased())
                                .foregroundColor(palette.primaryAccent)
                                .font(.system(size: 20, weight: .bold))
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(food.name)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text("\(Int(food.calories)) kcal • \(food.timestamp.formatted(.dateTime.hour().minute()))")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundColor(palette.textSecondary)
                    }
                    Spacer()
                }
            }
            
            // Log Next Meal button
            Button(action: { viewModel.state.showQuickActions = true }) {
                HStack(spacing: 16) {
                    Circle()
                        .stroke(palette.textSecondary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "plus")
                                .foregroundColor(palette.textSecondary)
                        )
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Log Next Meal")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundColor(palette.textSecondary)
                        Text("Waiting for input...")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .italic()
                            .foregroundColor(palette.textSecondary.opacity(0.7))
                    }
                    Spacer()
                }
            }
            .padding(.top, 4)
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32)
                .fill(palette.surface)
        )
    }

    private var logoDots: some View {
        HStack(spacing: 2) {
            VStack(spacing: 2) {
                Circle().fill(palette.primaryAccent).frame(width: 8, height: 8)
                Circle().fill(palette.primaryAccent).frame(width: 8, height: 8)
            }
            VStack {
                Spacer().frame(height: 10)
                Circle().fill(palette.primaryAccent).frame(width: 8, height: 8)
            }
        }
    }

    private var headerView: some View {
        VStack(spacing: 16) {
            HStack {
                // Logo
                HStack(spacing: 8) {
                    logoDots
                    Text("LifeOS")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundColor(palette.primaryAccent)
                }

                Spacer()

                HStack(spacing: 20) {
                    Button(action: { /* Do nothing yet */ }) {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 16))
                            .foregroundColor(palette.textSecondary)
                    }

                    Button(action: { viewModel.state.showProfileHub = true }) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(palette.textSecondary)
                            .overlay(Circle().stroke(palette.elevatedSurface, lineWidth: 1))
                    }
                }
            }

            // Date navigation (kept for logic continuity)
            HStack {
                Button(action: {
                    let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: foodDatabase.selectedDate)!
                    foodDatabase.selectDate(yesterday)
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(palette.textSecondary)
                        .padding(8)
                        .background(Circle().fill(palette.surface))
                }

                Spacer()

                Button(action: { viewModel.state.showDatePicker = true }) {
                    Text(viewModel.displayDate.uppercased())
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .kerning(1.5)
                        .foregroundColor(palette.primaryAccent)
                }

                Spacer()

                Button(action: {
                    let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: foodDatabase.selectedDate)!
                    foodDatabase.selectDate(tomorrow)
                }) {
                    Image(systemName: "chevron.right")
                        .foregroundColor(palette.textSecondary)
                        .padding(8)
                        .background(Circle().fill(palette.surface))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .sheet(isPresented: viewModel.binding(\.showDatePicker)) {
            DatePickerSheet(selectedDate: $foodDatabase.selectedDate, isPresented: viewModel.binding(\.showDatePicker))
        }
    }
    
    @ViewBuilder
    private var overlays: some View {
        if viewModel.state.showWeightPicker {
            WeightPickerView(
                currentWeight: viewModel.binding(\.currentWeight),
                targetWeight: viewModel.binding(\.targetWeight),
                isPresented: viewModel.binding(\.showWeightPicker),
                healthManager: healthManager,
                onSave: {
                    viewModel.saveWeights()
                }
            )
        }
        
        if viewModel.state.showFoodWeekView {
            FoodWeekView(
                weekFoodLog: viewModel.binding(\.weekFoodLog),
                currentDay: viewModel.currentDay,
                isPresented: viewModel.binding(\.showFoodWeekView),
                onDismiss: {
                    viewModel.saveWeekFoodLog()
                }
            )
        }
        if viewModel.state.showGymWeekView {
            GymWeekView(
                healthManager: healthManager,
                isPresented: viewModel.binding(\.showGymWeekView),
                onDismiss: {
                    viewModel.syncWorkoutToAppleHealth()
                    viewModel.syncStreaks()
                },
                currentWeight: viewModel.state.currentWeight
            )
        }
        if viewModel.state.showBarcodeScanner {
            BarcodeScannerView(
                isPresented: viewModel.binding(\.showBarcodeScanner),
                selectedMeal: viewModel.state.selectedMeal,
                onBarcodeScanned: { barcode in
                    Task {
                        do {
                            let food = try await BarcodeFoodLookup.lookup(barcode: barcode, apiClient: apiClient)
                            await MainActor.run {
                                if var scannedFoodItem = food {
                                    scannedFoodItem.mealType = viewModel.state.selectedMeal
                                    viewModel.state.scannedFood = scannedFoodItem
                                    viewModel.state.showPortionSelector = true
                                } else {
                                    viewModel.state.pendingBarcode = barcode
                                    viewModel.state.showBarcodeUnrecognizedPrompt = true
                                }
                            }
                        } catch {
                            await MainActor.run {
                                viewModel.state.pendingBarcode = barcode
                                viewModel.state.showBarcodeUnrecognizedPrompt = true
                            }
                        }
                    }
                }
            )
        }
        
        if viewModel.state.showPortionSelector, let food = viewModel.state.scannedFood {
            PortionSizeSelectorView(
                isPresented: viewModel.binding(\.showPortionSelector),
                baseFood: food,
                onConfirm: { scaledFood in
                    foodDatabase.addFood(scaledFood)
                }
            )
        }
        
        if viewModel.state.showAIMealScan {
            AIMealScanView(
                isPresented: viewModel.binding(\.showAIMealScan),
                selectedMeal: viewModel.state.selectedMeal,
                apiClient: apiClient,
                onFoodDetected: { food in
                    foodDatabase.addFood(food)
                }
            )
        }
    }
    
}
