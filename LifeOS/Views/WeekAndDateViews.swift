import SwiftUI

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
                            .background(ThemePalette.accent)
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
                    .foregroundColor(day == currentDay ? ThemePalette.accent : .white)

                if day == currentDay {
                    Text("(Today)")
                        .font(.caption)
                        .foregroundColor(ThemePalette.accent)
                }

                Spacer()

                Button(action: { selectedDay = day }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(ThemePalette.accent)
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
                        .stroke(day == currentDay ? ThemePalette.accent.opacity(0.6) : .clear, lineWidth: 2)
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
                .background(ThemePalette.accent)
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

struct FoodWeekView: View {
    @Binding var weekFoodLog: [String: DayMeals]
    let currentDay: String
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    @State private var selectedDayIndex: Int = 0

    let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
    let dayAbbreviations = ["M", "T", "W", "T", "F", "S", "S"]

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    private var currentDayIndex: Int {
        daysOfWeek.firstIndex(of: currentDay) ?? 0
    }

    private var selectedDayName: String {
        daysOfWeek[selectedDayIndex]
    }

    private var selectedDayMeals: DayMeals {
        weekFoodLog[selectedDayName] ?? DayMeals()
    }

    // Protein score (0–4 meals marked high-protein)
    private var proteinScore: Int {
        selectedDayMeals.highProteinCount
    }

    private var proteinPercent: CGFloat {
        CGFloat(proteinScore) / 4.0
    }

    // Does the student need extra protein?
    private var needsExtraProtein: Bool {
        proteinScore < 3
    }

    // Hostel meal info
    struct MealInfo {
        let type: MealType
        let time: String
        let icon: String
        let proteinTip: String
        let lowProteinExample: String
    }

    private let mealData: [MealInfo] = [
        MealInfo(type: .breakfast, time: "7 – 9 AM", icon: "sunrise.fill",
                 proteinTip: "Eggs, paneer paratha, or curd",
                 lowProteinExample: "Bread & jam, poha"),
        MealInfo(type: .lunch, time: "12 – 2 PM", icon: "sun.max.fill",
                 proteinTip: "Dal, rajma/chole, chicken curry",
                 lowProteinExample: "Plain rice & sabzi"),
        MealInfo(type: .dinner, time: "7 – 9 PM", icon: "moon.fill",
                 proteinTip: "Paneer/egg curry, dal makhani",
                 lowProteinExample: "Roti & aloo sabzi"),
        MealInfo(type: .snacks, time: "Anytime", icon: "takeoutbag.and.cup.and.straw.fill",
                 proteinTip: "Peanuts, milk, protein shake, sprouts",
                 lowProteinExample: "Biscuits, chips, maggi"),
    ]

    var body: some View {
        ZStack {
            palette.screenBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 24) {
                        proteinRing
                        weekStrip
                        supplementBanner
                        mealTimeline
                        weekOverviewGrid
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
            }
        }
        .onAppear {
            selectedDayIndex = currentDayIndex
            // Ensure every day has an entry
            for day in daysOfWeek {
                if weekFoodLog[day] == nil {
                    weekFoodLog[day] = DayMeals()
                }
            }
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

            Text("PROTEIN TRACKER")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .kerning(2)
                .foregroundColor(palette.primaryAccent)

            Spacer()

            Color.clear.frame(width: 36, height: 36)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Protein Score Ring
    private var proteinRing: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(palette.elevatedSurface, lineWidth: 14)

                Circle()
                    .trim(from: 0, to: proteinPercent)
                    .stroke(
                        ringGradient,
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: ringColor.opacity(0.4), radius: 8)
                    .animation(.spring(response: 0.5, dampingFraction: 0.7), value: proteinScore)

                VStack(spacing: 2) {
                    Text("\(proteinScore)/4")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    Text("MEALS")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .kerning(1.5)
                        .foregroundColor(palette.textSecondary)
                }
            }
            .frame(width: 140, height: 140)

            // Status label
            Text(proteinStatusText)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(ringColor)
        }
    }

    private var ringColor: Color {
        switch proteinScore {
        case 4: return palette.primaryAccent
        case 3: return .blue
        case 2: return .orange
        default: return .red
        }
    }

    private var ringGradient: LinearGradient {
        LinearGradient(
            colors: [ringColor, ringColor.opacity(0.6)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    private var proteinStatusText: String {
        switch proteinScore {
        case 4: return "🎯 All meals protein-rich!"
        case 3: return "💪 Almost there, one more!"
        case 2: return "⚠️ Need more protein today"
        case 1: return "🔴 Protein very low"
        default: return "❌ No high-protein meals yet"
        }
    }

    // MARK: - Week Day Strip
    private var weekStrip: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { i in
                let isSelected = i == selectedDayIndex
                let isToday = i == currentDayIndex
                let dayMeals = weekFoodLog[daysOfWeek[i]] ?? DayMeals()
                let score = dayMeals.highProteinCount

                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        selectedDayIndex = i
                    }
                }) {
                    VStack(spacing: 6) {
                        Text(dayAbbreviations[i])
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(isSelected ? .black : palette.textSecondary)

                        // Protein dot indicator
                        ZStack {
                            Circle()
                                .fill(isSelected ? Color.black.opacity(0.2) : dotColor(score: score))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(isSelected ? palette.primaryAccent : Color.clear)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isToday && !isSelected ? palette.primaryAccent.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                }
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(palette.surface)
        )
    }

    private func dotColor(score: Int) -> Color {
        switch score {
        case 4: return palette.primaryAccent
        case 3: return .blue
        case 2: return .orange
        case 1: return .red.opacity(0.7)
        default: return palette.elevatedSurface
        }
    }

    // MARK: - Supplement Banner
    @ViewBuilder
    private var supplementBanner: some View {
        if needsExtraProtein {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Extra protein needed")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                    Text("Add a protein shake, milk, eggs or peanuts to hit your goal")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(2)
                }

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                    )
            )
        } else {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 16))
                    .foregroundColor(palette.primaryAccent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Protein goal on track!")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                    Text("Great job — keep it up 💪")
                        .font(.system(size: 11, weight: .regular, design: .rounded))
                        .foregroundColor(palette.textSecondary)
                }

                Spacer()
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(palette.primaryAccent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(palette.primaryAccent.opacity(0.2), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Meal Timeline
    private var mealTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Your Day")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(palette.textPrimary)
                .padding(.bottom, 16)

            ForEach(Array(mealData.enumerated()), id: \.element.type) { index, meal in
                mealTimelineRow(meal: meal, isLast: index == mealData.count - 1)
            }
        }
    }

    private func mealTimelineRow(meal: MealInfo, isLast: Bool) -> some View {
        let isHighProtein = getMealStatus(day: selectedDayName, meal: meal.type)

        return HStack(alignment: .top, spacing: 16) {
            // Timeline line + dot
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(isHighProtein ? palette.primaryAccent : palette.elevatedSurface)
                        .frame(width: 32, height: 32)

                    Image(systemName: isHighProtein ? "checkmark" : meal.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(isHighProtein ? .black : palette.textSecondary)
                }

                if !isLast {
                    Rectangle()
                        .fill(palette.elevatedSurface)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 32)

            // Card
            Button(action: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    toggleMeal(day: selectedDayName, meal: meal.type)
                }
            }) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(meal.type.rawValue)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundColor(palette.textPrimary)
                            Text(meal.time)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(palette.textSecondary)
                        }

                        Spacer()

                        // Toggle badge
                        Text(isHighProtein ? "HIGH" : "LOW")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .kerning(0.5)
                            .foregroundColor(isHighProtein ? .black : .white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                Capsule()
                                    .fill(isHighProtein ? palette.primaryAccent : Color.orange)
                            )
                    }

                    // Tip / example
                    HStack(spacing: 6) {
                        Image(systemName: isHighProtein ? "leaf.fill" : "lightbulb.fill")
                            .font(.system(size: 10))
                            .foregroundColor(isHighProtein ? palette.primaryAccent : .orange)

                        Text(isHighProtein ? meal.proteinTip : "Try: \(meal.proteinTip)")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(palette.textSecondary)
                            .lineLimit(2)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(palette.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(isHighProtein ? palette.primaryAccent.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                )
            }
            .buttonStyle(.plain)
        }
        .frame(minHeight: 100)
    }

    // MARK: - Week Overview Grid
    private var weekOverviewGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Week Overview")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(palette.textPrimary)

            VStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { i in
                    let day = daysOfWeek[i]
                    let meals = weekFoodLog[day] ?? DayMeals()
                    let score = meals.highProteinCount
                    let isToday = i == currentDayIndex

                    HStack(spacing: 12) {
                        Text(day.prefix(3))
                            .font(.system(size: 13, weight: isToday ? .bold : .medium, design: .rounded))
                            .foregroundColor(isToday ? palette.primaryAccent : palette.textPrimary)
                            .frame(width: 36, alignment: .leading)

                        // Meal dots
                        HStack(spacing: 6) {
                            mealDot(filled: meals.breakfast, label: "B")
                            mealDot(filled: meals.lunch, label: "L")
                            mealDot(filled: meals.dinner, label: "D")
                            mealDot(filled: meals.snacks, label: "S")
                        }

                        Spacer()

                        Text("\(score)/4")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(dotColor(score: score))
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isToday ? palette.primaryAccent.opacity(0.08) : palette.surface)
                    )
                }
            }
        }
    }

    private func mealDot(filled: Bool, label: String) -> some View {
        ZStack {
            Circle()
                .fill(filled ? palette.primaryAccent : palette.elevatedSurface)
                .frame(width: 28, height: 28)
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(filled ? .black : palette.textSecondary)
        }
    }

    // MARK: - Helpers
    func getMealStatus(day: String, meal: MealType) -> Bool {
        guard let dayMeals = weekFoodLog[day] else { return false }
        switch meal {
        case .breakfast: return dayMeals.breakfast
        case .lunch: return dayMeals.lunch
        case .dinner: return dayMeals.dinner
        case .snacks: return dayMeals.snacks
        }
    }

    func toggleMeal(day: String, meal: MealType) {
        var dayMeals = weekFoodLog[day] ?? DayMeals()
        switch meal {
        case .breakfast: dayMeals.breakfast.toggle()
        case .lunch: dayMeals.lunch.toggle()
        case .dinner: dayMeals.dinner.toggle()
        case .snacks: dayMeals.snacks.toggle()
        }
        weekFoodLog[day] = dayMeals
    }
}

struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    @Binding var isPresented: Bool

    var body: some View {
        NavigationView {
            VStack {
                DatePicker(
                    "Select Date",
                    selection: Binding(
                        get: { selectedDate },
                        set: { newDate in
                            selectedDate = newDate
                            FoodDatabaseManager.shared.selectDate(newDate)
                        }
                    ),
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding()

                Spacer()
            }
            .navigationTitle("Choose Date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Today") {
                        let today = Date()
                        selectedDate = today
                        FoodDatabaseManager.shared.selectDate(today)
                        isPresented = false
                    }
                }
            }
        }
    }
}
