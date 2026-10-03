import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// Phase 5 §4: gym session + rest timer on the Lock Screen and in the Dynamic Island.
struct LifeOSLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LifeOSActivityAttributes.self) { context in
            LockScreenActivityView(state: context.state, startedAt: context.attributes.startedAt)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(WidgetPalette.energy)
                .widgetURL(LifeOSShared.url("training"))
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("\(s.setsDone)/\(s.setsTotal)", systemImage: "figure.strengthtraining.traditional")
                        .font(.headline).monospacedDigit().foregroundStyle(WidgetPalette.energy)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let end = s.restEndsAt, s.resting() {
                        Text(timerInterval: Date()...end, countsDown: true).font(.headline).monospacedDigit().multilineTextAlignment(.trailing)
                    } else {
                        Text(context.attributes.startedAt, style: .timer).font(.headline).monospacedDigit().multilineTextAlignment(.trailing)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(s.exercise).font(.subheadline.weight(.semibold)).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        if let next = s.nextExercise { Text("Next: \(next)").font(.caption).foregroundStyle(.secondary).lineLimit(1) }
                        Spacer()
                        if s.resting() {
                            Button(intent: SkipRestActivityIntent()) { Label("Skip", systemImage: "forward.fill") }.tint(.gray)
                        } else if !s.finished {
                            Button(intent: LogSetActivityIntent()) { Label("Log set", systemImage: "plus") }.tint(WidgetPalette.energy)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(WidgetPalette.energy)
            } compactTrailing: {
                if let end = s.restEndsAt, s.resting() {
                    ProgressView(timerInterval: Date()...end, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                        .progressViewStyle(.circular).tint(WidgetPalette.energy).frame(width: 18, height: 18)
                } else {
                    Text("\(s.setsDone)/\(s.setsTotal)").monospacedDigit().foregroundStyle(WidgetPalette.energy)
                }
            } minimal: {
                Image(systemName: s.resting() ? "timer" : "figure.strengthtraining.traditional").foregroundStyle(WidgetPalette.energy)
            }
            .widgetURL(LifeOSShared.url("training"))
            .keylineTint(WidgetPalette.energy)
        }
    }
}

struct LockScreenActivityView: View {
    let state: LifeOSActivityAttributes.ContentState
    let startedAt: Date

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                if let end = state.restEndsAt, state.resting() {
                    ProgressView(timerInterval: Date()...end, countsDown: true) { EmptyView() } currentValueLabel: {
                        Text(timerInterval: Date()...end, countsDown: true).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                    }
                    .progressViewStyle(.circular).tint(WidgetPalette.energy)
                } else {
                    Gauge(value: Double(state.setsDone), in: 0...Double(max(state.setsTotal, 1))) {
                        EmptyView()
                    } currentValueLabel: {
                        Text("\(state.setsDone)/\(state.setsTotal)").monospacedDigit()
                    }
                    .gaugeStyle(.accessoryCircularCapacity).tint(WidgetPalette.energy)
                }
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.finished ? "Session done" : (state.resting() ? "Resting" : state.exercise))
                    .font(.headline).lineLimit(1)
                Text(state.resting() ? (state.nextExercise.map { "Next: \($0)" } ?? state.exercise)
                                     : "Set \(min(state.setsDone + 1, max(state.setsTotal, 1))) of \(state.setsTotal) · \(state.setsToday) sets today")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).monospacedDigit()
                Text(startedAt, style: .timer).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
            if !state.finished {
                if state.resting() {
                    Button(intent: SkipRestActivityIntent()) { Label("Skip", systemImage: "forward.fill") }
                        .tint(.gray)
                } else {
                    Button(intent: LogSetActivityIntent()) { Label("Log set", systemImage: "plus") }
                        .tint(WidgetPalette.energy)
                }
            }
        }
        .padding(14)
    }
}
