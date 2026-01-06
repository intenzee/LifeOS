import SwiftUI
import HealthKit
import Combine

// MARK: - Mini Card Type
enum MiniCardType: Hashable {
    case todo, weight, gym, mood, water, food
}

// MARK: - Meal Type
enum MealType: String, CaseIterable, Codable {
    case breakfast = "Breakfast"
    case lunch = "Lunch"
    case dinner = "Dinner"
}

// MARK: - Body Part
enum BodyPart: String, CaseIterable, Codable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case arms = "Arms"
    case legs = "Legs"
    case abs = "Abs"
    case cardio = "Cardio"
}

// MARK: - Exercise
struct Exercise: Identifiable, Codable {
    let id: UUID
    var bodyPart: BodyPart
    var setsCompleted: Int
    var maxSets: Int
    
    init(id: UUID = UUID(), bodyPart: BodyPart, setsCompleted: Int = 0, maxSets: Int = 3) {
        self.id = id
        self.bodyPart = bodyPart
        self.setsCompleted = setsCompleted
        self.maxSets = maxSets
    }
}

// MARK: - Day Workout
struct DayWorkout: Codable {
    var exercises: [Exercise]
    var treadmillDone: Bool
    
    init(exercises: [Exercise] = [], treadmillDone: Bool = false) {
        self.exercises = exercises
        self.treadmillDone = treadmillDone
    }
    
    var totalSets: Int {
        exercises.reduce(0) { $0 + $1.setsCompleted }
    }
    
    var intensity: String {
        if totalSets >= 6 && treadmillDone {
            return "High"
        } else if totalSets >= 6 {
            return "Medium"
        } else if totalSets >= 3 {
            return "Low"
        } else {
            return "Rest"
        }
    }
}

// MARK: - Day Meals
struct DayMeals: Codable {
    var breakfast: Bool
    var lunch: Bool
    var dinner: Bool
    
    init(breakfast: Bool = false, lunch: Bool = false, dinner: Bool = false) {
        self.breakfast = breakfast
        self.lunch = lunch
        self.dinner = dinner
    }
    
    var highProteinCount: Int {
        [breakfast, lunch, dinner].filter { $0 }.count
    }
    
    var summary: String {
        let highProteinMeals = [
            (breakfast, "Breakfast"),
            (lunch, "Lunch"),
            (dinner, "Dinner")
        ].filter { $0.0 }.map { $0.1 }
        
        if highProteinMeals.isEmpty {
            return "Low Protein"
        } else if highProteinMeals.count == 3 {
            return "High Protein"
        } else {
            return highProteinMeals.joined(separator: ", ")
        }
    }
}

// MARK: - Todo Item
struct TodoItem: Identifiable, Codable {
    let id: UUID
    var title: String
    var isCompleted: Bool
    
    init(id: UUID = UUID(), title: String, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
    }
}

// MARK: - Health Manager
class HealthManager: ObservableObject {
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
        
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
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
        
        let query = HKStatisticsQuery(quantityType: calorieType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
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
        let query = HKSampleQuery(sampleType: weightType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { _, samples, error in
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
        
        healthStore.save(sample) { success, error in
            if success {
                DispatchQueue.main.async {
                    self.healthWeight = weight
                }
            }
        }
    }
}


// MARK: - Persistence Manager
class PersistenceManager {
    static let shared = PersistenceManager()
    
    private let waterKey = "waterCount"
    private let moodKey = "moodIndex"
    private let targetWeightKey = "targetWeight"
    private let currentWeightKey = "currentWeight"
    private let weekFoodKey = "weekFoodLog"
    private let weekTodoKey = "weekTodoList"
    private let weekGymKey = "weekGymLog"
    
    func saveWaterCount(_ count: Int) {
        UserDefaults.standard.set(count, forKey: waterKey)
    }
    
    func loadWaterCount() -> Int {
        UserDefaults.standard.integer(forKey: waterKey)
    }
    
    func saveMoodIndex(_ index: Int) {
        UserDefaults.standard.set(index, forKey: moodKey)
    }
    
    func loadMoodIndex() -> Int {
        UserDefaults.standard.integer(forKey: moodKey)
    }
    
    func saveTargetWeight(_ weight: Double) {
        UserDefaults.standard.set(weight, forKey: targetWeightKey)
    }
    
    func loadTargetWeight() -> Double {
        let saved = UserDefaults.standard.double(forKey: targetWeightKey)
        return saved > 0 ? saved : 68.0
    }
    
    func saveCurrentWeight(_ weight: Double) {
        UserDefaults.standard.set(weight, forKey: currentWeightKey)
    }
    
    func loadCurrentWeight() -> Double {
        let saved = UserDefaults.standard.double(forKey: currentWeightKey)
        return saved > 0 ? saved : 72.5
    }
    
    func saveWeekFoodLog(_ log: [String: DayMeals]) {
        if let encoded = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(encoded, forKey: weekFoodKey)
        }
    }
    
    func loadWeekFoodLog() -> [String: DayMeals] {
        guard let data = UserDefaults.standard.data(forKey: weekFoodKey),
              let decoded = try? JSONDecoder().decode([String: DayMeals].self, from: data) else {
            return defaultWeekFoodLog()
        }
        return decoded
    }
    
    func saveWeekTodoList(_ list: [String: [TodoItem]]) {
        if let encoded = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(encoded, forKey: weekTodoKey)
        }
    }
    
    func loadWeekTodoList() -> [String: [TodoItem]] {
        guard let data = UserDefaults.standard.data(forKey: weekTodoKey),
              let decoded = try? JSONDecoder().decode([String: [TodoItem]].self, from: data) else {
            return defaultWeekTodoList()
        }
        return decoded
    }
    
    func saveWeekGymLog(_ log: [String: DayWorkout]) {
        if let encoded = try? JSONEncoder().encode(log) {
            UserDefaults.standard.set(encoded, forKey: weekGymKey)
        }
    }
    
    func loadWeekGymLog() -> [String: DayWorkout] {
        guard let data = UserDefaults.standard.data(forKey: weekGymKey),
              let decoded = try? JSONDecoder().decode([String: DayWorkout].self, from: data) else {
            return defaultWeekGymLog()
        }
        return decoded
    }
    
    private func defaultWeekFoodLog() -> [String: DayMeals] {
        ["Monday": DayMeals(), "Tuesday": DayMeals(), "Wednesday": DayMeals(),
         "Thursday": DayMeals(), "Friday": DayMeals(), "Saturday": DayMeals(), "Sunday": DayMeals()]
    }
    
    private func defaultWeekTodoList() -> [String: [TodoItem]] {
        ["Monday": [], "Tuesday": [], "Wednesday": [], "Thursday": [],
         "Friday": [], "Saturday": [], "Sunday": []]
    }
    
    private func defaultWeekGymLog() -> [String: DayWorkout] {
        ["Monday": DayWorkout(), "Tuesday": DayWorkout(), "Wednesday": DayWorkout(),
         "Thursday": DayWorkout(), "Friday": DayWorkout(), "Saturday": DayWorkout(), "Sunday": DayWorkout()]
    }
}
// MARK: - Main App with TabView
struct ContentView: View {
    @StateObject private var healthManager = HealthManager()
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(healthManager: healthManager)
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(0)
            
