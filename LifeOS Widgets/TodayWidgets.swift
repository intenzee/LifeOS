import AppIntents
import SwiftUI
import WidgetKit

// Phase 5 §3: Home Screen, Lock Screen and StandBy widgets. Same data colours
// as the app, monospaced digits, no 3D (a 2D orb glyph). Designed for full
// colour, tinted and clear: anything that should take the tint is
// `.widgetAccentable()`.

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(entry(at: Date(), preview: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        // The app reloads us after every change; this only covers midnight and stale data.
        let midnight = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400 + 60)
        let next = min(now.addingTimeInterval(30 * 60), midnight)
        completion(Timeline(entries: [entry(at: now, preview: false)], policy: .after(next)))
    }

    private func entry(at date: Date, preview: Bool) -> TodayEntry {
        if let s = WidgetStore.read() { return TodayEntry(date: date, snapshot: s.forDisplay(now: date), isPlaceholder: false) }
        return TodayEntry(date: date, snapshot: .placeholder, isPlaceholder: !preview)
    }
}

// MARK: - Pieces

struct WidgetOrb: View {
    let s: WidgetSnapshot
    var lineWidth: CGFloat = 8
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        ZStack {
            if mode == .fullColor {
                Circle().fill(RadialGradient(colors: [(s.isOver ? WidgetPalette.over : WidgetPalette.energy).opacity(0.28), .clear],
                                             center: .center, startRadius: 2, endRadius: 60))
            }
            Circle().stroke(Color.primary.opacity(0.15), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(s.fill, 0), 1))
                .stroke(s.isOver ? WidgetPalette.over : WidgetPalette.energy, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .accessibilityHidden(true)
    }
}

struct RemainingText: View {
    let s: WidgetSnapshot
    var size: CGFloat = 30

    var body: some View {
        VStack(spacing: 0) {
            Text(abs(s.remaining).formatted(.number.precision(.fractionLength(0))))
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
                .contentTransition(.numericText())
            Text(s.isOver ? "kcal over" : "kcal left")
                .font(.system(size: max(size * 0.36, 10), weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

private func remainingLabel(_ s: WidgetSnapshot) -> String {
    s.isOver ? "Over budget by \(Int(-s.remaining)) calories" : "\(Int(s.remaining)) calories left today"
}

private struct MacroBar: View {
    let label: String
    let value: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(value).monospacedDigit()
            }
            .font(.system(size: 11, weight: .medium))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.2))
                    Capsule().fill(color).frame(width: geo.size.width * min(max(progress, 0), 1)).widgetAccentable()
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Small (Today) + Lock Screen + StandBy

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LifeOSShared.Kind.today, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Calories left today, with what you've earned from activity.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    var body: some View {
        let s = entry.snapshot
        content(s)
            .redacted(reason: entry.isPlaceholder ? .placeholder : [])
            .widgetURL(LifeOSShared.url("today"))
            .containerBackground(for: .widget) { Color.clear.background(.background) }
    }

    @ViewBuilder private func content(_ s: WidgetSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: min(max(s.fill, 0), 1)) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text(Int(abs(s.remaining)).formatted(.number.notation(.compactName))).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel(remainingLabel(s))
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(s.isOver ? "\(Int(-s.remaining)) over" : "\(Int(s.remaining)) left")
                    .font(.headline).monospacedDigit().widgetAccentable()
                Text("\(Int(s.proteinG)) g protein · \(s.water) of \(s.waterTarget) glasses").font(.caption).monospacedDigit()
                ProgressView(value: min(max(s.fill, 0), 1)).tint(s.isOver ? WidgetPalette.over : WidgetPalette.energy)
            }
            .accessibilityElement(children: .combine)
        case .accessoryInline:
            Text(s.isOver ? "\(Int(-s.remaining)) kcal over" : "\(Int(s.remaining)) kcal left").monospacedDigit()
        default:
            // systemSmall; also StandBy (large digits, the system dims it red at night).
            VStack(spacing: 6) {
                ZStack {
                    WidgetOrb(s: s, lineWidth: showsBackground ? 8 : 10)
                    RemainingText(s: s, size: showsBackground ? 26 : 34)
                }
                if s.earned >= 1 {
                    Label("\(Int(s.earned)) earned", systemImage: "flame.fill")
                        .font(.system(size: 11, weight: .medium)).monospacedDigit()
                        .foregroundStyle(WidgetPalette.activity)
                        .labelStyle(.titleAndIcon)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(remainingLabel(s) + (s.earned >= 1 ? ", including \(Int(s.earned)) earned" : ""))
        }
    }
}

