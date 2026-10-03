import SwiftUI

/// Watch Today (UI/UX Phase 5 §2): the orb glyph with remaining kcal in large
/// numerals, the activity line and the water bar, all sent from the iPhone.
struct WatchDashboardView: View {
    @ObservedObject var session: WatchSessionManager

    private var snapshot: WatchSnapshot { session.snapshot }
    private var remaining: Double { snapshot.calorieLimit - snapshot.caloriesConsumed }
    private var isOver: Bool { snapshot.calorieLimit > 0 && remaining < 0 }

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if !session.hasReceivedData {
                    connectingState
                } else {
                    hero
                    activityLine
                    bar(label: "Water", value: "\(snapshot.waterCount) of \(snapshot.waterTarget)",
                        progress: snapshot.waterProgress, color: WatchTheme.water, systemImage: "drop.fill")
                    chips
                    hint
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .navigationTitle("Today")
    }

    private var connectingState: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("Waiting for your iPhone…")
                .font(.footnote)
                .foregroundStyle(WatchTheme.secondary)
                .multilineTextAlignment(.center)
            Text("Open LifeOS on the iPhone once to sync.")
                .font(.system(size: 11))
                .foregroundStyle(WatchTheme.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }

    private var hero: some View {
        ZStack {
            WatchOrbGlyph(fill: snapshot.calorieLimit > 0 ? snapshot.caloriesConsumed / snapshot.calorieLimit : 0,
                          activity: min(snapshot.caloriesBurned / 400, 1), over: isOver)
            VStack(spacing: 0) {
                Text("\(Int(abs(remaining).rounded()))")
                    .font(WatchTheme.number(32))
                    .minimumScaleFactor(0.6).lineLimit(1)
                Text(isOver ? "kcal over" : "kcal left")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isOver ? WatchTheme.over : WatchTheme.secondary)
            }
            .shadow(color: .black.opacity(0.5), radius: 3)
        }
        .frame(width: 118, height: 118)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isOver ? "Over budget by \(Int(-remaining)) calories"
                                   : "Remaining calories, \(Int(remaining)). Eaten \(Int(snapshot.caloriesConsumed)) of \(Int(snapshot.calorieLimit)).")
    }

    @ViewBuilder private var activityLine: some View {
        if snapshot.caloriesBurned >= 1 {
            Label("\(Int(snapshot.caloriesBurned.rounded())) kcal from training", systemImage: "flame.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(WatchTheme.activity)
                .labelStyle(.titleAndIcon)
        }
    }

    private func bar(label: String, value: String, progress: Double, color: Color, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(label, systemImage: systemImage).foregroundStyle(color)
                Spacer()
                Text(value).font(WatchTheme.number(13, weight: .semibold))
            }
            .font(.system(size: 12, weight: .medium))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.2))
                    Capsule().fill(color).frame(width: geo.size.width * max(0, min(progress, 1)))
                }
            }
            .frame(height: 5)
        }
        .padding(10)
        .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
    }

    private var chips: some View {
        HStack(spacing: 6) {
            chip("\(snapshot.perfectStreak)", caption: "day streak", systemImage: "sparkles", color: WatchTheme.onTrack)
            chip(snapshot.steps > 0 ? snapshot.steps.formatted() : "–", caption: "steps", systemImage: "figure.walk", color: WatchTheme.activity)
        }
    }

    private func chip(_ value: String, caption: String, systemImage: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Image(systemName: systemImage).foregroundStyle(color).font(.system(size: 12))
            Text(value).font(WatchTheme.number(14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            Text(caption).font(.system(size: 10)).foregroundStyle(WatchTheme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(WatchTheme.card, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }

    /// The two workout sources (§2): Apple's Workout app for cardio, LifeOS for gym reps.
    private var hint: some View {
        Text("Use the Workout app for cardio; LifeOS counts your gym reps.")
            .font(.system(size: 11))
            .foregroundStyle(WatchTheme.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 2)
    }
}
