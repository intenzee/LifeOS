import SwiftUI
import Charts

// MARK: - Shared chrome

private struct ToolScaffold<Content: View>: View {
    let title: String
    @Binding var isPresented: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Color.black.opacity(0.9).ignoresSafeArea()
            VStack(spacing: 18) {
                HStack {
                    Text(title).font(.title2).fontWeight(.bold).foregroundColor(.white)
                    Spacer()
                    Button { isPresented = false } label: {
                        Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray)
                    }
                }
                content()
                Spacer(minLength: 0)
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color(red: 0.08, green: 0.08, blue: 0.10).ignoresSafeArea())
        }
    }
}

// MARK: - Rest Timer

struct RestTimerView: View {
    @Binding var isPresented: Bool

    @State private var total: Int = 90
    @State private var remaining: Int = 90
    @State private var running = false
    @State private var timer: Timer?

    private let presets = [30, 60, 90, 120, 180, 300]

    var body: some View {
        ToolScaffold(title: "Rest Timer", isPresented: $isPresented) {
            VStack(spacing: 24) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.12), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: total > 0 ? CGFloat(remaining) / CGFloat(total) : 0)
                        .stroke(ThemePalette.accent, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.25), value: remaining)
                    VStack(spacing: 2) {
                        Text(timeString(remaining)).font(.system(size: 44, weight: .bold, design: .rounded))
                            .foregroundColor(.white).monospacedDigit()
                        Text(running ? "resting" : "ready").font(.caption).foregroundColor(.gray)
                    }
                }
                .frame(width: 210, height: 210)
                .padding(.top, 8)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(presets, id: \.self) { p in
                        Button {
                            total = p; remaining = p
                            if running { restart() }
                        } label: {
                            Text(timeString(p)).font(.subheadline).fontWeight(total == p ? .bold : .regular)
                                .foregroundColor(.white).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .background(total == p ? ThemePalette.accent.opacity(0.3) : Color(red: 0.15, green: 0.15, blue: 0.17))
                                .cornerRadius(10)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button { running ? pause() : startTimer() } label: {
                        Label(running ? "Pause" : "Start", systemImage: running ? "pause.fill" : "play.fill")
                            .frame(maxWidth: .infinity).padding()
                            .background(running ? Color.orange : ThemePalette.accent)
                            .foregroundColor(.white).cornerRadius(12)
                    }
                    Button { reset() } label: {
                        Label("Reset", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity).padding()
                            .background(Color(red: 0.2, green: 0.2, blue: 0.22)).foregroundColor(.white).cornerRadius(12)
                    }
                }
            }
        }
        .onDisappear { timer?.invalidate() }
    }

    private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    private func startTimer() {
        running = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            guard remaining > 0 else { finish(); return }
            remaining -= 1
            if remaining == 0 { finish() }
        }
    }
    private func restart() { pause(); startTimer() }
    private func pause() { running = false; timer?.invalidate() }
    private func reset() { pause(); remaining = total }
    private func finish() {
        pause()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        remaining = 0
    }
}

// MARK: - Strength Calculators (1RM + plate)

struct StrengthCalculatorView: View {
    @Binding var isPresented: Bool

    @State private var weight: Double = 60
    @State private var reps: Int = 5
    @State private var barWeight: Double = 20

    // Kilogram plates available per side, heaviest first.
    private let platePool: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    private var oneRepMax: Double { weight * (1 + Double(reps) / 30.0) } // Epley

    private var platesPerSide: [Double] {
        var remainingPerSide = max(oneRepMaxTarget - barWeight, 0) / 2
        var result: [Double] = []
        for plate in platePool {
            while remainingPerSide >= plate - 0.001 {
                result.append(plate)
                remainingPerSide -= plate
            }
        }
        return result
    }
    // Plate calc targets the entered working weight, not the 1RM.
    private var oneRepMaxTarget: Double { weight }

