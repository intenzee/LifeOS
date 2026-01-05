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

// MARK: - Home View
struct HomeView: View {
    @ObservedObject var healthManager: HealthManager
    
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
                        consumed: healthManager.caloriesConsumed,
                        limit: caloriesLimit
                    )
                    .padding(.top, 10)
                    
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
        }
        .onAppear {
            healthManager.requestAuthorization()
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
    }
    
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
    
    func handleCardLongPress(_ type: MiniCardType) {
        if type == .water {
            showWaterSlider = true
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

struct SettingsView: View {
    var body: some View {
        ZStack {
            Color(red: 0.06, green: 0.06, blue: 0.07).ignoresSafeArea()
            VStack {
                Text("Settings").font(.largeTitle).fontWeight(.semibold).foregroundColor(.white)
                Text("App preferences coming soon...").foregroundColor(.gray).padding(.top, 20)
            }
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
    }
    
    func cycleExerciseSets(day: String, exerciseId: UUID) {
        guard let index = weekGymLog[day]?.exercises.firstIndex(where: { $0.id == exerciseId }) else { return }
        let currentSets = weekGymLog[day]!.exercises[index].setsCompleted
        let maxSets = weekGymLog[day]!.exercises[index].maxSets
        weekGymLog[day]?.exercises[index].setsCompleted = (currentSets + 1) % (maxSets + 1)
    }
    
    func deleteExercise(day: String, exerciseId: UUID) {
        weekGymLog[day]?.exercises.removeAll { $0.id == exerciseId }
    }
    
    func addExercise(day: String, bodyPart: BodyPart, maxSets: Int) {
        let newExercise = Exercise(bodyPart: bodyPart, setsCompleted: 0, maxSets: maxSets)
        weekGymLog[day]?.exercises.append(newExercise)
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
