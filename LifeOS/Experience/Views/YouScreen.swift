import SwiftUI

/// "You" tab: goal and body, streaks, todos, and the doors to the classic
/// Settings, Profile and Todo screens (which Phase 3 does not redesign yet).
struct YouScreen: View {
    @ObservedObject var store: ExperienceStore
    // Phase 4 doors
    var onMemory: () -> Void = {}
    var onAutomations: () -> Void = {}
    var onPrivacy: () -> Void = {}
    var onWeeklyReview: (() -> Void)? = nil
    // Phase 5 doors
    var onData: () -> Void = {}
    var onRefreshHelp: () -> Void = {}
    var onAchievements: () -> Void = {}
    @ObservedObject private var backup = BackupService.shared
    @AppStorage("lx.newExperience") private var newExperience = true
    @Environment(\.lxTheme) private var theme

    @State private var showWeight = false
    @State private var showSettings = false
    @State private var showProfile = false
    @State private var showTodos = false
    @State private var showStreaks = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LX.Space.s500) {
                Text("You").lxFont(.titleLarge).foregroundStyle(.lx(.textPrimary)).accessibilityAddTraits(.isHeader)
                if let message = backup.refreshMessage {
                    // Phase 5 §9.1: calm, never blocking.
                    LXInlineBanner(kind: .info, message: message, actionTitle: "How to refresh", action: onRefreshHelp)
                }
                goalCard
                streaks
                todos
                more
            }
            .padding(.horizontal, LX.Space.s400)
            .padding(.top, LX.Space.s400)
            .padding(.bottom, LX.Space.s600)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showWeight) { WeightQuickSheet(store: store).lxSheetStyle(detents: [.medium]) }
        .sheet(isPresented: $showSettings, onDismiss: { store.afterWrite() }) { NavigationStack { SettingsView() } }
        .sheet(isPresented: $showProfile, onDismiss: { store.reload(); store.afterWrite() }) { ProfileHubView(isPresented: $showProfile) }
        .sheet(isPresented: $showTodos, onDismiss: { store.reload(); store.afterWrite() }) { TodoTabView() }
        .sheet(isPresented: $showStreaks) { StreaksView() }
    }

    private var goalCard: some View {
        let p = store.profile
        let units = p?.units
        return VStack(alignment: .leading, spacing: LX.Space.s300) {
            HStack {
                if let goal = p?.goal {
                    Label(goal.rawValue, systemImage: goal.icon).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                } else {
                    Text("Your goal").lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                }
                Spacer()
                Button("Log weight") { showWeight = true }.buttonStyle(.lx(.secondary))
            }
            HStack(spacing: LX.Space.s300) {
                LXMetricTile(label: "Now", value: store.currentWeight > 0 ? ExperienceStore.weightText(store.currentWeight, units: units) : "–",
                             systemImage: "scalemass.fill", dataRole: .dataWeight)
                LXMetricTile(label: "Target", value: store.targetWeight > 0 ? ExperienceStore.weightText(store.targetWeight, units: units) : "–",
                             systemImage: "flag.checkered", dataRole: .dataWeight)
            }
            Text("Daily limit \(Int(store.budget.baseLimit).formatted()) kcal · \(store.calorieLimitIsManual ? "custom" : "recommended from your profile")")
                .lxFont(.footnote, numeric: true).foregroundStyle(.lx(.textSecondary))
        }
        .lxCard(padding: LX.Space.s400)
    }

    private var streaks: some View {
        let m = store.dependencies.streakManager
        return VStack(alignment: .leading, spacing: LX.Space.s200) {
            LXSectionHeader(title: "Streaks", action: "History") { showStreaks = true }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: LX.Space.s300), GridItem(.flexible())], spacing: LX.Space.s300) {
                LXMetricTile(label: "Perfect days", value: "\(m.perfectDayStreak)", unit: "days", systemImage: "sparkles", dataRole: .statusOnTrack,
                             caption: "Today \(store.todayScore) of 4")
                LXMetricTile(label: "On budget", value: "\(m.calorieStreak)", unit: "days", systemImage: "flame.fill", dataRole: .dataEnergy)
                LXMetricTile(label: "Water", value: "\(m.waterStreak)", unit: "days", systemImage: "drop.fill", dataRole: .dataWater)
                LXMetricTile(label: "Gym", value: "\(m.gymStreak)", unit: "days", systemImage: "figure.strengthtraining.traditional", dataRole: .dataActivity)
            }
        }
    }

    private var todos: some View {
        VStack(alignment: .leading, spacing: LX.Space.s200) {
            LXSectionHeader(title: "Todos", action: "All todos") { showTodos = true }
            if store.todos.isEmpty {
                Text("Nothing planned for this day.").lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lxCard(padding: LX.Space.s400)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.todos, id: \.id) { todo in
                        Button { store.toggleTodo(todo.id) } label: {
                            HStack(spacing: LX.Space.s300) {
                                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle").font(.title3)
                                    .foregroundStyle(todo.isCompleted ? .lx(.statusOnTrack) : .lx(.textTertiary))
                                Text(todo.title).lxFont(.body).foregroundStyle(todo.isCompleted ? .lx(.textSecondary) : .lx(.textPrimary))
                                    .strikethrough(todo.isCompleted)
                                Spacer()
                                if let r = todo.reminderDate {
                                    Text(r.formatted(date: .omitted, time: .shortened)).lxFont(.caption, numeric: true).foregroundStyle(.lx(.textTertiary))
                                }
                            }
                            .frame(minHeight: LX.Space.minTouchTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .lxCard(padding: LX.Space.s400)
            }
        }
    }

    private var more: some View {
        VStack(spacing: 0) {
            row("What LifeOS knows", "brain.head.profile") { onMemory() }
            Rectangle().fill(.lx(.separator)).frame(height: 0.5)
            row("Automations", "bolt.badge.clock") { onAutomations() }
            Rectangle().fill(.lx(.separator)).frame(height: 0.5)
            row("AI and privacy", "lock.shield") { onPrivacy() }
            Rectangle().fill(.lx(.separator)).frame(height: 0.5)
            if let onWeeklyReview {
                row("Weekly review", "book.pages") { onWeeklyReview() }
                Rectangle().fill(.lx(.separator)).frame(height: 0.5)
            }
            row("Achievements", "medal") { onAchievements() }
            Rectangle().fill(.lx(.separator)).frame(height: 0.5)
            row("Data and backup", "externaldrive") { onData() }
            Rectangle().fill(.lx(.separator)).frame(height: 0.5)
            row("Profile and health details", "person.text.rectangle") { showProfile = true }
            Rectangle().fill(.lx(.separator)).frame(height: 0.5)
            row("Settings", "gearshape") { showSettings = true }
            Rectangle().fill(.lx(.separator)).frame(height: 0.5)
            Toggle(isOn: $newExperience) {
                Label("New layout (Phase 3 preview)", systemImage: "sparkles.rectangle.stack").lxFont(.body).foregroundStyle(.lx(.textPrimary))
            }
            .tint(theme.color(.accentPrimary))
            .frame(minHeight: 52)
        }
        .padding(.horizontal, LX.Space.s400)
        .lxCard(padding: 0)
    }

    private func row(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon).lxFont(.body).foregroundStyle(.lx(.textPrimary))
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.lx(.textTertiary))
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
