import LifeOSConnectivity
import SwiftUI
import WidgetKit

// WCH-15: watch-face complications and Smart Stack widgets. Everything they show
// comes from the phone through the watch app (`ComplicationStore`); the
// timelines only add the moments the display changes on its own (midnight,
// the training window, meal slots).

@main
struct LifeOSWatchWidgets: WidgetBundle {
    var body: some Widget {
        BudgetComplication()
        StartWorkoutWidget()
        WaterComplication()
        StreakComplication()
    }
}

enum WatchWidgetKind {
    static let budget = "lx.watch.budget"
    static let workout = "lx.watch.workout"
    static let water = "lx.watch.water"
    static let streak = "lx.watch.streak"
}

enum WatchWidgetLink {
    static let today = URL(string: "lifeos://watch/today")!
    static let workout = URL(string: "lifeos://watch/workout")!
    static let water = URL(string: "lifeos://watch/water")!
}

// MARK: - Timeline

struct ComplicationEntry: TimelineEntry {
    let date: Date
    /// `nil` until the phone has sent a snapshot.
    let snapshot: ComplicationSnapshot?
    let showsPreset: Bool
    let relevance: TimelineEntryRelevance?
}

struct ComplicationProvider: TimelineProvider {
    /// Which Smart Stack relevance the entries carry.
    enum Relevance {
        case none, today, workout
    }

    var relevance: Relevance = .none

    func placeholder(in context: Context) -> ComplicationEntry {
        ComplicationEntry(date: Date(), snapshot: .placeholder, showsPreset: true, relevance: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (ComplicationEntry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
        } else {
            completion(entries(now: Date()).first ?? placeholder(in: context))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ComplicationEntry>) -> Void) {
        // `.atEnd`: the entries run a day ahead, and the watch app reloads
        // as soon as the phone sends anything new.
        completion(Timeline(entries: entries(now: Date()), policy: .atEnd))
    }

    private func entries(now: Date) -> [ComplicationEntry] {
        ComplicationTimeline.entries(for: ComplicationStore.read(), now: now).map { entry in
            let score: TimelineEntryRelevance?
            switch relevance {
            case .none:
                score = nil
            case .today:
                score = TimelineEntryRelevance(score: Float(entry.todayRelevance))
            case .workout:
                score = TimelineEntryRelevance(score: Float(entry.workoutRelevance),
                                               duration: entry.workoutRelevanceDuration)
            }
            return ComplicationEntry(date: entry.date, snapshot: entry.snapshot, showsPreset: entry.showsPreset,
                                     relevance: score)
        }
    }
}

// MARK: - Widgets

/// Calories left: the orb gauge, the curved corner gauge, the inline line and
/// the rectangular "640 left · 96 g protein" card (also the Smart Stack Today card).
struct BudgetComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.budget, provider: ComplicationProvider(relevance: .today)) { entry in
            BudgetComplicationView(entry: entry)
                .widgetURL(WatchWidgetLink.today)
                .containerBackground(for: .widget) { WatchTheme.energy.opacity(0.25) }
        }
        .configurationDisplayName("Calories left")
        .description("Today's remaining calories from your LifeOS budget.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

/// "Start workout", raised in the Smart Stack around the user's usual training time.
struct StartWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.workout, provider: ComplicationProvider(relevance: .workout)) { entry in
            StartWorkoutView(entry: entry)
                .widgetURL(WatchWidgetLink.workout)
                .containerBackground(for: .widget) { WatchTheme.activity.opacity(0.25) }
        }
        .configurationDisplayName("Start workout")
        .description("Opens a LifeOS strength workout. Suggested around your usual training time.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular])
    }
}

struct WaterComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.water, provider: ComplicationProvider()) { entry in
            WaterComplicationView(entry: entry)
                .widgetURL(WatchWidgetLink.water)
                .containerBackground(for: .widget) { WatchTheme.water.opacity(0.25) }
        }
        .configurationDisplayName("Water")
        .description("Glasses of water today.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct StreakComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WatchWidgetKind.streak, provider: ComplicationProvider()) { entry in
            StreakComplicationView(entry: entry)
                .widgetURL(WatchWidgetLink.today)
                .containerBackground(for: .widget) { WatchTheme.onTrack.opacity(0.25) }
        }
        .configurationDisplayName("Streak")
        .description("Your perfect-day streak.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}
