import SwiftUI

struct TodoTabView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var weekTodoList: [String: [TodoItem]]
    @State private var selectedDay: String = ""
    @State private var editingDay: String = ""
    @State private var editingTodo: TodoItem? = nil
    @State private var selectedDayIndex: Int = 0

    private let daysOfWeek = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    init() {
        _weekTodoList = State(initialValue: PersistenceManager.shared.loadWeekTodoList())
    }

    private var currentDay: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter.string(from: Date())
    }

    private var currentDayIndex: Int {
        daysOfWeek.firstIndex(of: currentDay) ?? 0
    }

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            palette.screenBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    headerView

                    TabView(selection: $selectedDayIndex) {
                        ForEach(daysOfWeek.indices, id: \.self) { index in
                            todoDayCard(for: daysOfWeek[index])
                                .tag(index)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 10)
                        }
                    }
                    .frame(height: 520)
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .onAppear {
                        selectedDayIndex = currentDayIndex
                    }
                    .animation(.easeInOut(duration: 0.25), value: selectedDayIndex)
                }
                .padding()
            }
        }
        .sheet(isPresented: Binding(
            get: { !selectedDay.isEmpty },
            set: { if !$0 { selectedDay = "" } }
        )) {
            AddTaskSheet(day: selectedDay) { title, notes, reminderDate in
                guard !title.isEmpty else { return }
                addTodo(day: selectedDay, title: title, notes: notes, reminderDate: reminderDate)
                PersistenceManager.shared.saveWeekTodoList(weekTodoList)
                selectedDay = ""
            }
        }
        // Edit sheet
        .sheet(isPresented: Binding(
            get: { editingTodo != nil },
            set: { if !$0 { editingTodo = nil } }
        )) {
            if let todo = editingTodo {
                AddTaskSheet(day: editingDay, initialTitle: todo.title, initialReminderDate: todo.reminderDate) { newTitle, _, newReminderDate in
                    guard !newTitle.isEmpty else { return }
                    updateTodo(day: editingDay, id: todo.id, newTitle: newTitle, newReminderDate: newReminderDate)
                    PersistenceManager.shared.saveWeekTodoList(weekTodoList)
                    editingTodo = nil
                }
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("To Do")
                        .font(.largeTitle.weight(.bold))
                        .foregroundColor(palette.textPrimary)

                    Text("Weekly tasks, one day at a time")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Today")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(palette.primaryAccent)

                    Text(currentDay)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(palette.textPrimary)
                }
            }

            HStack(spacing: 8) {
                ForEach(daysOfWeek.indices, id: \.self) { index in
                    Capsule()
                        .fill(index == selectedDayIndex ? palette.primaryAccent : palette.elevatedSurface)
                        .frame(width: index == selectedDayIndex ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.28, dampingFraction: 0.8), value: selectedDayIndex)
                }
            }
        }
    }

    private func todoDayCard(for day: String) -> some View {
        let todos = weekTodoList[day] ?? []
        let isCompletedDay = !todos.isEmpty && todos.allSatisfy { $0.isCompleted }
        let hasTasks = !todos.isEmpty

        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(day)
                            .font(.title2.weight(.bold))
                            .foregroundColor(palette.textPrimary)

                        if day == currentDay {
                            Text("Today")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(palette.primaryAccent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(palette.primaryAccent.opacity(0.16)))
                        }
                    }

                    Text("\(todos.count) task\(todos.count == 1 ? "" : "s")")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.textSecondary)
                }

                Spacer()

                Button(action: { selectedDay = day }) {
                    Label("Add", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.primaryAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(palette.primaryAccent.opacity(0.12))
                        )
                }
            }

            taskList(for: day, todos: todos)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28)
                .fill(
                    isCompletedDay
                    ? LinearGradient(
                        colors: [Color.green.opacity(0.22), Color.mint.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    : LinearGradient(
                        colors: [palette.surface, palette.surface],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .stroke(
                            isCompletedDay
                            ? Color.green.opacity(0.42)
                            : day == currentDay && hasTasks
                                ? palette.primaryAccent.opacity(0.7)
                                : Color.white.opacity(0.06),
                            lineWidth: isCompletedDay ? 1.5 : (day == currentDay && hasTasks ? 2 : 1)
                        )
                )
                .shadow(
                    color: isCompletedDay
                    ? Color.green.opacity(colorScheme == .dark ? 0.35 : 0.25)
                    : .black.opacity(colorScheme == .dark ? 0.28 : 0.08),
                    radius: isCompletedDay ? 12 : 10,
                    x: 0,
                    y: isCompletedDay ? 8 : 6
                )
        )
        .scaleEffect(isCompletedDay ? 1.01 : (day == currentDay ? 1.0 : 0.97))
    }

    private func taskList(for day: String, todos: [TodoItem]) -> some View {


        return ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 12) {
                if todos.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("No tasks yet")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(palette.textPrimary)

                        Text("Add a new task for \(day) to start building momentum.")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(palette.elevatedSurface)
                    )
                } else {
                    ForEach(todos) { todo in
                        todoRow(todo: todo, day: day)
                    }
                }
            }
            .padding(.trailing, 4)
        }
        .frame(maxHeight: 300, alignment: .top)
    }

    private func todoRow(todo: TodoItem, day: String) -> some View {
        HStack {
            Button(action: { toggleTodo(day: day, todoId: todo.id) }) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(todo.isCompleted ? .green : .gray)
            }

            Text(todo.title)
                .font(.body.weight(.semibold))
                .foregroundColor(todo.isCompleted ? palette.textSecondary : palette.textPrimary)
                .strikethrough(todo.isCompleted)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    editingDay = day
                    editingTodo = todo
                }

            Button(action: { deleteTodo(day: day, todoId: todo.id) }) {
                Image(systemName: "trash")
                    .foregroundColor(.red.opacity(0.7))
                    .font(.subheadline.weight(.semibold))
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(palette.elevatedSurface)
        )
    }



    private func toggleTodo(day: String, todoId: UUID) {
        guard var todos = weekTodoList[day], let index = todos.firstIndex(where: { $0.id == todoId }) else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            todos[index].isCompleted.toggle()
            let updatedItem = todos[index]
            weekTodoList[day] = todos
            PersistenceManager.shared.saveWeekTodoList(weekTodoList)
            
            if updatedItem.isCompleted {
                NotificationService.shared.cancelReminder(for: updatedItem.id)
            } else if let date = updatedItem.reminderDate, date > Date() {
                NotificationService.shared.scheduleReminder(for: updatedItem, at: date)
            }
        }
    }

    private func deleteTodo(day: String, todoId: UUID) {
        weekTodoList[day]?.removeAll { $0.id == todoId }
        PersistenceManager.shared.saveWeekTodoList(weekTodoList)
        NotificationService.shared.cancelReminder(for: todoId)
    }

    private func addTodo(day: String, title: String, notes: String = "", reminderDate: Date? = nil) {
        var todos = weekTodoList[day] ?? []
        let item = TodoItem(title: title, isCompleted: false, reminderDate: reminderDate)
        todos.append(item)
        weekTodoList[day] = todos
        if let date = reminderDate {
            NotificationService.shared.scheduleReminder(for: item, at: date)
        }
    }

    private func updateTodo(day: String, id: UUID, newTitle: String, newReminderDate: Date?) {
        guard var todos = weekTodoList[day],
              let index = todos.firstIndex(where: { $0.id == id }) else { return }
        // Cancel previous reminder if any
        NotificationService.shared.cancelReminder(for: id)
        todos[index].title = newTitle
        todos[index].reminderDate = newReminderDate
        weekTodoList[day] = todos
        if let date = newReminderDate {
            NotificationService.shared.scheduleReminder(for: todos[index], at: date)
        }
    }
}

