import SwiftUI

/// 4.4 Automations home: Active, Suggested by LifeOS, Gallery, and limits.
struct AutomationsScreen: View {
    @ObservedObject var intelligence: IntelligenceStore = .shared
    var focusRuleID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lxTheme) private var theme
    @State private var building: AutomationRule?

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: LX.Space.s600) {
                        if intelligence.notificationsAuthorized == false {
                            LXInlineBanner(kind: .attention, message: "Notifications are off for LifeOS, so scheduled automations can't reach you.",
                                           actionTitle: "Open Settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }
                        }
                        active
                        suggested
                        gallery
                        limits
                    }
                    .padding(LX.Space.s400)
                }
                .onAppear {
                    if let id = focusRuleID { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { withAnimation { proxy.scrollTo(id, anchor: .top) } } }
                }
            }
            .background { Rectangle().fill(.lx(.background)).ignoresSafeArea() }
            .navigationTitle("Automations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button { building = AutomationRule(id: "u.\(UUID().uuidString)", name: "My automation",
                                                       trigger: .time(hour: 9, minute: 0, weekdays: []), action: .notify("Check in with LifeOS")) } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New automation")
                }
            }
            .sheet(item: $building) { rule in AutomationBuilder(draft: rule) }
            .task { await intelligence.requestAuthorizationIfNeeded() }
        }
    }

    @ViewBuilder private var active: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            LXSectionHeader(title: "Active")
            if intelligence.rules.isEmpty {
                Text("Nothing running yet. Turn on a suggestion below, or ask the assistant: “remind me to weigh in every Monday at 7”.")
                    .lxFont(.subhead).foregroundStyle(.lx(.textSecondary)).lxCard(padding: LX.Space.s400)
            }
            ForEach(intelligence.rules) { rule in
                VStack(alignment: .leading, spacing: LX.Space.s200) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rule.name).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                            Text(AutomationText.sentence(rule)).lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                        }
                        Spacer()
                        Toggle("", isOn: Binding(get: { rule.isOn }, set: { intelligence.setOn(rule.id, $0) }))
                            .labelsHidden().tint(theme.color(.accentPrimary))
                            .accessibilityLabel(rule.name)
                    }
                    HStack {
                        let n = rule.runsThisWeek(now: Date())
                        Text("Ran \(n) time\(n == 1 ? "" : "s") this week").lxFont(.caption, numeric: true).foregroundStyle(.lx(.textTertiary))
                        Spacer()
                        Button("Edit") { building = rule }.buttonStyle(.plain).lxFont(.footnote, weight: .medium).foregroundStyle(.lx(.accentPrimary))
                        Button("Delete", role: .destructive) { intelligence.delete(rule.id) }.buttonStyle(.plain)
                            .lxFont(.footnote, weight: .medium).foregroundStyle(.lx(.statusCritical))
                    }
                }
                .lxCard(padding: LX.Space.s400)
                .overlay {
                    if rule.id == focusRuleID {
                        RoundedRectangle(cornerRadius: LX.Radius.card, style: .continuous).strokeBorder(.lx(.accentPrimary), lineWidth: 1.5)
                    }
                }
                .id(rule.id)
            }
        }
    }

    @ViewBuilder private var suggested: some View {
        let list = intelligence.suggestedTemplates
        if !list.isEmpty {
            VStack(alignment: .leading, spacing: LX.Space.s300) {
                LXSectionHeader(title: "Suggested by LifeOS")
                ForEach(list) { rule in templateCard(rule, why: why(rule)) }
            }
        }
    }

    private func why(_ rule: AutomationRule) -> String? {
        switch rule.templateID {
        case "t.usualBreakfast": return intelligence.memories.first { $0.id == "usual.breakfast" }?.text
        case "t.afterWorkout": return intelligence.memories.first { $0.id == "routine.gym" }?.text
        case "t.water": return "Water is behind today."
        default: return nil
        }
    }

    private var gallery: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            LXSectionHeader(title: "Gallery")
            ForEach(AutomationTemplates.Category.allCases, id: \.self) { cat in
                let items = AutomationTemplates.all.filter { $0.category == cat }.map(\.rule)
                if !items.isEmpty {
                    Text(cat.rawValue).lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.textSecondary)).padding(.top, LX.Space.s200)
                    ForEach(items) { templateCard($0, why: nil) }
                }
            }
        }
    }

    private func templateCard(_ rule: AutomationRule, why: String?) -> some View {
        let on = intelligence.isOn(templateID: rule.templateID ?? "")
        return HStack(alignment: .top, spacing: LX.Space.s300) {
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.name).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                Text(AutomationText.sentence(rule)).lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                if let why { Text("Because: \(why)").lxFont(.caption).foregroundStyle(.lx(.textTertiary)) }
            }
            Spacer()
            Button(on ? "On" : "Turn on") { intelligence.upsert(rule) }
                .buttonStyle(.lx(on ? .plain : .secondary))
                .disabled(on || intelligence.rules.contains { $0.id == rule.id })
        }
        .lxCard(padding: LX.Space.s400)
    }

    private var limits: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            LXSectionHeader(title: "Limits")
            VStack(spacing: LX.Space.s300) {
                Stepper(value: $intelligence.maxPerDay, in: 1...8) {
                    LXRowLabel(title: "At most \(intelligence.maxPerDay) a day", systemImage: "bell.badge")
                }
                Stepper(value: Binding(get: { intelligence.quietHours.startHour }, set: { intelligence.quietHours.startHour = $0 }), in: 18...23) {
                    LXRowLabel(title: "Quiet from \(AutomationText.clock(intelligence.quietHours.startHour, 0))", systemImage: "moon")
                }
                Stepper(value: Binding(get: { intelligence.quietHours.endHour }, set: { intelligence.quietHours.endHour = $0 }), in: 5...10) {
                    LXRowLabel(title: "Until \(AutomationText.clock(intelligence.quietHours.endHour, 0))", systemImage: "sunrise")
                }
            }
            .lxCard(padding: LX.Space.s400)
            Text("Scheduled automations are planned a week ahead and re-checked every time you log, so a reminder you no longer need is withdrawn. “When I log…” automations run while LifeOS is open.")
                .lxFont(.caption).foregroundStyle(.lx(.textTertiary))
        }
    }
}

