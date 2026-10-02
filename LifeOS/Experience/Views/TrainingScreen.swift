import SwiftUI

/// 3.9 Training: real sessions only (no repeated placeholder treadmill rows),
/// Apple Health activity, and the effect on today's budget.
struct TrainingScreen: View {
    @ObservedObject var store: ExperienceStore
    var onBudget: () -> Void

    @State private var showGym = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LX.Space.s500) {
                Text("Training").lxFont(.titleLarge).foregroundStyle(.lx(.textPrimary))
                    .accessibilityAddTraits(.isHeader)
                effectOnToday
                healthCard
                week
                Button { showGym = true } label: {
                    Label("Log a gym session", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .buttonStyle(.lx(.primary))
            }
            .padding(.horizontal, LX.Space.s400)
            .padding(.top, LX.Space.s400)
            .padding(.bottom, LX.Space.s600)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(isPresented: $showGym) {
            GymWeekView(healthManager: store.health, isPresented: $showGym,
                        onDismiss: { store.afterWrite() }, currentWeight: store.currentWeight)
        }
        .onChange(of: showGym) { _, open in if !open { store.afterWrite() } }
    }

    private var effectOnToday: some View {
        let b = store.budget
        return Button(action: onBudget) {
            VStack(alignment: .leading, spacing: LX.Space.s200) {
                Text("Effect on today").lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.textSecondary)).textCase(.uppercase)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("+\(Int(b.earned))").lxFont(.displayL, numeric: true).foregroundStyle(.lx(.dataActivity)).lxNumberRoll(b.earned)
                    Text("kcal earned").lxFont(.headline).foregroundStyle(.lx(.textSecondary))
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.lx(.textTertiary))
                }
                Text(b.earned > 0
                     ? "\(Int((b.eatBackShare * 100).rounded()))% of \(Int(b.activeEnergy.rounded())) kcal from today's logged sets is added to your budget."
                     : "Log sets or a treadmill session and part of it is added to your budget.")
                    .lxFont(.footnote).foregroundStyle(.lx(.textSecondary)).multilineTextAlignment(.leading)
            }
            .lxCard(padding: LX.Space.s400)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows how your budget is calculated")
    }

    @ViewBuilder private var healthCard: some View {
        let h = store.health
        if h.activeEnergyToday > 0 || h.stepsToday > 0 {
            HStack(spacing: LX.Space.s300) {
                LXMetricTile(label: "Active energy", value: "\(Int(h.activeEnergyToday.rounded()))", unit: "kcal",
                             systemImage: "applewatch", dataRole: .dataActivity, caption: "Apple Health, today")
                LXMetricTile(label: "Steps", value: Int(h.stepsToday).formatted(), systemImage: "figure.walk",
                             dataRole: .dataActivity, caption: "Apple Health, today")
            }
            Text("Apple Watch energy is shown for reference; your budget counts the sessions logged here until Health-based budgets ship.")
                .lxFont(.caption).foregroundStyle(.lx(.textTertiary))
        } else {
            LXInlineBanner(kind: .info, message: "Connect Apple Health to see Watch activity and steps here.",
                           actionTitle: "Connect", action: { h.requestFullAuthorization() })
        }
    }

    private var week: some View {
        let sessions = store.weekWorkouts.filter { $0.workout.totalSets > 0 || $0.workout.treadmillDone }
        return VStack(alignment: .leading, spacing: LX.Space.s300) {
            LXSectionHeader(title: "Last 7 days")
            if sessions.isEmpty {
                LXEmptyState(systemImage: "figure.strengthtraining.traditional", message: "No sessions in the last 7 days.",
                             actionTitle: "Log a session", action: { showGym = true })
                    .lxCard()
            } else {
                ForEach(sessions.reversed(), id: \.date) { s in
                    let kcal = store.workoutKcal(for: s.workout)
                    LXWorkoutCard(title: title(s.workout),
                                  durationMinutes: minutes(s.workout),
                                  earnedKcal: Int((kcal * store.eatBackShare).rounded()),
                                  time: dayLabel(s.date),
                                  systemImage: s.workout.totalSets == 0 ? "figure.run.treadmill" : "figure.strengthtraining.traditional",
                                  source: .manual,
                                  highlight: Calendar.current.isDateInToday(s.date))
                }
            }
        }
    }

    private func title(_ w: DayWorkout) -> String {
        let parts = Array(Set(w.exercises.filter { $0.setsCompleted > 0 }.map(\.bodyPart.rawValue))).sorted()
        if parts.isEmpty { return "Treadmill" }
        return parts.prefix(3).joined(separator: ", ")
    }

    /// 2.5 min per set (the calorie model's assumption) plus treadmill time.
    private func minutes(_ w: DayWorkout) -> Int {
        Int((Double(w.totalSets) * 2.5 + (w.treadmillDone ? w.treadmillDuration : 0)).rounded())
    }

    private func dayLabel(_ d: Date) -> String {
        if Calendar.current.isDateInToday(d) { return "Today" }
        if Calendar.current.isDateInYesterday(d) { return "Yesterday" }
        return d.formatted(.dateTime.weekday(.abbreviated).day())
    }
}