// MARK: - Reminder Preset
private enum ReminderPreset: Equatable {
    case none, urgent, inOneHour, tonight, tomorrow, custom(Date)

    var label: String {
        switch self {
        case .none:      return "None"
        case .urgent:    return "Mark as Urgent"
        case .inOneHour: return "Remind Me In 1 Hour"
        case .tonight:   return "Remind Me Tonight"
        case .tomorrow:  return "Remind Me Tomorrow"
        case .custom:    return "Remind Me Later\u{2026}"
        }
    }

    var icon: String {
        switch self {
        case .none:      return "minus.circle"
        case .urgent:    return "alarm"
        case .inOneHour: return "clock"
        case .tonight:   return "moon.stars"
        case .tomorrow:  return "calendar"
        case .custom:    return "calendar.badge.clock"
        }
    }

    func resolvedDate() -> Date? {
        let cal = Calendar.current
        switch self {
        case .none:      return nil
        case .urgent:    return Date().addingTimeInterval(5)
        case .inOneHour: return Date().addingTimeInterval(3600)
        case .tonight:   return cal.date(bySettingHour: 21, minute: 0, second: 0, of: Date())
        case .tomorrow:
            guard let tmr = cal.date(byAdding: .day, value: 1, to: Date()) else { return nil }
            return cal.date(bySettingHour: 9, minute: 0, second: 0, of: tmr)
        case .custom(let d): return d
        }
    }
}

