import SwiftUI
import LifeOSHealth

// Phase 1 Health & Energy surfaces for the current UI (doc 02 §4 P1-B, doc 03 CAL-05).
// The Experience screens (UI/UX Phase 3+) read the same `HealthSync` state.

// MARK: - Workouts feed (WCH-09)

/// Today's workouts from Apple Health with source badges. Tap for details.
struct HealthWorkoutsCard: View {
    @ObservedObject var health: HealthSync = .shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var selected: WorkoutSession?

    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's Activity")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                Spacer()
                if let active = health.activeKcal() {
                    Text("\(Int(active.rounded())) active kcal")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(palette.textSecondary)
                        .contentTransition(.numericText())
                }
            }

            HealthStatusBanner(health: health)

            if health.todaySessions.isEmpty {
                Text(health.status == .connected
                     ? "Workouts you record on Apple Watch appear here automatically."
                     : "Connect Apple Health to bring in your workouts.")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            } else {
                ForEach(health.todaySessions) { session in
                    Button { selected = session } label: { WorkoutRow(session: session, palette: palette) }
                        .buttonStyle(.plain)
                }
            }
        }
        .padding()
        .glassCard(cornerRadius: 20, elevation: 0.5)
        .sheet(item: $selected) { WorkoutDetailSheet(session: $0) }
    }
}

private struct WorkoutRow: View {
    let session: WorkoutSession
    let palette: ThemePalette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: session.kind.symbol)
                .font(.title3)
                .foregroundColor(palette.primaryAccent)
                .frame(width: 36, height: 36)
                .background(Circle().fill(palette.primaryAccent.opacity(0.15)))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.kind.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.textPrimary)
                Text(session.summaryLine)
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            Spacer()
            SourceBadge(text: session.sourceBadge, palette: palette)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct SourceBadge: View {
    let text: String
    let palette: ThemePalette

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(palette.elevatedSurface))
            .foregroundColor(palette.textSecondary)
    }
}

struct WorkoutDetailSheet: View {
    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Type", value: session.kind.displayName)
                    LabeledContent("Time", value: (session.start..<session.end).formatted(.interval.hour().minute()))
                    LabeledContent("Duration", value: "\(Int((session.duration / 60).rounded())) min")
                    if let kcal = session.activeEnergyKcal { LabeledContent("Active energy", value: "\(Int(kcal.rounded())) kcal") }
                    if let meters = session.distanceMeters, meters > 0 {
                        LabeledContent("Distance", value: Measurement(value: meters, unit: UnitLength.meters)
                            .formatted(.measurement(width: .abbreviated, usage: .road)))
                    }
                    if let bpm = session.avgHeartRate { LabeledContent("Avg heart rate", value: "\(Int(bpm.rounded())) bpm") }
                    LabeledContent("Source", value: session.sourceBadge)
                }
                if !session.mergedExerciseIDs.isEmpty {
                    Section {
                        Text("Your logged sets for this session are included. The Watch's measured energy replaces the estimate.")
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle(session.kind.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Permission states (WCH-11)

/// Shown only when Health needs attention (doc 02 §3.6).
struct HealthStatusBanner: View {
    @ObservedObject var health: HealthSync
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL

    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }

    var body: some View {
        switch health.status {
        case .connected:
            EmptyView()
        case .unavailable:
            note("Apple Health isn't available on this device. Your budget uses logged workouts.", action: nil)
        case .notDetermined:
            note("Connect Apple Health so Apple Watch workouts update your budget automatically.",
                 action: ("Connect", { Task { await health.requestAuthorization() } }))
        case .likelyDenied:
            note("Not seeing your workouts? Allow LifeOS to read Activity in Settings → Health → Data Access.",
                 action: ("Open Settings", { if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) } }))
        }
    }

    private func note(_ text: String, action: (String, () -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "heart.text.square.fill").foregroundColor(.pink)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).font(.caption).foregroundColor(palette.textPrimary)
                if let action {
                    Button(action.0, action: action.1)
                        .font(.caption.weight(.semibold))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.pink.opacity(0.1)))
    }
}

// MARK: - "Workout synced" moment (WCH-10)

/// Haptic plus a toast when a new Watch workout lands while the app is open.
struct WorkoutSyncedToast: ViewModifier {
    @State private var message: String?
    @State private var hideTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let message {
                    Text(message)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.top, 8)
                        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                        .accessibilityAddTraits(.isStaticText)
                }
            }
            .sensoryFeedback(.success, trigger: message) { _, new in new != nil }
            .onReceive(NotificationCenter.default.publisher(for: .healthWorkoutSynced)) { note in
                guard let session = note.object as? WorkoutSession else { return }
                show(session.toastText)
            }
    }

    private func show(_ text: String) {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.4, bounce: 0.2)) { message = text }
        UIAccessibility.post(notification: .announcement, argument: text)
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { message = nil }
        }
    }
}

extension View {
    func workoutSyncedToast() -> some View { modifier(WorkoutSyncedToast()) }
}

// MARK: - Budget settings (CAL-05)

