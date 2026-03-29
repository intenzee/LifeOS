
import SwiftUI

struct StreaksView: View {
    @StateObject private var streakManager = StreakManager.shared
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            palette.screenBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    perfectDayBanner
                    streakCardsSection
                    heatmapSection
                    last7DaysSection
                    Spacer(minLength: 40)
                }
                .padding(.horizontal)
                .padding(.top, 20)
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Streaks")
                    .font(.largeTitle)
                    .fontWeight(.semibold)
                    .foregroundColor(palette.textPrimary)
                Text("Your consistency over time")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Perfect Day Banner
    private var perfectDayBanner: some View {
        let streak = streakManager.perfectDayStreak
        return VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("🏆")
                            .font(.title2)
                        Text("Perfect Day Streak")
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)
                    }
                    Text("Hit all 4 goals: calories, water, gym & todos")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(streak)")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundColor(streak > 0 ? .yellow : .gray)
                    Text(streak == 1 ? "day" : "days")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            }

            // Score ring for today
            if let today = streakManager.summaries[streakManager.dateKey(for: Date())] {
                todayScoreBar(score: today.score)
            } else {
                todayScoreBar(score: 0)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    streak > 0
                    ? LinearGradient(colors: [Color.yellow.opacity(0.25), Color.orange.opacity(0.15)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    : LinearGradient(colors: [Color(red: 0.12, green: 0.12, blue: 0.14), Color(red: 0.12, green: 0.12, blue: 0.14)], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(streak > 0 ? Color.yellow.opacity(0.4) : Color.clear, lineWidth: 1)
                )
        )
    }

    private func todayScoreBar(score: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's score: \(score)/4")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
            HStack(spacing: 8) {
                scoreChip("🔥 Cal", score >= 1)
                scoreChip("💧 Water", score >= 2)
                scoreChip("💪 Gym", score >= 3)
                scoreChip("✅ Todos", score >= 4)
            }
        }
    }

    private func scoreChip(_ label: String, _ achieved: Bool) -> some View {
        Text(label)
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(achieved ? .white : .gray)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(achieved ? Color.green.opacity(0.3) : Color(red: 0.15, green: 0.15, blue: 0.17))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(achieved ? Color.green.opacity(0.6) : Color.clear, lineWidth: 1)
                    )
            )
    }

    // MARK: - Individual Streak Cards
    private var streakCardsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Individual Streaks")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                streakCard(
                    icon: "🔥",
                    title: "Calorie Goal",
                    subtitle: "Under daily limit",
                    streak: streakManager.calorieStreak,
                    color: .orange
                )
                streakCard(
                    icon: "💧",
                    title: "Water Goal",
                    subtitle: "Hit daily target",
                    streak: streakManager.waterStreak,
                    color: .blue
                )
                streakCard(
                    icon: "💪",
                    title: "Gym",
                    subtitle: "Medium or High intensity",
                    streak: streakManager.gymStreak,
                    color: .green
                )
                streakCard(
                    icon: "✅",
                    title: "All Todos",
                    subtitle: "100% completion",
                    streak: streakManager.todoStreak,
                    color: .purple
                )
            }
        }
    }

    private func streakCard(icon: String, title: String, subtitle: String, streak: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(icon)
                    .font(.title2)
                Spacer()
                if streak > 0 {
                    HStack(spacing: 2) {
                        Text("🔥")
                            .font(.caption)
                        Text("\(streak)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(color)
                    }
                }
            }
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(palette.textPrimary)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(palette.textSecondary)
            Text("\(streak) \(streak == 1 ? "day" : "days")")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(streak > 0 ? color : .gray)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(palette.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(streak > 0 ? color.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }

    // MARK: - 30-Day Heatmap
    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("30-Day Heatmap")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            let days = streakManager.last30Days()

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 10), spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { index, summary in
                    heatCell(summary: summary)
                }
            }

            // Legend
            HStack(spacing: 12) {
                legendItem(color: .gray.opacity(0.3), label: "No data")
                legendItem(color: .red.opacity(0.6), label: "0/4")
                legendItem(color: .orange.opacity(0.7), label: "1–2/4")
                legendItem(color: .yellow.opacity(0.8), label: "3/4")
                legendItem(color: .green, label: "4/4 ✨")
            }
            .padding(.top, 4)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                        .fill(palette.surface)
        )
    }

    private func heatCell(summary: DailySummary?) -> some View {
        let color: Color = {
            guard let s = summary else { return Color.gray.opacity(0.2) }
            switch s.score {
            case 4: return Color.green.opacity(0.85)
            case 3: return Color.yellow.opacity(0.7)
            case 1, 2: return Color.orange.opacity(0.6)
            default: return Color.red.opacity(0.4)
            }
        }()
        return RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .frame(height: 22)
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: 12, height: 12)
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Last 7 Days Detail
    private var last7DaysSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 Days")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            VStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { offset in
                    if let date = Calendar.current.date(byAdding: .day, value: -(6 - offset), to: Date()) {
                        let key = streakManager.dateKey(for: date)
                        let summary = streakManager.summaries[key]
                        dayRow(date: date, summary: summary)
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

    private func dayRow(date: Date, summary: DailySummary?) -> some View {
        let isToday = Calendar.current.isDateInToday(date)
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, MMM d"

        return HStack(spacing: 12) {
            Text(isToday ? "Today" : formatter.string(from: date))
                .font(.subheadline)
                .foregroundColor(isToday ? .blue : palette.textPrimary)
                .frame(width: 100, alignment: .leading)

            if let s = summary {
                HStack(spacing: 6) {
                    miniGoalDot(hit: s.hitCalorieGoal, color: .orange)
                    miniGoalDot(hit: s.hitWaterGoal, color: .blue)
                    miniGoalDot(hit: s.hitGymGoal, color: .green)
                    miniGoalDot(hit: s.hitTodoGoal, color: .purple)
                }

                Spacer()

                Text("\(s.score)/4")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(s.score == 4 ? .green : s.score >= 2 ? .orange : .gray)

                if s.isPerfectDay {
                    Text("🏆")
                        .font(.subheadline)
                }
            } else {
                Text("No data")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                Spacer()
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isToday ? Color.blue.opacity(0.1) : palette.elevatedSurface)
        )
    }

    private func miniGoalDot(hit: Bool, color: Color) -> some View {
        Circle()
            .fill(hit ? color : Color.gray.opacity(0.25))
            .frame(width: 10, height: 10)
    }
}
