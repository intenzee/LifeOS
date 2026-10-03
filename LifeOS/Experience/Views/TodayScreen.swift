import SwiftUI

/// 3.1 Today: "In two seconds, tell me how my day is going and what to do next."
struct TodayScreen: View {
    @ObservedObject var store: ExperienceStore
    var loggedTick: Int
    var onCapture: () -> Void
    var onBudget: () -> Void
    var onNextUp: (ExperienceNextUp.Action) -> Void
    // Phase 4
    var onAsk: () -> Void = {}
    var brief: String? = nil
    var recap: String? = nil
    var onWeeklyReview: (() -> Void)? = nil
    // Phase 5
    var refreshBanner: String? = nil
    var onRefreshHelp: () -> Void = {}

    @State private var showCalendar = false
    @State private var showWeight = false
    @State private var editing: FoodItem?
    @State private var orbWobble = 0.0
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LX.Space.s500) {
                LXDateScroller(date: dayBinding, onCalendar: { showCalendar = true })
                    .overlay(alignment: .topTrailing) {
                        // "Ask" glass chip (Phase 3 §3.1 header, Phase 4 §4.1 entry point).
                        Button(action: onAsk) { LXChip(title: "Ask", systemImage: "sparkles", kind: .suggestion) }
                            .buttonStyle(.plain)
                            .padding(.trailing, LX.Space.minTouchTarget + LX.Space.s200)
                            .accessibilityLabel("Ask LifeOS about today")
                    }
                if store.isToday, let refreshBanner {
                    // Phase 5 §9.1: on the last day the refresh note moves to Today.
                    LXInlineBanner(kind: .attention, message: refreshBanner, actionTitle: "How to refresh", action: onRefreshHelp)
                }
                hero
                if let next = store.nextUp {
                    nextUpCard(next)
                } else if store.isToday, let brief {
                    briefCard(brief)
                }
                if store.isToday, let recap { recapCard(recap) }
                if store.isToday, let onWeeklyReview { weeklyCard(onWeeklyReview) }
                metrics
                timeline
                plan
            }
            .padding(.horizontal, LX.Space.s400)
            .padding(.top, LX.Space.s200)
            .padding(.bottom, LX.Space.s600)
            .opacity(store.isToday ? 1 : 0.92)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showCalendar) { calendarSheet }
        .sheet(isPresented: $showWeight) { WeightQuickSheet(store: store).lxSheetStyle(detents: [.medium]) }
        .sheet(item: $editing) { item in
            FoodEditSheet(item: item, onSave: { store.update($0, scale: $1) }, onDelete: { store.remove([item.id]) })
        }
        .onChange(of: loggedTick) { _, _ in pulseOrb() }
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { store.day }, set: { store.select(day: $0) })
    }

    // MARK: Hero (orb, remaining, budget chip)

    private var hero: some View {
        let b = store.budget
        let headline = ExperienceCopy.remainingHeadline(b)
        var orb = store.orbState
        orb.wobble = orbWobble
        return VStack(spacing: LX.Space.s300) {
            LifeOrb(state: orb)
                .padding(.vertical, LX.Space.s300)
            VStack(spacing: 2) {
                Text(headline.value)
                    .lxFont(.displayHero, numeric: true)
                    .foregroundStyle(b.isOver ? .lx(.statusOver) : .lx(.textPrimary))
                    .lineLimit(1).minimumScaleFactor(0.6)
                    .lxNumberRoll(b.remaining)
                Text(headline.label).lxFont(.headline).foregroundStyle(.lx(.textSecondary))
                if let over = ExperienceCopy.overNote(b) {
                    Text(over).lxFont(.footnote).foregroundStyle(.lx(.textSecondary)).padding(.top, 2)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(b.isOver
                ? "Over budget by \(Int(-b.remaining)) calories. Budget \(Int(b.budget).formatted()), including \(Int(b.earned)) earned from activity."
                : "Remaining calories, \(Int(b.remaining).formatted()). Budget \(Int(b.budget).formatted()), including \(Int(b.earned)) earned from activity.")
            Button(action: onBudget) {
                LXBudgetChip(base: Int(b.baseLimit.rounded()), earned: Int(b.earned))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
    }

    private func pulseOrb() {
        orbWobble = 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            orbWobble = 0
        }
    }

    // MARK: Next up

    private func briefCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: LX.Space.s300) {
            Image(systemName: "sun.horizon").foregroundStyle(.lx(.accentPrimary))
            Text(text).lxFont(.callout).foregroundStyle(.lx(.textPrimary)).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .lxCard(padding: LX.Space.s400)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Morning brief. \(text)")
    }

    private func recapCard(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: LX.Space.s200) {
            Text("Evening recap").lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.textSecondary)).textCase(.uppercase)
            Text(text).lxFont(.callout, numeric: true).foregroundStyle(.lx(.textPrimary)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lxCard(padding: LX.Space.s400)
        .accessibilityElement(children: .combine)
    }

    private func weeklyCard(_ open: @escaping () -> Void) -> some View {
        Button(action: open) {
            HStack(spacing: LX.Space.s300) {
                Image(systemName: "book.pages").font(.title3).foregroundStyle(.lx(.accentPrimary))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Your weekly review").lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                    Text("The week in a few pages").lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.lx(.textTertiary))
            }
            .lxCard(padding: LX.Space.s400)
        }
        .buttonStyle(.plain)
    }

    private func nextUpCard(_ next: ExperienceNextUp) -> some View {
        LXAdaptiveStack(spacing: LX.Space.s300) {
            HStack(alignment: .top, spacing: LX.Space.s300) {
                Image(systemName: "sparkles").foregroundStyle(.lx(.accentPrimary))
                Text(next.message).lxFont(.callout).foregroundStyle(.lx(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button(next.actionTitle) { onNextUp(next.action) }
                .buttonStyle(.lx(.secondary))
        }
        .lxCard(padding: LX.Space.s400)
        .accessibilityElement(children: .combine)
    }

    // MARK: Metrics

    private var metrics: some View {
        let log = store.log
        let targets = store.macroTargets
        let health = store.health
        let healthConnected = health.activeEnergyToday > 0 || health.stepsToday > 0
        return LazyVGrid(columns: typeSize.lxColumns(2), spacing: LX.Space.s300) {
            LXMetricTile(label: "Protein", value: "\(Int(log.totalProtein().rounded()))", unit: "of \(Int(targets.protein)) g",
                         systemImage: "bolt.heart", dataRole: .dataProtein,
                         progress: targets.protein > 0 ? log.totalProtein() / targets.protein : 0)
            Button { store.addWater(1) } label: {
                LXMetricTile(label: "Water", value: "\(store.waterCount)", unit: "of \(store.waterTarget)",
                             systemImage: "drop.fill", dataRole: .dataWater,
                             progress: store.waterTarget > 0 ? Double(store.waterCount) / Double(store.waterTarget) : 0,
                             caption: store.isToday ? "Tap for +1 glass" : nil)
            }
            .buttonStyle(.plain)
            .disabled(!store.isToday)
            .accessibilityHint(store.isToday ? "Adds one glass" : "")
            if healthConnected {
                LXMetricTile(label: "Activity", value: "\(Int(health.activeEnergyToday.rounded()))", unit: "kcal",
                             systemImage: "flame.fill", dataRole: .dataActivity,
                             caption: "\(Int(health.stepsToday).formatted()) steps · Apple Health")
            } else {
                Button { health.requestFullAuthorization() } label: {
                    LXMetricTile(label: "Activity", value: "–", systemImage: "flame.fill", dataRole: .dataActivity,
                                 caption: "Connect Apple Health")
                }
                .buttonStyle(.plain)
            }
            Button { showWeight = true } label: {
                if health.sleepDurationHours > 0 {
                    LXMetricTile(label: "Sleep", value: String(format: "%.1f", health.sleepDurationHours), unit: "h",
                                 systemImage: "moon.zzz.fill", dataRole: .dataSleep, caption: "Last night")
                } else {
                    LXMetricTile(label: "Weight", value: store.currentWeight > 0 ? ExperienceStore.weightText(store.currentWeight, units: store.profile?.units) : "–",
                                 systemImage: "scalemass.fill", dataRole: .dataWeight, caption: "Tap to log")
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Timeline

    private var timeline: some View {
        VStack(alignment: .leading, spacing: LX.Space.s200) {
            LXSectionHeader(title: store.isToday ? "Today so far" : "That day")
            let rows = store.timeline
            if rows.isEmpty {
                LXEmptyState(systemImage: "fork.knife", message: store.isToday ? "Nothing logged yet. Say what you ate, or snap it." : "Nothing was logged this day.",
                             actionTitle: store.isToday ? "Capture" : nil, action: onCapture)
                    .frame(maxWidth: .infinity)
                    .lxCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(rows) { row in
                        if row.kind == .meal, let item = store.item(id: row.id) {
                            Button { editing = item } label: { timelineRow(row).contentShape(Rectangle()) }
                                .buttonStyle(.plain)
                                .accessibilityHint("Edit")
                                .contextMenu {
                                    Button("Edit", systemImage: "pencil") { editing = item }
                                    Button("Delete", systemImage: "trash", role: .destructive) { store.remove([item.id]) }
                                }
                        } else {
                            timelineRow(row)
                        }
                        if row.id != rows.last?.id { Rectangle().fill(.lx(.separator)).frame(height: 0.5) }
                    }
                }
                .lxCard(padding: LX.Space.s300)
                .animation(.default, value: rows.map(\.id))
            }
        }
    }

    private func timelineRow(_ row: ExperienceTimelineEntry) -> LXListRow {
        var value: String? = nil
        var caption: String? = nil
        if let k = row.kcal {
            value = k < 0 ? "+\(-k)" : "\(k)"
            caption = k < 0 ? "earned" : "kcal"
        }
        let badge: LXSource? = (row.kind == .meal && row.source != .manual) ? row.source.lxSource : nil
        return LXListRow(title: row.title, subtitle: subtitle(row), value: value, valueCaption: caption,
                         systemImage: icon(row.kind), iconRole: role(row.kind), source: badge)
    }

    private func subtitle(_ row: ExperienceTimelineEntry) -> String {
        if let t = row.time { return "\(row.detail) · \(t.formatted(date: .omitted, time: .shortened))" }
        return row.detail
    }

    private func icon(_ kind: ExperienceTimelineEntry.Kind) -> String {
        switch kind {
        case .meal: return "fork.knife"
        case .workout: return "figure.strengthtraining.traditional"
        case .water: return "drop.fill"
        case .weight: return "scalemass.fill"
        }
    }

    private func role(_ kind: ExperienceTimelineEntry.Kind) -> LXColorRole {
        switch kind {
        case .meal: return .dataEnergy
        case .workout: return .dataActivity
        case .water: return .dataWater
        case .weight: return .dataWeight
        }
    }

    // MARK: Plan preview

    private var plan: some View {
        VStack(alignment: .leading, spacing: LX.Space.s200) {
            HStack {
                LXSectionHeader(title: "Plan")
                if store.perfectDayStreak > 0 {
                    LXChip(title: "\(store.perfectDayStreak)-day streak", systemImage: "flame", kind: .status(.statusOnTrack))
                }
            }
            if store.todos.isEmpty {
                Text("No todos for this day.").lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lxCard(padding: LX.Space.s400)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.todos.prefix(3), id: \.id) { todo in
                        Button { store.toggleTodo(todo.id) } label: {
                            HStack(spacing: LX.Space.s300) {
                                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .font(.title3)
                                    .foregroundStyle(todo.isCompleted ? .lx(.statusOnTrack) : .lx(.textTertiary))
                                Text(todo.title).lxFont(.body)
                                    .foregroundStyle(todo.isCompleted ? .lx(.textSecondary) : .lx(.textPrimary))
                                    .strikethrough(todo.isCompleted)
                                Spacer()
                            }
                            .frame(minHeight: LX.Space.minTouchTarget)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(todo.isCompleted ? .isSelected : [])
                    }
                    if store.todos.count > 3 {
                        Text("+\(store.todos.count - 3) more in You → Todos").lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, LX.Space.s200)
                    }
                }
                .lxCard(padding: LX.Space.s400)
            }
        }
    }

    private var calendarSheet: some View {
        NavigationStack {
            DatePicker("Day", selection: dayBinding, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showCalendar = false } } }
        }
        .presentationDetents([.medium])
    }
}

/// Quick weight from Today and Capture (Phase 3 §3.2 "quick weight").
struct WeightQuickSheet: View {
    @ObservedObject var store: ExperienceStore
    @Environment(\.dismiss) private var dismiss
    @State private var kg: Double = 70

    private var imperial: Bool { store.profile?.units == .imperial }

    var body: some View {
        VStack(spacing: LX.Space.s500) {
            LXSheetHeader(title: "Weight", primaryTitle: "Save", onClose: { dismiss() }, onPrimary: {
                store.logWeight(kg: kg)
                dismiss()
            })
            Text(ExperienceStore.weightText(kg, units: store.profile?.units))
                .lxFont(.displayL, numeric: true).foregroundStyle(.lx(.textPrimary))
                .lxNumberRoll(kg)
            HStack(spacing: LX.Space.s300) {
                ForEach([-1.0, -0.1, 0.1, 1.0], id: \.self) { step in
                    Button(step > 0 ? "+\(String(format: "%g", step))" : String(format: "%g", step)) {
                        kg = max(20, ((kg + step * (imperial ? 1 / 2.20462 : 1)) * 10).rounded() / 10)
                    }
                    .buttonStyle(.lx(.secondary))
                }
            }
            Text("Saved on this iPhone. Updates your recommended target if it's on auto.")
                .lxFont(.footnote).foregroundStyle(.lx(.textSecondary)).multilineTextAlignment(.center)
            Spacer()
        }
        .padding(LX.Space.s400)
        .onAppear { if store.currentWeight > 0 { kg = store.currentWeight } }
        .lxHaptic(.selection, trigger: kg)
    }
}