            StatsView()
                .tabItem {
                    Label("Stats", systemImage: "chart.bar.fill")
                }
                .tag(1)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                .tag(2)
            
            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.fill")
                }
                .tag(3)
        }
        .accentColor(.blue)
    }
}

// MARK: - Calorie Settings Manager
class CalorieSettings {
    static let shared = CalorieSettings()
    
    private let percentageKey = "caloriePercentage"
    
    func savePercentage(_ percentage: Double) {
        UserDefaults.standard.set(percentage, forKey: percentageKey)
    }
    
    func loadPercentage() -> Double {
        let saved = UserDefaults.standard.double(forKey: percentageKey)
        return saved > 0 ? saved : 0.5 // Default 50%
    }
}

// MARK: - Calorie Calculator (Based on MET values)
class CalorieCalculator {
    
    // MET values based on scientific research for strength training
    static let exerciseMETs: [BodyPart: Double] = [
        .chest: 6.0,      // Bench press, push-ups (vigorous)
        .back: 6.0,       // Rows, pull-ups (vigorous)
        .shoulders: 5.5,  // Overhead press (moderate-vigorous)
        .arms: 5.0,       // Bicep curls, tricep extensions
        .legs: 6.5,       // Squats, deadlifts (high intensity)
        .abs: 5.0,        // Core exercises
        .cardio: 8.0      // General cardio training
    ]
    
    // Calculate calories for ONE SET of exercise
    // Formula: (MET × 3.5 × weight_kg / 200) × duration_minutes
    // Average set duration: 2.5 minutes (work + rest between sets)
    static func caloriesPerSet(bodyPart: BodyPart, weightKg: Double) -> Double {
        let met = exerciseMETs[bodyPart] ?? 5.0
        let durationMinutes = 2.5 // Average time per set including rest
        
        let calories = (met * 3.5 * weightKg / 200.0) * durationMinutes
        return calories
    }
    
    // Calculate calories for treadmill at 15% incline, 20 minutes
    // MET for walking at 15% incline ≈ 8.5 (brisk uphill)
    static func treadmillCalories(weightKg: Double) -> Double {
        let met = 8.5 // 15% incline at moderate pace (3.0-3.5 mph)
        let durationMinutes = 20.0
        
        let calories = (met * 3.5 * weightKg / 200.0) * durationMinutes
        return calories
    }
    
    // Calculate total workout calories for the day
    static func totalWorkoutCalories(workout: DayWorkout, weightKg: Double) -> Double {
        var total: Double = 0
        
        // Add calories from exercises
        for exercise in workout.exercises {
            let caloriesPerSet = self.caloriesPerSet(bodyPart: exercise.bodyPart, weightKg: weightKg)
            total += caloriesPerSet * Double(exercise.setsCompleted)
        }
        
        // Add treadmill calories
        if workout.treadmillDone {
            total += treadmillCalories(weightKg: weightKg)
        }
        
        return total
    }
}

// MARK: - Food Item Model
struct FoodItem: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingSize: String
    var barcode: String?
    var mealType: MealType
    var timestamp: Date
    
    init(id: UUID = UUID(), name: String, calories: Double, protein: Double = 0, carbs: Double = 0, fat: Double = 0, servingSize: String = "1 serving", barcode: String? = nil, mealType: MealType, timestamp: Date = Date()) {
        self.id = id
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.servingSize = servingSize
        self.barcode = barcode
        self.mealType = mealType
        self.timestamp = timestamp
    }
}

// MARK: - Daily Food Log
struct DailyFoodLog: Codable {
    var breakfast: [FoodItem]
    var lunch: [FoodItem]
    var dinner: [FoodItem]
    var snacks: [FoodItem]
    
    init() {
        self.breakfast = []
        self.lunch = []
        self.dinner = []
        self.snacks = []
    }
    
    func totalCalories() -> Double {
        (breakfast + lunch + dinner + snacks).reduce(0) { $0 + $1.calories }
    }
    
    func totalProtein() -> Double {
        (breakfast + lunch + dinner + snacks).reduce(0) { $0 + $1.protein }
    }
    
    func totalCarbs() -> Double {
        (breakfast + lunch + dinner + snacks).reduce(0) { $0 + $1.carbs }
    }
    
    func totalFat() -> Double {
        (breakfast + lunch + dinner + snacks).reduce(0) { $0 + $1.fat }
    }
    
    mutating func addFood(_ food: FoodItem) {
        switch food.mealType {
        case .breakfast: breakfast.append(food)
        case .lunch: lunch.append(food)
        case .dinner: dinner.append(food)
        }
    }
    
    mutating func removeFood(_ foodId: UUID) {
        breakfast.removeAll { $0.id == foodId }
        lunch.removeAll { $0.id == foodId }
        dinner.removeAll { $0.id == foodId }
        snacks.removeAll { $0.id == foodId }
    }
}

// MARK: - Food Database Manager
class FoodDatabaseManager: ObservableObject {
    static let shared = FoodDatabaseManager()
    
    @Published var recentFoods: [FoodItem] = []
    @Published var favoriteFoods: [FoodItem] = []
    @Published var dailyLog: DailyFoodLog = DailyFoodLog()
    
    private let recentFoodsKey = "recentFoods"
    private let favoriteFoodsKey = "favoriteFoods"
    private let dailyLogKey = "dailyFoodLog"
    
    init() {
        loadData()
    }
    
    func addFood(_ food: FoodItem) {
        dailyLog.addFood(food)
        
        // Add to recent foods
        if let index = recentFoods.firstIndex(where: { $0.name == food.name }) {
            recentFoods.remove(at: index)
        }
        recentFoods.insert(food, at: 0)
        if recentFoods.count > 20 {
            recentFoods.removeLast()
        }
        
        saveData()
    }
    
    func removeFood(_ foodId: UUID) {
        dailyLog.removeFood(foodId)
        saveData()
    }
    
    func toggleFavorite(_ food: FoodItem) {
        if let index = favoriteFoods.firstIndex(where: { $0.id == food.id }) {
            favoriteFoods.remove(at: index)
        } else {
            favoriteFoods.append(food)
        }
        saveData()
    }
    
    func isFavorite(_ food: FoodItem) -> Bool {
        favoriteFoods.contains(where: { $0.name == food.name })
    }
    
    private func saveData() {
        if let encoded = try? JSONEncoder().encode(recentFoods) {
            UserDefaults.standard.set(encoded, forKey: recentFoodsKey)
        }
        if let encoded = try? JSONEncoder().encode(favoriteFoods) {
            UserDefaults.standard.set(encoded, forKey: favoriteFoodsKey)
        }
        if let encoded = try? JSONEncoder().encode(dailyLog) {
            UserDefaults.standard.set(encoded, forKey: dailyLogKey)
        }
    }
    