struct EnergySettingsCard: View {
    @ObservedObject var health: HealthSync = .shared
    @Environment(\.colorScheme) private var colorScheme

    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Exercise & Budget")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            Picker("Budget", selection: Binding(
                get: { health.settings.modePreference },
                set: { mode in health.updateSettings { $0.modePreference = mode } })) {
                Text("Adds exercise").tag(EnergySettings.ModePreference.automatic)
                Text("Fixed").tag(EnergySettings.ModePreference.fixed)
            }
            .pickerStyle(.segmented)
            .disabled(health.settings.manualTarget != nil)

            Text(modeExplanation)
                .font(.caption)
                .foregroundColor(palette.textSecondary)

            if health.settings.modePreference == .automatic, health.settings.manualTarget == nil {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Eat back").foregroundColor(palette.textPrimary)
                        Spacer()
                        Text("\(Int((health.settings.eatBack * 100).rounded()))%")
                            .foregroundColor(palette.primaryAccent).fontWeight(.semibold)
                    }
                    .font(.subheadline)
                    Slider(value: Binding(get: { health.settings.eatBack },
                                          set: { v in health.updateSettings { $0.eatBack = v } }),
                           in: 0...1, step: 0.1)
                    Text("Share of exercise calories added to today's budget. Watch estimates run high, so 30–50% is typical.")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                }

                Stepper(value: Binding(get: { health.settings.cap },
                                       set: { v in health.updateSettings { $0.cap = v } }),
                        in: 300...1500, step: 100) {
                    Text("Daily exercise cap: \(Int(health.settings.cap)) kcal")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                }
            }

            if let lastSync = health.lastSync {
                Text("Apple Health synced \(lastSync.formatted(.relative(presentation: .named)))")
                    .font(.caption2)
                    .foregroundColor(palette.textSecondary)
            }
        }
        .padding()
        .glassCard(cornerRadius: 20, elevation: 0.5)
    }

    private var modeExplanation: String {
        if health.settings.manualTarget != nil {
            return "You set a custom target, so it stays fixed. Pick Automatic in Daily Calorie Target to add exercise."
        }
        switch health.settings.modePreference {
        case .fixed:
            return "Your budget stays the same every day and assumes your usual activity."
        case .automatic:
            switch health.energyByDay[.today()]?.budgetMode {
            case .measured?: return "Using Apple Watch active energy above your everyday movement."
            default: return "Using your logged workouts until Apple Watch data covers 3 of the last 7 days."
            }
        }
    }
}

// MARK: - Save to Apple Health (WCH-08)

/// Settings toggle for mirroring the food and water log into Apple Health.
struct SaveToHealthCard: View {
    @ObservedObject var health: HealthSync = .shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var isUpdating = false

    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }

    var body: some View {
        if health.status != .unavailable {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(get: { health.savesToHealth }, set: { enabled in
                    isUpdating = true
                    Task {
                        await health.setSavesToHealth(enabled)
                        isUpdating = false
                    }
                })) {
                    Text("Save food & water to Apple Health")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.textPrimary)
                }
                .tint(palette.primaryAccent)
                .disabled(isUpdating)

                Text(footnote)
                    .font(.caption)
                    .foregroundColor(missingAccess ? .orange : palette.textSecondary)
            }
            .padding()
            .glassCard(cornerRadius: 20, elevation: 0.5)
        }
    }

    private var missingAccess: Bool {
        health.savesToHealth && health.writableKinds != Set(HealthWriteKind.allCases)
    }

    private var footnote: String {
        guard health.savesToHealth else {
            return "Calories, protein, carbs, fat and water from today on. Edits and deletes are mirrored."
        }
        switch (health.writableKinds.contains(.food), health.writableKinds.contains(.water)) {
        case (true, true): return "Today's log and everything you add from now on appear in Health › Nutrition."
        case (false, true): return "Water is saved. To save food, allow Dietary Energy in Settings › Health › Data Access › LifeOS."
        case (true, false): return "Food is saved. To save water, allow Water in Settings › Health › Data Access › LifeOS."
        case (false, false): return "LifeOS can't write to Health. Allow it in Settings › Health › Data Access › LifeOS."
        }
    }
}

// MARK: - Formatting

extension ActivityKind {
    var symbol: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .run: return "figure.run"
        case .walk: return "figure.walk"
        case .cycle: return "figure.outdoor.cycle"
        case .hiit: return "flame.fill"
        case .yoga: return "figure.yoga"
        case .swim: return "figure.pool.swim"
        case .other: return "figure.mixed.cardio"
        }
    }
}

extension WorkoutSession {
    var summaryLine: String {
        var parts = ["\(Int((duration / 60).rounded())) min"]
        if let kcal = activeEnergyKcal { parts.append("\(Int(kcal.rounded())) kcal") }
        if let meters = distanceMeters, meters > 50 { parts.append(String(format: "%.1f km", meters / 1000)) }
        if let bpm = avgHeartRate { parts.append("\(Int(bpm.rounded())) bpm") }
        return parts.joined(separator: " · ")
    }

    var toastText: String {
        if let kcal = activeEnergyKcal { return "\(kind.displayName) · +\(Int(kcal.rounded())) kcal synced" }
        return "\(kind.displayName) synced from \(sourceBadge)"
    }
}