/// Builder: When [token] if [token] then [token], with a preview of last week.
struct AutomationBuilder: View {
    @State var draft: AutomationRule
    @ObservedObject var intelligence: IntelligenceStore = .shared
    @Environment(\.dismiss) private var dismiss
    @State private var notifyText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(AutomationText.sentence(draft)).lxFont(.headline)
                    Text(draft.trigger.isScheduled
                         ? "Here's how this would have run last week: \(intelligence.backtest(draft)) time\(intelligence.backtest(draft) == 1 ? "" : "s")."
                         : "Runs while LifeOS is open, right after you log.")
                        .lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
                }
                Section("Name") { TextField("Name", text: $draft.name) }
                Section("When") {
                    Picker("Trigger", selection: triggerKind) {
                        Text("At a time").tag(0); Text("Every few hours").tag(1)
                        Text("When I log a meal").tag(2); Text("When I log a workout").tag(3); Text("When I log my weight").tag(4)
                    }
                    switch draft.trigger {
                    case let .time(h, m, days):
                        DatePicker("Time", selection: Binding(get: { Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date())! },
                                                              set: { let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
                                                                  draft.trigger = .time(hour: c.hour ?? h, minute: c.minute ?? m, weekdays: days) }),
                                   displayedComponents: .hourAndMinute)
                        Picker("Days", selection: Binding(get: { daysKey(days) }, set: { draft.trigger = .time(hour: h, minute: m, weekdays: daysFor($0)) })) {
                            Text("Every day").tag("all"); Text("Weekdays").tag("weekdays"); Text("Weekends").tag("weekends")
                            ForEach(1...7, id: \.self) { d in Text("Every \(Calendar.current.weekdaySymbols[d - 1])").tag("d\(d)") }
                        }
                    case let .everyHours(n, from, to):
                        Stepper("Every \(n) hour\(n == 1 ? "" : "s")", value: Binding(get: { n }, set: { draft.trigger = .everyHours($0, fromHour: from, toHour: to) }), in: 1...6)
                        Stepper("From \(AutomationText.clock(from, 0))", value: Binding(get: { from }, set: { draft.trigger = .everyHours(n, fromHour: $0, toHour: max($0, to)) }), in: 6...20)
                        Stepper("Until \(AutomationText.clock(to, 0))", value: Binding(get: { to }, set: { draft.trigger = .everyHours(n, fromHour: min(from, $0), toHour: $0) }), in: 8...22)
                    default:
                        EmptyView()
                    }
                }
                Section("If (optional)") {
                    Picker("Condition", selection: conditionKind) {
                        Text("Always").tag(0); Text("Water under…").tag(1); Text("Protein under 80% of target").tag(2)
                        Text("Over budget").tag(3); Text("Breakfast not logged").tag(4); Text("Lunch not logged").tag(5)
                        Text("Dinner not logged").tag(6); Text("Not weighed in").tag(7)
                    }
                    if case .waterBelow(let n) = draft.condition {
                        Stepper("Under \(n) glasses", value: Binding(get: { n }, set: { draft.condition = .waterBelow($0) }), in: 1...12)
                    }
                }
                Section("Then") {
                    Picker("Action", selection: actionKind) {
                        Text("Remind me").tag(0); Text("Suggest my usual meal").tag(1); Text("Show my morning brief").tag(2)
                        Text("Summarise my day").tag(3); Text("Prepare my weekly review").tag(4); Text("Show what a workout added").tag(5)
                        Text("Suggest a high-protein dinner").tag(6)
                    }
                    if case .notify = draft.action {
                        TextField("Reminder text", text: $notifyText).onChange(of: notifyText) { _, v in draft.action = .notify(v) }
                    }
                }
            }
            .navigationTitle("Automation").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { draft.isOn = true; intelligence.upsert(draft); dismiss() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear { if case .notify(let t) = draft.action { notifyText = t } }
        }
    }

    // MARK: Token bindings

    private var triggerKind: Binding<Int> {
        Binding(get: {
            switch draft.trigger {
            case .time: return 0
            case .everyHours: return 1
            case .mealLogged: return 2
            case .workoutLogged: return 3
            case .weightLogged: return 4
            }
        }, set: { k in
            switch k {
            case 0: draft.trigger = .time(hour: 9, minute: 0, weekdays: [])
            case 1: draft.trigger = .everyHours(2, fromHour: 9, toHour: 21)
            case 2: draft.trigger = .mealLogged
            case 3: draft.trigger = .workoutLogged
            default: draft.trigger = .weightLogged
            }
        })
    }

    private var conditionKind: Binding<Int> {
        Binding(get: {
            switch draft.condition {
            case .none: return 0
            case .waterBelow: return 1
            case .proteinBelowShare: return 2
            case .overBudget: return 3
            case .slotNotLogged(.breakfast): return 4
            case .slotNotLogged(.lunch): return 5
            case .slotNotLogged: return 6
            case .notWeighedToday: return 7
            }
        }, set: { k in
            draft.condition = [.none, .waterBelow(4), .proteinBelowShare(0.8), .overBudget, .slotNotLogged(.breakfast),
                               .slotNotLogged(.lunch), .slotNotLogged(.dinner), .notWeighedToday][k]
        })
    }

    private var actionKind: Binding<Int> {
        Binding(get: {
            switch draft.action {
            case .notify: return 0
            case .suggestUsual: return 1
            case .morningBrief: return 2
            case .eveningRecap: return 3
            case .weeklyReview: return 4
            case .budgetEffect: return 5
            case .suggestHighProtein: return 6
            }
        }, set: { k in
            let slot: ExperienceMealSlot = {
                if case .time(let h, _, _) = draft.trigger { return h < 11 ? .breakfast : h < 16 ? .lunch : .dinner }
                return .breakfast
            }()
            draft.action = [.notify(notifyText.isEmpty ? draft.name : notifyText), .suggestUsual(slot), .morningBrief, .eveningRecap,
                            .weeklyReview, .budgetEffect, .suggestHighProtein][k]
        })
    }

    private func daysKey(_ days: [Int]) -> String {
        let s = Set(days)
        if s.isEmpty || s.count == 7 { return "all" }
        if s == [2, 3, 4, 5, 6] { return "weekdays" }
        if s == [1, 7] { return "weekends" }
        return "d\(days.first ?? 2)"
    }

    private func daysFor(_ key: String) -> [Int] {
        switch key {
        case "all": return []
        case "weekdays": return [2, 3, 4, 5, 6]
        case "weekends": return [1, 7]
        default: return [Int(key.dropFirst()) ?? 2]
        }
    }
}