    private func loadData() {
        if let data = UserDefaults.standard.data(forKey: recentFoodsKey),
           let decoded = try? JSONDecoder().decode([FoodItem].self, from: data) {
            recentFoods = decoded
        }
        if let data = UserDefaults.standard.data(forKey: favoriteFoodsKey),
           let decoded = try? JSONDecoder().decode([FoodItem].self, from: data) {
            favoriteFoods = decoded
        }
        if let data = UserDefaults.standard.data(forKey: dailyLogKey),
           let decoded = try? JSONDecoder().decode(DailyFoodLog.self, from: data) {
            dailyLog = decoded
        }
    }
    
    // Sample food database (you can expand this)
    static let commonFoods: [FoodItem] = [
        FoodItem(name: "Chicken Breast (100g)", calories: 165, protein: 31, carbs: 0, fat: 3.6, servingSize: "100g", mealType: .lunch),
        FoodItem(name: "Brown Rice (1 cup)", calories: 216, protein: 5, carbs: 45, fat: 1.8, servingSize: "1 cup", mealType: .lunch),
        FoodItem(name: "Banana", calories: 105, protein: 1.3, carbs: 27, fat: 0.4, servingSize: "1 medium", mealType: .breakfast),
        FoodItem(name: "Eggs (2 large)", calories: 140, protein: 12, carbs: 1, fat: 10, servingSize: "2 eggs", mealType: .breakfast),
        FoodItem(name: "Oatmeal (1 cup)", calories: 150, protein: 5, carbs: 27, fat: 3, servingSize: "1 cup", mealType: .breakfast),
        FoodItem(name: "Protein Shake", calories: 120, protein: 24, carbs: 3, fat: 2, servingSize: "1 scoop", mealType: .breakfast),
        FoodItem(name: "Apple", calories: 95, protein: 0.5, carbs: 25, fat: 0.3, servingSize: "1 medium", mealType: .breakfast),
        FoodItem(name: "Almonds (28g)", calories: 164, protein: 6, carbs: 6, fat: 14, servingSize: "28g", mealType: .breakfast)
    ]
}

// MARK: - Quick Actions Menu
struct QuickActionsMenu: View {
    @Binding var isPresented: Bool
    let onAction: (QuickActionType) -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 0) {
                Spacer()
                
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        Text("Quick Actions")
                            .font(.headline)
                            .foregroundColor(.white)
                        Spacer()
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.title2)
                        }
                    }
                    .padding()
                    .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                    
                    Divider().background(Color.gray.opacity(0.3))
                    
                    // Actions Grid
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 20) {
                        actionButton("fork.knife", "Breakfast", .breakfast)
                        actionButton("fork.knife", "Lunch", .lunch)
                        actionButton("fork.knife", "Dinner", .dinner)
                        actionButton("cup.and.saucer", "Snacks", .snacks)
                        actionButton("figure.run", "Exercise", .exercise)
                        actionButton("drop.fill", "Water", .water)
                        actionButton("scalemass", "Weight", .weight)
                        actionButton("barcode.viewfinder", "Scan", .barcodeScan)
                        actionButton("camera.fill", "AI Scan", .aiMealScan)
                    }
                    .padding(20)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                }
                .cornerRadius(20, corners: [.topLeft, .topRight])
            }
        }
    }
    
    func actionButton(_ icon: String, _ label: String, _ action: QuickActionType) -> some View {
        Button(action: {
            onAction(action)
            isPresented = false
        }) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 28))
                    .foregroundColor(.blue)
                
                Text(label)
                    .font(.caption)
                    .foregroundColor(.white)
            }
            .frame(height: 70)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
            )
        }
    }
}

// MARK: - Meal Detail View
struct MealDetailView: View {
    @Binding var foodLog: DailyFoodLog
    @Binding var isPresented: Bool
    let onAddFood: (MealType) -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Today's Meals")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                            
                            Text("\(Int(foodLog.totalCalories())) calories")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.title2)
                        }
                    }
                    
                    // Macros Summary
                    HStack(spacing: 16) {
                        macroCard("Protein", foodLog.totalProtein(), "g", .green)
                        macroCard("Carbs", foodLog.totalCarbs(), "g", .orange)
                        macroCard("Fat", foodLog.totalFat(), "g", .red)
                    }
                    
                    // Meals
                    mealSection("Breakfast", .breakfast, foodLog.breakfast)
                    mealSection("Lunch", .lunch, foodLog.lunch)
                    mealSection("Dinner", .dinner, foodLog.dinner)
                    mealSection("Snacks", .breakfast, foodLog.snacks) // Using breakfast type for snacks
                    
                    Spacer(minLength: 40)
                }
                .padding(24)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 60)
        }
    }
    
    func macroCard(_ label: String, _ value: Double, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(value))\(unit)")
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
        )
    }
    
    func mealSection(_ title: String, _ mealType: MealType, _ foods: [FoodItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Spacer()
                
                Button(action: { onAddFood(mealType) }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            
            if foods.isEmpty {
                Text("No items added")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(foods) { food in
                        foodRow(food)
                    }
                }
            }
            
            Text("\(Int(foods.reduce(0) { $0 + $1.calories })) cal")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
        )
    }
    
    func foodRow(_ food: FoodItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                Text(food.servingSize)
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Text("\(Int(food.calories)) cal")
                .font(.caption)
                .foregroundColor(.blue)
            
            Button(action: {
                FoodDatabaseManager.shared.removeFood(food.id)
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.7))
            }
        }
    }
}

// MARK: - Food Search View
struct FoodSearchView: View {
    @Binding var isPresented: Bool
    let selectedMeal: MealType
    let onFoodSelected: (FoodItem) -> Void
    
    @State private var searchText = ""
    @State private var showingCustomFood = false
    
    var filteredFoods: [FoodItem] {
        if searchText.isEmpty {
            return FoodDatabaseManager.commonFoods
        } else {
            return FoodDatabaseManager.commonFoods.filter {
                $0.name.lowercased().contains(searchText.lowercased())
            }
        }
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Add to \(selectedMeal.rawValue)")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title2)
                    }
                }
                .padding()
                .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search foods...", text: $searchText)
                        .foregroundColor(.white)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                
                // Tabs
                HStack(spacing: 0) {
                    tabButton("Common", true)
                    tabButton("Recent", false)
                    tabButton("Favorites", false)
                }
                .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                
                Divider().background(Color.gray.opacity(0.3))
                
                // Food List
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(filteredFoods) { food in
                            foodSearchRow(food)
                        }
                        
                        // Custom Food Button
                        Button(action: { showingCustomFood = true }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.blue)
                                Text("Add Custom Food")
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
                            )
                        }
                    }
                    .padding()
                }
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            }
            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            .cornerRadius(20)
            .padding(.horizontal, 20)
            .padding(.vertical, 60)
            
            if showingCustomFood {
                CustomFoodView(
                    isPresented: $showingCustomFood,
                    mealType: selectedMeal,
                    onSave: { food in
                        onFoodSelected(food)
                        isPresented = false
                    }
                )
            }
        }
    }
    
    func tabButton(_ title: String, _ isSelected: Bool) -> some View {
        Button(action: {}) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(isSelected ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color(red: 0.15, green: 0.15, blue: 0.17) : Color.clear)
        }
    }
    
    func foodSearchRow(_ food: FoodItem) -> some View {
        Button(action: {
            var selectedFood = food
            selectedFood.mealType = selectedMeal
            onFoodSelected(selectedFood)
            isPresented = false
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name)
                        .font(.subheadline)
                        .foregroundColor(.white)
                    
                    HStack(spacing: 8) {
                        Text("\(Int(food.calories)) cal")
                            .font(.caption)
                            .foregroundColor(.blue)
                        Text("•")
                            .foregroundColor(.gray)
                        Text(food.servingSize)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
                
                Image(systemName: "plus.circle")
                    .foregroundColor(.blue)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
            )
        }
    }
}