// MARK: - Add Task Sheet
private struct AddTaskSheet: View {
    let day: String
    let onSave: (String, String, Date?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String
    @State private var reminderPreset: ReminderPreset
    @State private var showReminderPicker = false
    @State private var customDate: Date
    @FocusState private var titleFocused: Bool

    init(
        day: String,
        initialTitle: String = "",
        initialReminderDate: Date? = nil,
        onSave: @escaping (String, String, Date?) -> Void
    ) {
        self.day = day
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _notes = State(initialValue: "")
        _customDate = State(initialValue: initialReminderDate ?? Date().addingTimeInterval(3600))
        if let d = initialReminderDate {
            _reminderPreset = State(initialValue: .custom(d))
        } else {
            _reminderPreset = State(initialValue: .none)
        }
    }

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    private var reminderChip: String {
        let cal = Calendar.current
        switch reminderPreset {
        case .none:      return ""
        case .urgent:    return "Urgent \u{2014} right now"
        case .inOneHour:
            return "Today, " + Date().addingTimeInterval(3600).formatted(date: .omitted, time: .shortened)
        case .tonight:   return "Tonight, 9:00 PM"
        case .tomorrow:  return "Tomorrow, 9:00 AM"
        case .custom(let d):
            if cal.isDateInToday(d)    { return "Today, "    + d.formatted(date: .omitted, time: .shortened) }
            if cal.isDateInTomorrow(d) { return "Tomorrow, " + d.formatted(date: .omitted, time: .shortened) }
            return d.formatted(date: .abbreviated, time: .shortened)
        }
    }

    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.07, blue: 0.09).ignoresSafeArea()
            VStack(spacing: 0) {
                // Top bar
                HStack {
                    Text("New Task")
                        .font(.title2.weight(.bold))
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .padding(9)
                            .background(Circle().fill(Color.white.opacity(0.18)))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 18)

                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)

                // Input section
                ScrollView {
                    HStack(alignment: .top, spacing: 16) {
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .frame(width: 26, height: 26)
                            .foregroundColor(.gray)
                            .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 10) {
                            TextField("Task title", text: $title)
                                .font(.title3.weight(.medium))
                                .foregroundColor(.white)
                                .focused($titleFocused)

                            TextField("Notes", text: $notes)
                                .font(.subheadline)
                                .foregroundColor(.gray)

                            if reminderPreset != .none {
                                Button(action: { showReminderPicker = true }) {
                                    HStack(spacing: 5) {
                                        Image(systemName: "clock").font(.caption2.weight(.medium))
                                        Text(reminderChip).font(.subheadline)
                                    }
                                    .foregroundColor(ThemePalette.accent)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 22)
                }

                Spacer()

                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)

                // Bottom toolbar
                HStack {
                    HStack(spacing: 22) {
                        Button(action: { showReminderPicker = true }) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(reminderPreset != .none ? ThemePalette.accent : Color.white.opacity(0.10))
                                    .frame(width: 44, height: 44)
                                Image(systemName: "calendar.badge.clock")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                            }
                        }
                        Image(systemName: "location").font(.system(size: 18)).foregroundColor(.white.opacity(0.3))
                        Image(systemName: "flag").font(.system(size: 18)).foregroundColor(.white.opacity(0.3))
                    }
                    .padding(.leading, 20)

