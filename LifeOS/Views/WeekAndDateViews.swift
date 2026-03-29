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
        case .snacks: return dayMeals.snacks
        }
    }

    func toggleMeal(day: String, meal: MealType) {
        guard var dayMeals = weekFoodLog[day] else { return }
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