// MARK: - Custom Food Entry View
struct CustomFoodView: View {
    @Binding var isPresented: Bool
    let mealType: MealType
    let onSave: (FoodItem) -> Void
    
    @State private var foodName = ""
    @State private var calories = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var servingSize = ""
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Add Custom Food")
                    .font(.headline)
                    .foregroundColor(.white)
                
                TextField("Food name", text: $foodName)
                    .padding()
                    .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                
                HStack(spacing: 12) {
                    TextField("Calories", text: $calories)
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    
                    TextField("Protein (g)", text: $protein)
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                HStack(spacing: 12) {
                    TextField("Carbs (g)", text: $carbs)
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    
                    TextField("Fat (g)", text: $fat)
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                TextField("Serving size", text: $servingSize)
                    .padding()
                    .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                    .foregroundColor(.white)
                    .cornerRadius(10)
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .cornerRadius(10)
                    
                    Button("Save") {
                        let food = FoodItem(
                            name: foodName.isEmpty ? "Custom Food" : foodName,
                            calories: Double(calories) ?? 0,
                            protein: Double(protein) ?? 0,
                            carbs: Double(carbs) ?? 0,
                            fat: Double(fat) ?? 0,
                            servingSize: servingSize.isEmpty ? "1 serving" : servingSize,
                            mealType: mealType
                        )
                        onSave(food)
                        isPresented = false
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
            .padding(.horizontal, 40)
        }
    }
}

// MARK: - Barcode Scanner View
import AVFoundation

struct BarcodeScannerView: View {
    @Binding var isPresented: Bool
    let selectedMeal: MealType
    let onBarcodeScanned: (String) -> Void
    
    var body: some View {
        ZStack {
            BarcodeScannerRepresentable(onBarcodeScanned: { barcode in
                onBarcodeScanned(barcode)
                isPresented = false
            })
            .ignoresSafeArea()
            
            VStack {
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                
                Spacer()
                
                VStack(spacing: 12) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                    
                    Text("Scan Barcode")
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text("Align barcode within the frame")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.7))
                )
                .padding(.bottom, 100)
            }
        }
    }
}

// MARK: - Barcode Scanner UIKit Bridge
struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onBarcodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let controller = BarcodeScannerViewController()
        controller.onBarcodeScanned = onBarcodeScanned
        return controller
    }
    
    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onBarcodeScanned: ((String) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }
    
    func setupCamera() {
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if (captureSession?.canAddInput(videoInput) ?? false) {
            captureSession?.addInput(videoInput)
        } else {
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if (captureSession?.canAddOutput(metadataOutput) ?? false) {
            captureSession?.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .pdf417, .upce, .code128, .code39]
        } else {
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)
        
        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if (captureSession?.isRunning == true) {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession?.stopRunning()
            }
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onBarcodeScanned?(stringValue)
        }
    }
}

// MARK: - Barcode Food Lookup with OpenFoodFacts API
class BarcodeFoodLookup {
    // Real-time lookup from OpenFoodFacts database
    static func lookup(barcode: String, completion: @escaping (FoodItem?) -> Void) {
        let urlString = "https://world.openfoodfacts.org/api/v0/product/\(barcode).json"
        
        guard let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            guard let data = data, error == nil else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? Int,
                   status == 1,
                   let product = json["product"] as? [String: Any] {
                    
                    // Extract nutritional data
                    let name = product["product_name"] as? String ?? "Unknown Product"
                    let nutriments = product["nutriments"] as? [String: Any] ?? [:]
                    
                    // Per 100g values
                    let calories = (nutriments["energy-kcal_100g"] as? Double) ?? 0
                    let protein = (nutriments["proteins_100g"] as? Double) ?? 0
                    let carbs = (nutriments["carbohydrates_100g"] as? Double) ?? 0
                    let fat = (nutriments["fat_100g"] as? Double) ?? 0
                    
                    let food = FoodItem(
                        name: name,
                        calories: calories,
                        protein: protein,
                        carbs: carbs,
                        fat: fat,
                        servingSize: "100g",
                        barcode: barcode,
                        mealType: .breakfast
                    )
                    
                    DispatchQueue.main.async {
                        completion(food)
                    }
                } else {
                    DispatchQueue.main.async { completion(nil) }
                }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }
}


// MARK: - AI Meal Scanner View
import PhotosUI

struct AIMealScanView: View {
    @Binding var isPresented: Bool
    let selectedMeal: MealType
    let onFoodDetected: (FoodItem) -> Void
    
    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isAnalyzing = false
    @State private var detectedFood: FoodItem?
    @State private var showConfirmation = false
    @State private var apiKey = ""
    @State private var selectedAI: AIProvider = .chatgpt
    
    enum AIProvider: String, CaseIterable {
        case chatgpt = "ChatGPT"
        case perplexity = "Perplexity"
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
            
            VStack(spacing: 24) {
                // Header
                HStack {
                    Text("AI Meal Scanner")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title2)
                    }
                }
                
                // AI Provider Selection
                Picker("AI Provider", selection: $selectedAI) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // API Key Input
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(selectedAI.rawValue) API Key")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    SecureField("Enter your API key", text: $apiKey)
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                
                Text("Get your API key from \(selectedAI == .chatgpt ? "platform.openai.com" : "perplexity.ai")")
                    .font(.caption)
                    .foregroundColor(.blue)
                