                    Spacer()

                    Button(action: {
                        guard canSave else { return }
                        onSave(title.trimmingCharacters(in: .whitespaces), notes, reminderPreset.resolvedDate())
                        dismiss()
                    }) {
                        ZStack {
                            Circle()
                                .fill(canSave ? Color(white: 0.30) : Color(white: 0.15))
                                .frame(width: 46, height: 46)
                            Image(systemName: "checkmark")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(canSave ? .white : .white.opacity(0.25))
                        }
                    }
                    .disabled(!canSave)
                    .padding(.trailing, 20)
                }
                .padding(.vertical, 14)
                .padding(.bottom, 10)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { titleFocused = true }
        .sheet(isPresented: $showReminderPicker) {
            ReminderPresetPicker(selected: $reminderPreset, customDate: $customDate)
        }
    }
}

// MARK: - Reminder Preset Picker
private struct ReminderPresetPicker: View {
    @Binding var selected: ReminderPreset
    @Binding var customDate: Date
    @Environment(\.dismiss) private var dismiss
    @State private var showCustomPicker = false

    private let rows: [(ReminderPreset, String)] = [
        (.none,      "minus.circle"),
        (.urgent,    "alarm"),
        (.inOneHour, "clock"),
        (.tonight,   "moon.stars"),
        (.tomorrow,  "calendar")
    ]

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.10, blue: 0.12).ignoresSafeArea()
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.2))
                    .frame(width: 36, height: 4)
                    .padding(.top, 10).padding(.bottom, 16)

                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(rows.indices, id: \.self) { i in
                            let (preset, icon) = rows[i]
                            Button(action: { selected = preset; dismiss() }) {
                                HStack(spacing: 16) {
                                    Image(systemName: selected == preset ? "checkmark" : "")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.white)
                                        .frame(width: 20)
                                    Image(systemName: icon).font(.system(size: 22)).foregroundColor(.white).frame(width: 30)
                                    Text(preset.label).font(.body).foregroundColor(.white)
                                    Spacer()
                                }
                                .padding(.horizontal, 24).padding(.vertical, 18)
                            }
                            if i < rows.count - 1 {
                                Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5).padding(.leading, 74)
                            }
                        }
                        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 0.5).padding(.leading, 74)

                        // Custom picker row
                        Button(action: { withAnimation { showCustomPicker.toggle() } }) {
                            HStack(spacing: 16) {
                                Color.clear.frame(width: 20)
                                Image(systemName: "calendar.badge.clock").font(.system(size: 22)).foregroundColor(.white).frame(width: 30)
                                Text("Remind Me Later\u{2026}").font(.body).foregroundColor(.white)
                                Spacer()
                                Image(systemName: showCustomPicker ? "chevron.up" : "chevron.down").font(.caption).foregroundColor(.gray)
                            }
                            .padding(.horizontal, 24).padding(.vertical, 18)
                        }

                        if showCustomPicker {
                            DatePicker("", selection: $customDate, displayedComponents: [.date, .hourAndMinute])
                                .datePickerStyle(.graphical)
                                .colorScheme(.dark)
                                .padding(.horizontal, 16)
                                .onChange(of: customDate) { _, d in selected = .custom(d) }
                        }
                    }
                }

                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 0.5)

                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.body.weight(.semibold)).foregroundColor(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 14).fill(ThemePalette.accent))
                }
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 28)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }
}

struct ProfileHubView: View {
    @Binding var isPresented: Bool
    @AppStorage("profileIsLoggedIn") private var isLoggedIn = false
    @AppStorage("profileDisplayName") private var profileDisplayName = "LifeOS User"
    @AppStorage("profileEmail") private var profileEmail = "user@example.com"
    @State private var showSettings = false
    @State private var showHealthProfile = false
    @Environment(\.colorScheme) private var colorScheme