    var body: some View {
        ToolScaffold(title: "Strength Tools", isPresented: $isPresented) {
            ScrollView {
                VStack(spacing: 20) {
                    // Inputs
                    VStack(spacing: 14) {
                        stepperRow(label: "Weight", value: "\(Int(weight)) kg") {
                            weight = max(0, weight - 2.5)
                        } onPlus: { weight += 2.5 }
                        stepperRow(label: "Reps", value: "\(reps)") {
                            reps = max(1, reps - 1)
                        } onPlus: { reps = min(20, reps + 1) }
                        stepperRow(label: "Bar", value: "\(Int(barWeight)) kg") {
                            barWeight = max(0, barWeight - 5)
                        } onPlus: { barWeight += 5 }
                    }
                    .padding().background(Color(red: 0.13, green: 0.13, blue: 0.15)).cornerRadius(14)

                    // 1RM
                    VStack(spacing: 4) {
                        Text("Estimated 1-Rep Max").font(.caption).foregroundColor(.gray)
                        Text("\(Int(oneRepMax.rounded())) kg")
                            .font(.system(size: 40, weight: .bold, design: .rounded)).foregroundColor(ThemePalette.accent)
                        Text("Epley · \(Int(weight))kg × \(reps) reps").font(.caption2).foregroundColor(.gray)
                        HStack(spacing: 14) {
                            oneRmChip("70%", oneRepMax * 0.70)
                            oneRmChip("80%", oneRepMax * 0.80)
                            oneRmChip("90%", oneRepMax * 0.90)
                        }.padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(Color(red: 0.13, green: 0.13, blue: 0.15)).cornerRadius(14)

                    // Plate loader
                    VStack(spacing: 8) {
                        Text("Plates per side for \(Int(weight)) kg").font(.caption).foregroundColor(.gray)
                        if platesPerSide.isEmpty {
                            Text("Just the bar").foregroundColor(.white).font(.subheadline)
                        } else {
                            FlowPlates(plates: platesPerSide)
                        }
                    }
                    .frame(maxWidth: .infinity).padding()
                    .background(Color(red: 0.13, green: 0.13, blue: 0.15)).cornerRadius(14)
                }
            }
        }
    }

    private func stepperRow(label: String, value: String, onMinus: @escaping () -> Void, onPlus: @escaping () -> Void) -> some View {
        HStack {
            Text(label).foregroundColor(.white)
            Spacer()
            Button(action: onMinus) { Image(systemName: "minus.circle.fill") }
                .foregroundColor(ThemePalette.accent).font(.title3)
            Text(value).foregroundColor(.white).fontWeight(.semibold).frame(minWidth: 70)
            Button(action: onPlus) { Image(systemName: "plus.circle.fill") }
                .foregroundColor(ThemePalette.accent).font(.title3)
        }
    }
    private func oneRmChip(_ pct: String, _ w: Double) -> some View {
        VStack(spacing: 1) {
            Text(pct).font(.caption2).foregroundColor(.gray)
            Text("\(Int(w.rounded()))kg").font(.caption).foregroundColor(.white).fontWeight(.medium)
        }
    }
}

private struct FlowPlates: View {
    let plates: [Double]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 8) {
            ForEach(Array(plates.enumerated()), id: \.offset) { _, p in
                Text(p == p.rounded() ? "\(Int(p))" : String(format: "%.2f", p))
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(ThemePalette.accent))
            }
        }
    }
}

// MARK: - Macros

struct MacrosView: View {
    @Binding var isPresented: Bool
    let protein: Double
    let carbs: Double
    let fat: Double
    let calorieGoal: Double

    // Standard split of the daily calorie goal: 30% P / 40% C / 30% F.
    private var proteinGoal: Double { (calorieGoal * 0.30) / 4 }
    private var carbGoal: Double { (calorieGoal * 0.40) / 4 }
    private var fatGoal: Double { (calorieGoal * 0.30) / 9 }

    var body: some View {
        ToolScaffold(title: "Today's Macros", isPresented: $isPresented) {
            VStack(spacing: 26) {
                HStack(spacing: 18) {
                    macroRing("Protein", protein, proteinGoal, .pink)
                    macroRing("Carbs", carbs, carbGoal, .orange)
                    macroRing("Fat", fat, fatGoal, .yellow)
                }
                .padding(.top, 12)

                VStack(spacing: 10) {
                    macroBar("Protein", protein, proteinGoal, .pink)
                    macroBar("Carbs", carbs, carbGoal, .orange)
                    macroBar("Fat", fat, fatGoal, .yellow)
                }
                .padding().background(Color(red: 0.13, green: 0.13, blue: 0.15)).cornerRadius(14)

                Text("Goals derived from a \(Int(calorieGoal)) kcal target (30/40/30).")
                    .font(.caption2).foregroundColor(.gray).multilineTextAlignment(.center)
            }
        }
    }

    private func macroRing(_ label: String, _ value: Double, _ goal: Double, _ color: Color) -> some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 8)
                Circle().trim(from: 0, to: goal > 0 ? min(value / goal, 1) : 0)
                    .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(Int(value))g").font(.system(size: 15, weight: .bold, design: .rounded)).foregroundColor(.white)
            }
            .frame(width: 84, height: 84)
            Text(label).font(.caption).foregroundColor(.gray)
        }
    }
    private func macroBar(_ label: String, _ value: Double, _ goal: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.caption).foregroundColor(.white)
                Spacer()
                Text("\(Int(value)) / \(Int(goal))g").font(.caption2).foregroundColor(.gray)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(color).frame(width: geo.size.width * (goal > 0 ? min(value / goal, 1) : 0))
                }
            }.frame(height: 8)
        }
    }
}

// MARK: - Trends (weight + calories)

struct TrendsView: View {
    @Binding var isPresented: Bool
    let healthManager: HealthManager
    let streakManager: StreakManager