// MARK: - Medium (Today + log)

struct TodayLogWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LifeOSShared.Kind.todayLog, provider: TodayProvider()) { entry in
            TodayLogWidgetView(entry: entry)
        }
        .configurationDisplayName("Today and log")
        .description("Calories, protein and water, with your two likeliest meals to log in one tap.")
        .supportedFamilies([.systemMedium])
    }
}

struct TodayLogWidgetView: View {
    let entry: TodayEntry

    var body: some View {
        let s = entry.snapshot
        HStack(spacing: 14) {
            VStack(spacing: 6) {
                ZStack {
                    WidgetOrb(s: s, lineWidth: 8)
                    RemainingText(s: s, size: 24)
                }
                .frame(width: 92, height: 92)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(remainingLabel(s))
                MacroBar(label: "Protein", value: "\(Int(s.proteinG)) g", progress: s.proteinTargetG > 0 ? s.proteinG / s.proteinTargetG : 0, color: WidgetPalette.protein)
                    .frame(width: 92)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Log").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                if s.presets.isEmpty {
                    Text("Your usual meals appear here once you've logged a few.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(s.presets.prefix(2)) { p in presetButton(p, s) }
                }
                Button(intent: AddWaterWidgetIntent()) {
                    Label("Water \(s.water)/\(s.waterTarget)", systemImage: "drop.fill")
                        .font(.system(size: 13, weight: .medium)).monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .tint(WidgetPalette.water)
                .accessibilityLabel("Add a glass of water. \(s.water) of \(s.waterTarget) so far.")
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .widgetURL(LifeOSShared.url("today"))
        .containerBackground(for: .widget) { Color.clear.background(.background) }
    }

    private func presetButton(_ p: WidgetSnapshot.Preset, _ s: WidgetSnapshot) -> some View {
        let done = s.justLogged(p.id, now: entry.date)
        return Button(intent: LogPresetWidgetIntent(presetID: p.id)) {
            HStack(spacing: 6) {
                Image(systemName: done ? "checkmark.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(done ? WidgetPalette.onTrack : WidgetPalette.accent)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(done ? "Logged" : "\(Int(p.kcal)) kcal").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(done ? "\(p.name) logged" : "Log \(p.name), \(Int(p.kcal)) calories")
    }
}

// MARK: - Large (Day timeline)

struct TimelineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: LifeOSShared.Kind.timeline, provider: TodayProvider()) { entry in
            TimelineWidgetView(entry: entry)
        }
        .configurationDisplayName("Day timeline")
        .description("Today's meals and workouts, and what's left.")
        .supportedFamilies([.systemLarge])
    }
}

struct TimelineWidgetView: View {
    let entry: TodayEntry

    var body: some View {
        let s = entry.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack { WidgetOrb(s: s, lineWidth: 7) }.frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.isOver ? "\(Int(-s.remaining)) kcal over" : "\(Int(s.remaining)) kcal left")
                        .font(.system(size: 22, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("\(Int(s.eaten)) eaten of \(Int(s.budget))" + (s.earned >= 1 ? " · \(Int(s.earned)) earned" : ""))
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
            Divider()
            if s.items.isEmpty {
                Spacer()
                Text("Nothing logged yet today.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                Spacer()
            } else {
                ForEach(s.items.prefix(6)) { item in
                    Link(destination: LifeOSShared.url("today")) { row(item) }
                }
                Spacer(minLength: 0)
            }
        }
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
        .containerBackground(for: .widget) { Color.clear.background(.background) }
    }

    private func row(_ i: WidgetSnapshot.Item) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon(i.kind)).foregroundStyle(color(i.kind)).frame(width: 20).widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(i.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(i.detail).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if let k = i.kcal { Text(k > 0 ? "\(k)" : "+\(-k)").font(.system(size: 13, weight: .medium)).monospacedDigit() }
            if let t = i.time { Text(t, style: .time).font(.caption2).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }

    private func icon(_ k: WidgetSnapshot.Item.Kind) -> String {
        switch k { case .meal: return "fork.knife"; case .workout: return "figure.strengthtraining.traditional"; case .water: return "drop.fill"; case .weight: return "scalemass.fill" }
    }

    private func color(_ k: WidgetSnapshot.Item.Kind) -> Color {
        switch k { case .meal: return WidgetPalette.energy; case .workout: return WidgetPalette.activity; case .water: return WidgetPalette.water; case .weight: return .secondary }
    }
}