    /// When true, the close (xmark) button is hidden. Used when the view is
    /// embedded as a tab rather than presented modally.
    var embeddedAsTab: Bool = false

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.screenBackground.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 64))
                                .foregroundColor(palette.primaryAccent)

                            Text(isLoggedIn ? profileDisplayName : "Guest")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(palette.textPrimary)

                            Text(isLoggedIn ? profileEmail : "Not signed in")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(palette.surface)
                        )

                        Button(action: { showHealthProfile = true }) {
                            labelRow(
                                title: "Health Profile",
                                systemImage: "person.text.rectangle.fill"
                            )
                        }

                        Button(action: {
                            isLoggedIn.toggle()
                            if isLoggedIn {
                                profileDisplayName = "LifeOS User"
                                profileEmail = "user@example.com"
                            }
                        }) {
                            labelRow(
                                title: isLoggedIn ? "Log Out" : "Log In",
                                systemImage: isLoggedIn ? "rectangle.portrait.and.arrow.right" : "person.crop.circle.badge.checkmark"
                            )
                        }

                        Spacer(minLength: 16)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !embeddedAsTab {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark")
                                .font(.headline)
                                .foregroundColor(palette.textPrimary)
                        }
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape.fill")
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showHealthProfile) {
                ProfileDetailsView()
            }
        }
    }

    private func labelRow(title: String, systemImage: String) -> some View {
        HStack {
            Image(systemName: systemImage)
            Text(title)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
        }
        .foregroundColor(palette.textPrimary)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.elevatedSurface)
        )
    }
}

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
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("appTheme") private var appThemeRaw = AppTheme.system.rawValue
    @State private var caloriePercentage: Double
    @State private var dailyCalorieLimit: Double
    @State private var smokingEnabled: Bool
    @State private var showLimitPicker = false

    @State private var showHealthProfile = false

    init() {
        _caloriePercentage = State(initialValue: CalorieSettings.shared.loadPercentage())
        _dailyCalorieLimit = State(initialValue: CalorieLimitSettings.shared.loadLimit())
        _smokingEnabled = State(initialValue: SmokingSettings.shared.loadSmokingEnabled())
    }

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    private var selectedTheme: AppTheme {
        get { AppTheme(rawValue: appThemeRaw) ?? .system }
        set { appThemeRaw = newValue.rawValue }
    }

    var body: some View {
        ZStack {
            palette.screenBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .foregroundColor(palette.textPrimary)
                        .padding(.horizontal)

                    VStack(spacing: 16) {
                        themeCard
                        healthProfileCard
                        calorieLimitCard
                        calorieBankCard
                        smokingCard
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 20)
            }

            if showLimitPicker {
                calorieLimitPicker
            }
        }
        .sheet(isPresented: $showHealthProfile, onDismiss: {
            dailyCalorieLimit = CalorieLimitSettings.shared.loadLimit()
            smokingEnabled = SmokingSettings.shared.loadSmokingEnabled()
        }) {
            ProfileDetailsView()
        }
    }

    private var healthProfileCard: some View {
        Button(action: { showHealthProfile = true }) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Health Profile")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)

                Text("Edit your age, body metrics, goal, diet and lifestyle. Saving recalculates your daily calorie target.")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.leading)

                HStack {
                    Image(systemName: "person.text.rectangle.fill")
                        .foregroundColor(palette.primaryAccent)
                    Text("Review & edit details")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(palette.elevatedSurface)
                )
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(palette.surface)
            )
        }
        .buttonStyle(.plain)
    }

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            Text("Choose how the app looks on this device")
                .font(.caption)
                .foregroundColor(palette.textSecondary)

            HStack(spacing: 12) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Button(action: { appThemeRaw = theme.rawValue }) {
                        Text(theme.title)
                            .fontWeight(selectedTheme == theme ? .bold : .regular)
                            .foregroundColor(selectedTheme == theme ? .white : palette.textPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(selectedTheme == theme ? palette.primaryAccent : palette.elevatedSurface)
                            )
                    }
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(palette.surface)
        )
    }

    struct ProfileView: View {
        var body: some View {
            ZStack {
                Color(red: 0.06, green: 0.06, blue: 0.07)
                    .ignoresSafeArea()

                VStack {
                    Text("Profile")
                        .font(.largeTitle)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text("User profile coming soon...")
                        .foregroundColor(.gray)
                        .padding(.top, 20)
                }
            }
        }
    }

    private var calorieLimitCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Calorie Target")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            Text("Set your baseline daily calorie budget (before workout adjustments)")
                .font(.caption)
                .foregroundColor(palette.textSecondary)

            Button(action: {
                showLimitPicker = true
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Current Target")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)

                        Text("\(Int(dailyCalorieLimit)) calories")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(palette.primaryAccent)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(palette.elevatedSurface)
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(palette.surface)
        )
    }

    private var calorieBankCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Metabolic Intensity")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            Text("Controls how much burned calories return to your daily target")
                .font(.caption)
                .foregroundColor(palette.textSecondary)

            VStack(spacing: 10) {
                intensityOptionButton(
                    0.5,
                    title: "Low",
                    subtitle: "Slow add-back for a tighter deficit."
                )
                intensityOptionButton(
                    0.75,
                    title: "Medium",
                    subtitle: "Balanced add-back for steady days."
                )
                intensityOptionButton(
                    1.0,
                    title: "High",
                    subtitle: "Fast add-back to support hard training."
                )
            }

            Text("Current: \(intensityLabel(for: caloriePercentage))")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(palette.surface)
        )
    }

    private var smokingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Smoking")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            Text("Use this if you smoke so future health features can adjust guidance and reminders.")
                .font(.caption)
                .foregroundColor(palette.textSecondary)

            Toggle(isOn: Binding(
                get: { smokingEnabled },
                set: { newValue in
                    smokingEnabled = newValue
                    SmokingSettings.shared.saveSmokingEnabled(newValue)
                }
            )) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("I am a smoker")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.textPrimary)

                    Text("Store this preference locally on the device.")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            }
            .tint(palette.primaryAccent)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(palette.surface)
        )
    }

    private var calorieLimitPicker: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    showLimitPicker = false
                }

            VStack(spacing: 24) {
                Text("Set Daily Calorie Target")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)

                VStack(spacing: 12) {
                    limitOptionButton(1500, "Weight Loss (Low)")
                    limitOptionButton(1800, "Weight Loss (Moderate)")
                    limitOptionButton(2000, "Maintenance (Light)")
                    limitOptionButton(2200, "Maintenance (Standard)")
                    limitOptionButton(2500, "Muscle Gain (Moderate)")
                    limitOptionButton(2800, "Muscle Gain (High)")
                    limitOptionButton(3000, "Bulking")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Or enter custom value:")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)

                    HStack {
                        TextField("", value: $dailyCalorieLimit, format: .number)
                            .keyboardType(.numberPad)
                            .foregroundColor(.white)
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
                            )

                        Text("cal")
                            .foregroundColor(.gray)
                    }
                }

                Button(action: {
                    CalorieLimitSettings.shared.saveLimit(dailyCalorieLimit)
                    showLimitPicker = false
                }) {
                    Text("Save")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(palette.primaryAccent)
                        .cornerRadius(12)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(palette.screenBackground)
            )
            .padding(.horizontal, 32)
        }
    }

    func limitOptionButton(_ value: Double, _ label: String) -> some View {
        Button(action: {
            dailyCalorieLimit = value
        }) {
            HStack {
                Text(label)
                    .foregroundColor(palette.textPrimary)

                Spacer()

                Text("\(Int(value)) cal")
                    .foregroundColor(dailyCalorieLimit == value ? .blue : palette.textSecondary)
                    .fontWeight(dailyCalorieLimit == value ? .bold : .regular)

                if dailyCalorieLimit == value {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(palette.primaryAccent)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(dailyCalorieLimit == value ? palette.primaryAccent.opacity(0.2) : palette.elevatedSurface)
            )
        }
    }

    func intensityOptionButton(_ value: Double, title: String, subtitle: String) -> some View {
        Button(action: {
            caloriePercentage = value
            CalorieSettings.shared.savePercentage(value)
        }) {
            let isSelected = caloriePercentage == value
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.textPrimary)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(palette.primaryAccent)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? palette.primaryAccent.opacity(0.12) : palette.elevatedSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? palette.primaryAccent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
    }

    func intensityLabel(for value: Double) -> String {
        switch value {
        case 0.5:
            return "Low"
        case 0.75:
            return "Medium"
        default:
            return "High"
        }
    }
}
