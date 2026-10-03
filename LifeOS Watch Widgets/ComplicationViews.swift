import LifeOSConnectivity
import SwiftUI
import WidgetKit

// WCH-15 views, following UI/UX Phase 5 §2. In tinted faces only the gauges and
// numbers are accentable, never the label text. Accessibility labels match
// Watch Today.

private extension ComplicationSnapshot {
    var remainingText: String { Int(abs(remainingKcal).rounded()).formatted() }
    var budgetColor: Color { isOver ? WatchTheme.over : WatchTheme.energy }
    var budgetAccessibility: String {
        let kcal = Int(abs(remainingKcal).rounded())
        return isOver ? "Over budget by \(kcal) calories" : "Remaining calories, \(kcal)"
    }
}

/// Shown before the phone has sent a budget.
private struct NoDataGlyph: View {
    var systemImage: String

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: systemImage).font(.title3)
        }
        .accessibilityLabel("Open LifeOS on your iPhone to sync")
    }
}

// MARK: - Calories left

struct BudgetComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot, s.hasBudget {
            content(s)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(s.budgetAccessibility)
        } else {
            switch family {
            case .accessoryInline: Text("LifeOS: open on iPhone")
            case .accessoryRectangular:
                VStack(alignment: .leading) {
                    Text("LifeOS").font(.headline)
                    Text("Open LifeOS on your iPhone to sync.").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            default: NoDataGlyph(systemImage: "flame")
            }
        }
    }

    @ViewBuilder private func content(_ s: ComplicationSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: s.fill) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text(s.remainingText).font(WatchTheme.number(15)).minimumScaleFactor(0.5)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(s.budgetColor)
            .widgetAccentable()

        case .accessoryCorner:
            Text(s.remainingText)
                .font(WatchTheme.number(18))
                .widgetAccentable()
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: s.fill) {
                        Text("kcal")
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("")
                    } maximumValueLabel: {
                        Text(s.isOver ? "over" : "left")
                    }
                    .tint(s.budgetColor)
                }

        case .accessoryInline:
            Label(s.isOver ? "\(s.remainingText) kcal over" : "\(s.remainingText) kcal left",
                  systemImage: "flame.fill")

        default:
            rectangular(s)
        }
    }

    /// "640 left · 96 g protein", the bar, then the preset or eaten/budget.
    private func rectangular(_ s: ComplicationSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text(s.remainingText)
                    .font(WatchTheme.number(20))
                    .foregroundStyle(s.budgetColor)
                    .widgetAccentable()
                Text(s.isOver ? "over" : "left").font(.caption2).foregroundStyle(.secondary)
                if let protein = s.proteinG {
                    Text("· \(Int(protein.rounded())) g protein")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            Gauge(value: s.fill) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(s.budgetColor)
                .widgetAccentable()
            if entry.showsPreset, let preset = s.preset {
                Text("Next: \(preset.name) · \(Int(preset.kcal.rounded())) kcal")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Text("\(Int(s.eatenKcal.rounded()).formatted()) of \(Int(s.budgetKcal.rounded()).formatted()) kcal")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Start workout

struct StartWorkoutView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "dumbbell.fill").font(.title3).widgetAccentable()
            }
            .accessibilityLabel("Start workout")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label("Start workout", systemImage: "dumbbell.fill")
                    .font(.headline)
                    .foregroundStyle(WatchTheme.activity)
                    .widgetAccentable()
                Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    private var detail: String {
        guard let s = entry.snapshot else { return "Counts your reps and saves to Apple Health." }
        if s.workoutActive { return "Workout in progress" }
        if s.trainedToday {
            return s.earnedKcal >= 1 ? "Trained today · +\(Int(s.earnedKcal.rounded())) earned" : "Trained today"
        }
        if let window = s.trainingWindow?.interval(on: s.day) {
            let range = (window.start..<window.end).formatted(.interval.hour().minute())
            return "Your usual time: \(range)"
        }
        return "Counts your reps and saves to Apple Health."
    }
}

// MARK: - Water

struct WaterComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot {
            content(s)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Water, \(s.waterGlasses) of \(s.waterTarget) glasses")
        } else if family == .accessoryInline {
            Text("Water: open LifeOS")
        } else {
            NoDataGlyph(systemImage: "drop")
        }
    }

    @ViewBuilder private func content(_ s: ComplicationSnapshot) -> some View {
        switch family {
        case .accessoryCorner:
            Image(systemName: "drop.fill")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel {
                    Gauge(value: s.waterFill) {
                        Text("Water")
                    } currentValueLabel: {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("")
                    } maximumValueLabel: {
                        Text("\(s.waterGlasses)/\(s.waterTarget)")
                    }
                    .tint(WatchTheme.water)
                }
        case .accessoryInline:
            Label("\(s.waterGlasses) of \(s.waterTarget) glasses", systemImage: "drop.fill")
        default:
            Gauge(value: s.waterFill) {
                Image(systemName: "drop.fill")
            } currentValueLabel: {
                Text("\(s.waterGlasses)").font(WatchTheme.number(16))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(WatchTheme.water)
            .widgetAccentable()
        }
    }
}

// MARK: - Streak

struct StreakComplicationView: View {
    let entry: ComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot {
            content(s)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Perfect-day streak, \(s.streak) \(s.streak == 1 ? "day" : "days")")
        } else if family == .accessoryInline {
            Text("Streak: open LifeOS")
        } else {
            NoDataGlyph(systemImage: "star")
        }
    }

    @ViewBuilder private func content(_ s: ComplicationSnapshot) -> some View {
        switch family {
        case .accessoryInline:
            Label("\(s.streak)-day streak", systemImage: "star.fill")
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "star.fill").font(.system(size: 12)).foregroundStyle(WatchTheme.onTrack)
                    Text("\(s.streak)").font(WatchTheme.number(18)).minimumScaleFactor(0.6)
                }
                .widgetAccentable()
            }
        }
    }
}