    @State private var weightPoints: [WeightPoint] = []

    struct WeightPoint: Identifiable { let id = UUID(); let date: Date; let kg: Double }
    struct CaloriePoint: Identifiable { let id = UUID(); let date: Date; let kcal: Double }

    private var caloriePoints: [CaloriePoint] {
        streakManager.last30Days().compactMap { summary in
            guard let s = summary, s.caloriesConsumed > 0 else { return nil }
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
            guard let d = f.date(from: s.date) else { return nil }
            return CaloriePoint(date: d, kcal: s.caloriesConsumed)
        }
    }

    var body: some View {
        ToolScaffold(title: "Trends", isPresented: $isPresented) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Weight").font(.headline).foregroundColor(.white)
                    if weightPoints.count >= 2 {
                        Chart(weightPoints) { p in
                            LineMark(x: .value("Date", p.date), y: .value("kg", p.kg))
                                .foregroundStyle(ThemePalette.accent)
                                .interpolationMethod(.catmullRom)
                            PointMark(x: .value("Date", p.date), y: .value("kg", p.kg))
                                .foregroundStyle(ThemePalette.accent)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180)
                    } else {
                        emptyState("Log your weight a few times to see the trend.")
                    }

                    Text("Calories (last 30 days)").font(.headline).foregroundColor(.white).padding(.top, 6)
                    if caloriePoints.count >= 2 {
                        Chart(caloriePoints) { p in
                            BarMark(x: .value("Date", p.date, unit: .day), y: .value("kcal", p.kcal))
                                .foregroundStyle(WatchThemeColorBridge.burn)
                        }
                        .frame(height: 170)
                    } else {
                        emptyState("Keep logging meals to build your calorie history.")
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .onAppear(perform: loadWeight)
    }

    private func emptyState(_ text: String) -> some View {
        Text(text).font(.caption).foregroundColor(.gray)
            .frame(maxWidth: .infinity, minHeight: 120)
            .background(Color(red: 0.13, green: 0.13, blue: 0.15)).cornerRadius(12)
    }

    private func loadWeight() {
        // Merge local records with HealthKit history (HealthKit wins on same day).
        var byDay: [String: (Date, Double)] = [:]
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        for p in PersistenceManager.shared.loadWeightHistory() {
            byDay[f.string(from: p.date)] = (p.date, p.weightKg)
        }
        healthManager.fetchWeightHistory(days: 120) { hkPoints in
            for p in hkPoints { byDay[f.string(from: p.date)] = (p.date, p.weightKg) }
            weightPoints = byDay.values.map { WeightPoint(date: $0.0, kg: $0.1) }.sorted { $0.date < $1.date }
        }
    }
}

/// Small color bridge so tools can reuse the app's burn accent without depending on watch code.
enum WatchThemeColorBridge {
    static let burn = Color(red: 1.0, green: 0.45, blue: 0.25)
}

// MARK: - Reminders

struct RemindersView: View {
    @Binding var isPresented: Bool

    @State private var waterOn = ReminderSettings.shared.waterEnabled
    @State private var mealOn = ReminderSettings.shared.mealEnabled

    var body: some View {
        ToolScaffold(title: "Reminders", isPresented: $isPresented) {
            VStack(spacing: 16) {
                toggleCard(
                    title: "Water reminders",
                    subtitle: "Every 2 hours, 9am–9pm",
                    systemImage: "drop.fill",
                    color: .blue,
                    isOn: $waterOn
                )
                .onChange(of: waterOn) { _, on in
                    ReminderSettings.shared.waterEnabled = on
                    if on { NotificationService.shared.scheduleWaterReminders() }
                    else { NotificationService.shared.cancelWaterReminders() }
                }

                toggleCard(
                    title: "Meal reminders",
                    subtitle: "Breakfast 8am · Lunch 1pm · Dinner 8pm",
                    systemImage: "fork.knife",
                    color: .orange,
                    isOn: $mealOn
                )
                .onChange(of: mealOn) { _, on in
                    ReminderSettings.shared.mealEnabled = on
                    if on { NotificationService.shared.scheduleMealReminders() }
                    else { NotificationService.shared.cancelMealReminders() }
                }

                Text("Notifications must be allowed for LifeOS in Settings.")
                    .font(.caption2).foregroundColor(.gray).multilineTextAlignment(.center)
            }
        }
    }

    private func toggleCard(title: String, subtitle: String, systemImage: String, color: Color, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundColor(color).font(.title3).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundColor(.white).fontWeight(.medium)
                Text(subtitle).font(.caption2).foregroundColor(.gray)
            }
            Spacer()
            Toggle("", isOn: isOn).labelsHidden().tint(ThemePalette.accent)
        }
        .padding().background(Color(red: 0.13, green: 0.13, blue: 0.15)).cornerRadius(14)
    }
}