                // Image Preview
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("No image selected")
                            .foregroundColor(.gray)
                    }
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                    .cornerRadius(16)
                }
                
                // Action Buttons
                HStack(spacing: 12) {
                    Button(action: { showImagePicker = true }) {
                        Label("Select Photo", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                    
                    Button(action: { analyzeImage() }) {
                        if isAnalyzing {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Label("Analyze", systemImage: "sparkles")
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(selectedImage != nil && !apiKey.isEmpty ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(selectedImage == nil || apiKey.isEmpty || isAnalyzing)
                }
                
                Spacer()
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 60)
            
            // Confirmation Dialog
            if showConfirmation, let food = detectedFood {
                FoodConfirmationView(
                    food: food,
                    isPresented: $showConfirmation,
                    onConfirm: {
                        onFoodDetected(food)
                        isPresented = false
                    }
                )
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
        }
    }
    
    func analyzeImage() {
        guard let image = selectedImage else { return }
        isAnalyzing = true
        
        // Convert image to base64
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            isAnalyzing = false
            return
        }
        let base64Image = imageData.base64EncodedString()
        
        // Call AI API
        if selectedAI == .chatgpt {
            analyzewithChatGPT(base64Image: base64Image)
        } else {
            analyzeWithPerplexity(base64Image: base64Image)
        }
    }
    
    func analyzewithChatGPT(base64Image: String) {
        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Analyze this food image and return ONLY a JSON object with this exact format (no markdown, no explanation):
        {
          "name": "Food name",
          "calories": 250,
          "protein": 20,
          "carbs": 30,
          "fat": 10,
          "servingSize": "1 cup"
        }
        """
        
        let payload: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                    ]
                ]
            ],
            "max_tokens": 300
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isAnalyzing = false
                
                guard let data = data, error == nil else {
                    print("Error: \(error?.localizedDescription ?? "Unknown")")
                    return
                }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    parseFoodResponse(content)
                }
            }
        }.resume()
    }
    
    func analyzeWithPerplexity(base64Image: String) {
        let url = URL(string: "https://api.perplexity.ai/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let prompt = """
        Analyze this food image and return ONLY a JSON object with this exact format:
        {
          "name": "Food name",
          "calories": 250,
          "protein": 20,
          "carbs": 30,
          "fat": 10,
          "servingSize": "1 cup"
        }
        """
        
        let payload: [String: Any] = [
            "model": "llama-3.1-sonar-large-128k-online",
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isAnalyzing = false
                
                guard let data = data, error == nil else { return }
                
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String {
                    
                    parseFoodResponse(content)
                }
            }
        }.resume()
    }
    
    func parseFoodResponse(_ response: String) {
        // Remove markdown code blocks if present
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("Failed to parse JSON")
            return
        }
        
        let food = FoodItem(
            name: json["name"] as? String ?? "Unknown Food",
            calories: json["calories"] as? Double ?? 0,
            protein: json["protein"] as? Double ?? 0,
            carbs: json["carbs"] as? Double ?? 0,
            fat: json["fat"] as? Double ?? 0,
            servingSize: json["servingSize"] as? String ?? "1 serving",
            mealType: selectedMeal
        )
        
        detectedFood = food
        showConfirmation = true
    }
}

// MARK: - Food Confirmation View
struct FoodConfirmationView: View {
    let food: FoodItem
    @Binding var isPresented: Bool
    let onConfirm: () -> Void
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Food Detected!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                VStack(alignment: .leading, spacing: 12) {
                    infoRow("Name", food.name)
                    infoRow("Calories", "\(Int(food.calories)) kcal")
                    infoRow("Protein", "\(Int(food.protein))g")
                    infoRow("Carbs", "\(Int(food.carbs))g")
                    infoRow("Fat", "\(Int(food.fat))g")
                    infoRow("Serving", food.servingSize)
                }
                .padding()
                .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                .cornerRadius(12)
                
                HStack(spacing: 12) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .cornerRadius(10)
                    
                    Button("Add to Log") {
                        onConfirm()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(10)
                }
            }
            .padding(30)
            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            .cornerRadius(20)
            .padding(.horizontal, 40)
        }
    }
    
    func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Image Picker
struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
    }
}

// Helper for rounded corners
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

// MARK: - Quick Action Menu Type
enum QuickActionType {
    case breakfast, lunch, dinner, snacks, exercise, water, weight, barcodeScan, aiMealScan
}

// MARK: - Enhanced Health Manager Extension
extension HealthManager {
    
    // Update authorization to include active energy
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
        
        healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead) { success, error in
            DispatchQueue.main.async {
                self.isAuthorized = success
                if success {
                    self.fetchTodayCalories()
                    self.fetchLatestWeight()
                }
            }
        }
    }
    
    // Fetch walking/active calories from Apple Health
    func fetchWalkingCalories(completion: @escaping (Double) -> Void) {
        guard let activeEnergyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion(0)
            return
        }
        
        let now = Date()
        let startOfDay = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: now, options: .strictStartDate)
        
        let query = HKStatisticsQuery(quantityType: activeEnergyType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
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
    
    // Save workout calories to Apple Health
    func saveWorkoutCalories(_ calories: Double, workoutType: HKWorkoutActivityType = .traditionalStrengthTraining) {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return }
        
        let quantity = HKQuantity(unit: HKUnit.kilocalorie(), doubleValue: calories)
        let now = Date()
        let sample = HKQuantitySample(type: energyType, quantity: quantity, start: now.addingTimeInterval(-3600), end: now)
        
        healthStore.save(sample) { success, error in
            if success {
                print("✅ Saved \(Int(calories)) calories to Apple Health")
            } else {
                print("❌ Failed to save calories: \(error?.localizedDescription ?? "Unknown")")
            }
        }
    }
}

// MARK: - Home View
struct HomeView: View {
    @ObservedObject var healthManager: HealthManager
    
    @StateObject private var foodDatabase = FoodDatabaseManager.shared
    @State private var showQuickActions = false
    @State private var showMealDetail = false
    @State private var selectedMeal: MealType = .breakfast
    @State private var showFoodSearch = false
    @State private var showBarcodeScanner = false
    @State private var showAIMealScan = false
    @State private var waterCount: Int
    @State private var showWaterSlider = false
    
    @State private var currentWeight: Double
    @State private var targetWeight: Double
    @State private var showWeightPicker = false
    @State private var showCurrentWeight = true
    
    @State private var moodIndex: Int
    
    @State private var showFoodWeekView = false
    @State private var showTodoWeekView = false
    @State private var showGymWeekView = false
    
    @State private var weekFoodLog: [String: DayMeals]
    @State private var weekTodoList: [String: [TodoItem]]
    @State private var weekGymLog: [String: DayWorkout]
    
    let caloriesLimit = 2200.0
    let cardOrder: [MiniCardType] = [.todo, .gym, .water, .food]
    
    init(healthManager: HealthManager) {
        self.healthManager = healthManager
        
        let persistence = PersistenceManager.shared
        _waterCount = State(initialValue: persistence.loadWaterCount())
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
        weekGymLog[currentDay] ?? DayWorkout()
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    headerView
                    
                    CaloriesRing(
                        consumed: foodDatabase.dailyLog.totalCalories(),  // ✅ Changed
                        limit: caloriesLimit
                    )
                    .padding(.top, 10)
                    .onTapGesture {
                        showMealDetail = true  // ✅ Added - Tap to view meals
                    }
                    
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
                        showWaterSlider: $showWaterSlider,
                        onCardTap: handleCardTap,
                        onCardLongPress: handleCardLongPress,
                        onWaterChange: { newValue in
                            waterCount = newValue
                            PersistenceManager.shared.saveWaterCount(newValue)
                        }
                    )
                    
                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
            }
            
            overlays
            
            // ✅ NEW - PLUS BUTTON (Bottom Right)
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
            
            // ✅ NEW - Quick Actions Menu
            if showQuickActions {
                QuickActionsMenu(
                    isPresented: $showQuickActions,
                    onAction: handleQuickAction
                )
            }
            
            // ✅ NEW - Meal Detail View
            if showMealDetail {
                MealDetailView(
                    foodLog: $foodDatabase.dailyLog,
                    isPresented: $showMealDetail,
                    onAddFood: { meal in
                        selectedMeal = meal
                        showFoodSearch = true
                    }
                )
            }
            
            // ✅ NEW - Food Search View
            if showFoodSearch {
                FoodSearchView(
                    isPresented: $showFoodSearch,
                    selectedMeal: selectedMeal,
                    onFoodSelected: { food in
                        foodDatabase.addFood(food)
                    }
                )
            }
        }
        .onAppear {
            healthManager.requestFullAuthorization()
            calculateAndAddCaloriesToBank()
            fetchAndAddWalkingCalories()
        }
    }

    
    private var headerView: some View {
        HStack {
            Text("Today")
                .font(.largeTitle)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Spacer()
        }
        .padding(.top, 20)
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
        
        if showTodoWeekView {
            TodoWeekView(
                weekTodoList: $weekTodoList,
                currentDay: currentDay,
                isPresented: $showTodoWeekView,
                onDismiss: {
                    PersistenceManager.shared.saveWeekTodoList(weekTodoList)
                }
            )
        }
        
        if showGymWeekView {
            GymWeekView(
                weekGymLog: $weekGymLog,
                currentDay: currentDay,
                isPresented: $showGymWeekView,
                onDismiss: {
                    PersistenceManager.shared.saveWeekGymLog(weekGymLog)
                }
            )
        }
        
        if showBarcodeScanner {
            BarcodeScannerView(
                isPresented: $showBarcodeScanner,
                selectedMeal: selectedMeal,
                onBarcodeScanned: { barcode in
                    print("🔍 Scanned barcode: \(barcode)")
                    
                    // Show loading indicator (optional)
                    BarcodeFoodLookup.lookup(barcode: barcode) { food in
                        if var scannedFood = food {
                            scannedFood.mealType = selectedMeal
                            foodDatabase.addFood(scannedFood)
                            print("✅ Added: \(scannedFood.name) - \(Int(scannedFood.calories)) cal")
                        } else {
                            print("❌ Barcode not found in database: \(barcode)")
                            // Show alert to user (optional)
                        }
                    }
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
    }  // ← Closing brace stays here

    
    func handleCardTap(_ type: MiniCardType) {
        switch type {
        case .todo:
            showTodoWeekView = true
        case .gym:
            showGymWeekView = true
        case .mood:
            moodIndex = (moodIndex + 1) % 3
            PersistenceManager.shared.saveMoodIndex(moodIndex)
        case .water:
            if waterCount < 12 {
                waterCount += 1
                PersistenceManager.shared.saveWaterCount(waterCount)
            }
        case .food:
            showFoodWeekView = true
        case .weight:
            showWeightPicker = true
        }
    }

    // MARK: - Calorie Tracking Integration
    func calculateAndAddCaloriesToBank() {
        // Get today's workout
        let workout = weekGymLog[currentDay] ?? DayWorkout()
        
        // Calculate total calories burned from exercises
        let totalBurned = CalorieCalculator.totalWorkoutCalories(workout: workout, weightKg: currentWeight)
        
        // Get percentage setting (50%, 75%, or 100%)
        let percentage = CalorieSettings.shared.loadPercentage()
        
        // Calculate calories to add to bank
        let caloriesToAdd = totalBurned * percentage
        
        // Add to consumed calories (giving back calorie budget)
        healthManager.caloriesConsumed += caloriesToAdd
        
        // Save workout calories to Apple Health
        if healthManager.isAuthorized {
            healthManager.saveWorkoutCalories(totalBurned)
        }
        
        print("🔥 Burned: \(Int(totalBurned)) cal | Added to bank: \(Int(caloriesToAdd)) cal (\(Int(percentage * 100))%)")
    }

    func fetchAndAddWalkingCalories() {
        if healthManager.isAuthorized {
            healthManager.fetchWalkingCalories { walkingCals in
                let percentage = CalorieSettings.shared.loadPercentage()
                let caloriesToAdd = walkingCals * percentage
                
                // Add walking calories to bank
                self.healthManager.caloriesConsumed += caloriesToAdd
                
                print("🚶 Walking: \(Int(walkingCals)) cal | Added to bank: \(Int(caloriesToAdd)) cal (\(Int(percentage * 100))%)")
            }
        }
    }

    
    func handleCardLongPress(_ type: MiniCardType) {
        if type == .water {
            showWaterSlider = true
        }
    }
    // MARK: - Handle Quick Actions
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
            selectedMeal = .breakfast // Snacks use breakfast type
            showFoodSearch = true
        case .exercise:
            showGymWeekView = true
        case .water:
            if waterCount < 12 {
                waterCount += 1
                PersistenceManager.shared.saveWaterCount(waterCount)
            }
        case .weight:
            showWeightPicker = true
        case .barcodeScan:
            showBarcodeScanner = true
            print("📷 Barcode scanner coming in next block")
        case .aiMealScan:
            showAIMealScan = true
            print("🤖 AI meal scan coming in next block")
        }
    }

}

// MARK: - Other Tab Views
struct StatsView: View {
    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()
            VStack {
                Text("Stats").font(.largeTitle).fontWeight(.semibold).foregroundColor(.white)
                Text("Weekly analytics coming soon...").foregroundColor(.gray).padding(.top, 20)
            }
        }
    }
}

// MARK: - Settings View
struct SettingsView: View {
    @State private var caloriePercentage: Double
    
    init() {
        _caloriePercentage = State(initialValue: CalorieSettings.shared.loadPercentage())
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07)
                .ignoresSafeArea()
            
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                VStack(spacing: 16) {
                    settingsCard
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top, 20)
        }
    }
    
    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Calorie Bank Settings")
                .font(.headline)
                .foregroundColor(.white)
            
            Text("Percentage of burned calories to add back to your calorie budget")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack(spacing: 12) {
                percentageButton(0.5, "50%")
                percentageButton(0.75, "75%")
                percentageButton(1.0, "100%")
            }
            
            Text("Current: \(Int(caloriePercentage * 100))% of burned calories added")
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
        )
    }
    
    func percentageButton(_ value: Double, _ label: String) -> some View {
        Button(action: {
            caloriePercentage = value
            CalorieSettings.shared.savePercentage(value)
        }) {
            Text(label)
                .fontWeight(caloriePercentage == value ? .bold : .regular)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(caloriePercentage == value ? Color.blue : Color(red: 0.2, green: 0.2, blue: 0.22))
                )
        }
    }
}


struct ProfileView: View {
    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()
            VStack {
                Text("Profile").font(.largeTitle).fontWeight(.semibold).foregroundColor(.white)
                Text("User profile coming soon...").foregroundColor(.gray).padding(.top, 20)
            }
        }
    }
}

// MARK: - Daily Progress Container
struct DailyProgressContainer: View {
    let order: [MiniCardType]
    let waterCount: Int
    let todayTodosCompleted: Int
    let todayTodosTotal: Int
    let currentWeight: Double
    let targetWeight: Double
    let showCurrentWeight: Bool
    let todayWorkout: DayWorkout
    let moodIndex: Int
    let todayMeals: DayMeals
    @Binding var showWaterSlider: Bool
    
    let onCardTap: (MiniCardType) -> Void
    let onCardLongPress: (MiniCardType) -> Void
    let onWaterChange: (Int) -> Void
    
    var weightRemaining: Double { currentWeight - targetWeight }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Progress").font(.headline).foregroundColor(.white)
            
            VStack(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(order, id: \.self) { card in
                        ZStack {
                            miniCard(card)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if !(card == .water && showWaterSlider) {
                                        onCardTap(card)
                                    }
                                }
                                .onLongPressGesture(minimumDuration: 0.5) {
                                    onCardLongPress(card)
                                }
                            
                            if card == .water && showWaterSlider {
                                WaterSliderOverlay(waterCount: waterCount) { newValue in
                                    onWaterChange(newValue)
                                    showWaterSlider = false
                                }
                            }
                        }
                    }
                }
                
                HStack(spacing: 12) {
                    miniCard(.weight).onTapGesture { onCardTap(.weight) }
                    miniCard(.mood).onTapGesture { onCardTap(.mood) }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 18).fill(Color(red: 0.12, green: 0.12, blue: 0.14)))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.blue.opacity(0.6)))
        }
    }
    
    func miniCard(_ type: MiniCardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title(for: type)).font(.caption).foregroundColor(.gray)
            Text(value(for: type)).font(.headline).foregroundColor(color(for: type)).lineLimit(2).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.10, green: 0.10, blue: 0.12)))
    }
    
    func title(for type: MiniCardType) -> String {
        switch type {
        case .todo: return "To‑Do"
        case .weight: return "Weight"
        case .gym: return "Gym Intensity"
        case .mood: return "Mood"
        case .water: return "Water"
        case .food: return "Protein Food"
        }
    }
    
    func value(for type: MiniCardType) -> String {
        switch type {
        case .todo: return "\(todayTodosCompleted)/\(todayTodosTotal) Done"
        case .weight:
            let baseWeight = showCurrentWeight ? "\(String(format: "%.1f", currentWeight)) kg" : "Target \(Int(targetWeight))"
            if weightRemaining > 0 {
                return "\(baseWeight)\n\(String(format: "%.1f", weightRemaining)) kg to go"
            }
            return baseWeight
        case .gym: return todayWorkout.intensity
        case .mood: return ["😞", "😐", "😊"][moodIndex]
        case .water: return "\(waterCount)/8"
        case .food: return todayMeals.summary
        }
    }
    
    func color(for type: MiniCardType) -> Color {
        switch type {
        case .todo: return todayTodosTotal > 0 && todayTodosCompleted == todayTodosTotal ? .green : .orange
        case .water: return waterCount >= 8 ? .green : .orange
        case .mood: return moodIndex == 2 ? .green : .orange
        case .gym:
            switch todayWorkout.intensity {
            case "High": return .green
            case "Medium": return .blue
            case "Low": return .orange
            default: return .gray
            }
        case .food:
            let count = todayMeals.highProteinCount
            return count == 3 ? .green : (count == 0 ? .orange : .blue)
        default: return .blue
        }
    }
}

// MARK: - Calories Ring
struct CaloriesRing: View {
    let consumed: Double
    let limit: Double
    var progress: Double { min(consumed / limit, 1.0) }
    
    var body: some View {
        ZStack {
            Circle().stroke(Color.blue.opacity(0.15), lineWidth: 20)
            Circle().trim(from: 0, to: progress).stroke(Color.blue, style: StrokeStyle(lineWidth: 20, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 6) {
                Text("Calorie Budget").font(.title3).fontWeight(.semibold).foregroundColor(.white)
                Text("\(Int(consumed))").font(.system(size: 36, weight: .bold)).foregroundColor(.blue)
                Text("of \(Int(limit))").font(.subheadline).foregroundColor(.gray)
            }
        }
        .frame(width: 220, height: 220)
    }
}
// MARK: - Water Slider Overlay
struct WaterSliderOverlay: View {
    let waterCount: Int
    let onWaterChange: (Int) -> Void
    @State private var dragValue: Double
    @State private var isDragging = false
    
    init(waterCount: Int, onWaterChange: @escaping (Int) -> Void) {
        self.waterCount = waterCount
        self.onWaterChange = onWaterChange
        _dragValue = State(initialValue: Double(waterCount))
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Text("\(Int(dragValue.rounded())) glasses")
                .font(.caption)
                .foregroundColor(.white)
                .fontWeight(.semibold)
            
            sliderTrack
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(red: 0.08, green: 0.08, blue: 0.10))
                .shadow(color: .blue.opacity(0.6), radius: 12)
        )
        .scaleEffect(isDragging ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isDragging)
    }
    
    private var sliderTrack: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.2))
                .frame(width: 120, height: 6)
            
            let progressWidth: CGFloat = CGFloat(dragValue / 12.0) * 120.0
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.blue)
                .frame(width: progressWidth, height: 6)
        }
        .frame(width: 120, height: 44)
        .contentShape(Rectangle())
        .highPriorityGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    isDragging = true
                    let locationX = value.location.x
                    let normalized = locationX / 120.0
                    let clamped = max(0, min(12, normalized * 12.0))
                    dragValue = clamped
                }
                .onEnded { _ in
                    isDragging = false
                    onWaterChange(Int(dragValue.rounded()))
                }
        )
    }
}

// MARK: - Gym Week View
struct GymWeekView: View {
    @Binding var weekGymLog: [String: DayWorkout]
    let currentDay: String
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    
    @State private var selectedDay: String = ""
    @State private var selectedBodyPart: BodyPart = .chest
    @State private var selectedMaxSets: Int = 3
    
    let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    
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
                    Text("Weekly Gym Plan")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
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
            
            if !selectedDay.isEmpty {
                addExercisePopup
            }
        }
    }
    
    private func dayCard(for day: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day)
                        .font(.headline)
                        .foregroundColor(day == currentDay ? .blue : .white)
                    
                    if let workout = weekGymLog[day] {
                        Text("Intensity: \(workout.intensity)")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
                
                if day == currentDay {
                    Text("(Today)")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Button(action: { selectedDay = day }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            
            treadmillToggle(for: day)
            exercisesList(for: day)
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
    
    private func treadmillToggle(for day: String) -> some View {
        HStack {
            Text("Treadmill (20 min)")
                .foregroundColor(.gray)
            Spacer()
            Button(action: { toggleTreadmill(day: day) }) {
                Image(systemName: weekGymLog[day]?.treadmillDone == true ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(weekGymLog[day]?.treadmillDone == true ? .green : .gray)
            }
        }
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private func exercisesList(for day: String) -> some View {
        if let exercises = weekGymLog[day]?.exercises, !exercises.isEmpty {
            VStack(spacing: 8) {
                ForEach(exercises) { exercise in
                    exerciseRow(exercise: exercise, day: day)
                }
            }
        } else {
            Text("No exercises")
                .font(.caption)
                .foregroundColor(.gray)
                .padding(.vertical, 4)
        }
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
            
            Button(action: { cycleExerciseSets(day: day, exerciseId: exercise.id) }) {
                Text("\(exercise.setsCompleted)/\(exercise.maxSets)")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(6)
            }
            
            Button(action: { deleteExercise(day: day, exerciseId: exercise.id) }) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
                    .font(.caption)
            }
        }
    }
    
    private var addExercisePopup: some View {
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
                Text("Max Sets:")
                    .foregroundColor(.white)
                Spacer()
                
                ForEach([3, 6], id: \.self) { sets in
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
                Button("Cancel") { selectedDay = "" }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .cornerRadius(10)
                
                Button("Add") {
                    addExercise(day: selectedDay, bodyPart: selectedBodyPart, maxSets: selectedMaxSets)
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
    
    func toggleTreadmill(day: String) {
        weekGymLog[day]?.treadmillDone.toggle()
        
        // Show calorie update
        if day == currentDay {
            printCalorieUpdate()
        }
    }

    func cycleExerciseSets(day: String, exerciseId: UUID) {
        guard let index = weekGymLog[day]?.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let currentSets = weekGymLog[day]!.exercises[index].setsCompleted
        let maxSets = weekGymLog[day]!.exercises[index].maxSets
        weekGymLog[day]?.exercises[index].setsCompleted = (currentSets + 1) % (maxSets + 1)
        
        // Show calorie update
        if day == currentDay {
            printCalorieUpdate()
        }
    }

    func deleteExercise(day: String, exerciseId: UUID) {
        weekGymLog[day]?.exercises.removeAll { $0.id == exerciseId }
        
        // Show calorie update
        if day == currentDay {
            printCalorieUpdate()
        }
    }

    func addExercise(day: String, bodyPart: BodyPart, maxSets: Int) {
        let newExercise = Exercise(bodyPart: bodyPart, setsCompleted: 0, maxSets: maxSets)
        weekGymLog[day]?.exercises.append(newExercise)
        
        // Show calorie update
        if day == currentDay {
            printCalorieUpdate()
        }
    }

    // Helper function to display calorie calculations
    func printCalorieUpdate() {
        guard let workout = weekGymLog[currentDay] else { return }
        
        // Get current weight from persistence
        let weight = PersistenceManager.shared.loadCurrentWeight()
        
        // Calculate total calories
        let totalBurned = CalorieCalculator.totalWorkoutCalories(workout: workout, weightKg: weight)
        
        // Get percentage
        let percentage = CalorieSettings.shared.loadPercentage()
        let caloriesToBank = totalBurned * percentage
        
        print("🏋️ Updated Workout:")
        print("   Total burned: \(Int(totalBurned)) cal")
        print("   Added to bank: \(Int(caloriesToBank)) cal (\(Int(percentage * 100))%)")
        
        // Show breakdown
        for exercise in workout.exercises {
            let calPerSet = CalorieCalculator.caloriesPerSet(bodyPart: exercise.bodyPart, weightKg: weight)
            let totalForExercise = calPerSet * Double(exercise.setsCompleted)
            print("   \(exercise.bodyPart.rawValue): \(exercise.setsCompleted) sets = \(Int(totalForExercise)) cal")
        }
        
        if workout.treadmillDone {
            let treadmillCal = CalorieCalculator.treadmillCalories(weightKg: weight)
            print("   Treadmill: \(Int(treadmillCal)) cal")
        }
    }

}
// MARK: - Weight Picker View
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
// MARK: - Todo Week View
struct TodoWeekView: View {
    @Binding var weekTodoList: [String: [TodoItem]]
    let currentDay: String
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    
    @State private var newTodoText: String = ""
    @State private var selectedDay: String = ""
    
    let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    
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
                    Text("Weekly To-Do List")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    VStack(spacing: 16) {
                        ForEach(daysOfWeek, id: \.self) { day in
                            todoDayCard(for: day)
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
            
            if !selectedDay.isEmpty {
                addTodoPopup
            }
        }
    }
    
    private func todoDayCard(for day: String) -> some View {
        VStack(spacing: 12) {
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
                
                Button(action: { selectedDay = day }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            
            if let todos = weekTodoList[day], !todos.isEmpty {
                VStack(spacing: 8) {
                    ForEach(todos) { todo in
                        todoRow(todo: todo, day: day)
                    }
                }
            } else {
                Text("No tasks")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 4)
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
    
    private func todoRow(todo: TodoItem, day: String) -> some View {
        HStack {
            Button(action: { toggleTodo(day: day, todoId: todo.id) }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? .green : .gray)
            }
            
            Text(todo.title)
                .foregroundColor(todo.isCompleted ? .gray : .white)
                .strikethrough(todo.isCompleted)
            
            Spacer()
            
            Button(action: { deleteTodo(day: day, todoId: todo.id) }) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
                    .font(.caption)
            }
        }
    }
    
    private var addTodoPopup: some View {
        VStack(spacing: 16) {
            Text("Add Task for \(selectedDay)")
                .font(.headline)
                .foregroundColor(.white)
            
            TextField("Task description", text: $newTodoText)
                .foregroundColor(.white)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
                )
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    selectedDay = ""
                    newTodoText = ""
                }
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                .cornerRadius(10)
                
                Button("Add") {
                    if !newTodoText.isEmpty {
                        addTodo(day: selectedDay, title: newTodoText)
                        selectedDay = ""
                        newTodoText = ""
                    }
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
    
    func toggleTodo(day: String, todoId: UUID) {
        guard var todos = weekTodoList[day],
              let index = todos.firstIndex(where: { $0.id == todoId }) else { return }
        todos[index].isCompleted.toggle()
        weekTodoList[day] = todos
    }
    
    func deleteTodo(day: String, todoId: UUID) {
        weekTodoList[day]?.removeAll { $0.id == todoId }
    }
    
    func addTodo(day: String, title: String) {
        var todos = weekTodoList[day] ?? []
        todos.append(TodoItem(title: title, isCompleted: false))
        weekTodoList[day] = todos
    }
}
// MARK: - Food Week View
struct FoodWeekView: View {
    @Binding var weekFoodLog: [String: DayMeals]
    let currentDay: String
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    
    let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    
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
                    Text("Weekly Food Plan")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    
                    VStack(spacing: 16) {
                        ForEach(daysOfWeek, id: \.self) { day in
                            foodDayCard(for: day)
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
        }
    }
    
    private func foodDayCard(for day: String) -> some View {
        VStack(spacing: 12) {
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
            }
            
            VStack(spacing: 8) {
                ForEach(MealType.allCases, id: \.self) { meal in
                    mealRow(day: day, meal: meal)
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
    
    private func mealRow(day: String, meal: MealType) -> some View {
        HStack {
            Text(meal.rawValue)
                .foregroundColor(.gray)
                .frame(width: 80, alignment: .leading)
            
            Spacer()
            
            Button(action: { toggleMeal(day: day, meal: meal) }) {
                Text(getMealStatus(day: day, meal: meal) ? "High Protein" : "Low Protein")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(getMealStatus(day: day, meal: meal) ? Color.green : Color.orange)
                    )
            }
        }
    }
    
    func getMealStatus(day: String, meal: MealType) -> Bool {
        guard let dayMeals = weekFoodLog[day] else { return false }
        switch meal {
        case .breakfast: return dayMeals.breakfast
        case .lunch: return dayMeals.lunch
        case .dinner: return dayMeals.dinner
        }
    }
    
    func toggleMeal(day: String, meal: MealType) {
        guard var dayMeals = weekFoodLog[day] else { return }
        switch meal {
        case .breakfast: dayMeals.breakfast.toggle()
        case .lunch: dayMeals.lunch.toggle()
        case .dinner: dayMeals.dinner.toggle()
        }
        weekFoodLog[day] = dayMeals
    }
}
