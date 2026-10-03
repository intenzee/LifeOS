import Combine
import Foundation
import UserNotifications

/// Phase 4 state that lives on this iPhone: memories, automation rules and the
/// notification plan. Memories and rules are JSON in Application Support
/// (never sent anywhere); the assistant only reads them to answer.
@MainActor
final class IntelligenceStore: ObservableObject {
    static let shared = IntelligenceStore()

    // MARK: Memory

    @Published private(set) var said: [MemoryItem] = []
    @Published private(set) var inferred: [MemoryItem] = []
    @Published private(set) var forgottenInferred: Set<String> = []
    @Published private(set) var pinned: Set<String> = []
    @Published private(set) var usage: [String: Int] = [:]
    @Published var learnFromActivity: Bool {
        didSet { defaults.set(learnFromActivity, forKey: Keys.learn) }
    }

    // MARK: Automations

    @Published private(set) var rules: [AutomationRule] = []
    @Published var quietHours: QuietHours { didSet { saveSettings(); replanSoon() } }
    @Published var maxPerDay: Int { didSet { saveSettings(); replanSoon() } }
    @Published private(set) var notificationsAuthorized: Bool? = nil
    /// An event rule fired while the app is open (e.g. "After a workout").
    @Published var eventBanner: EventBanner? = nil

    struct EventBanner: Equatable {
        let id = UUID()
        var ruleID: String
        var text: String
    }
    /// Where a tapped notification wants to go.
    @Published var pendingRoute: Route? = nil

    enum Route: Equatable {
        case weeklyReview, recap, automation(String), logPreset(String), today
        // Phase 5: Siri / Shortcuts / Control Center
        case training, capture
    }

    private let defaults = UserDefaults.standard
    private let folder: URL
    private var lastSnapshot: IntelligenceSnapshot?
    private var lastPlan: [PlannedNotification] = []
    private weak var experience: ExperienceStore?
    private var replanTask: Task<Void, Never>?

    private enum Keys {
        static let learn = "lx.memory.learnFromActivity"
        static let quietStart = "lx.auto.quietStart"
        static let quietEnd = "lx.auto.quietEnd"
        static let maxPerDay = "lx.auto.maxPerDay"
    }

    private init() {
        folder = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory)
            .appendingPathComponent("LifeOS/Experience", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        learnFromActivity = defaults.object(forKey: Keys.learn) as? Bool ?? true
        quietHours = QuietHours(startHour: defaults.object(forKey: Keys.quietStart) as? Int ?? 22,
                                endHour: defaults.object(forKey: Keys.quietEnd) as? Int ?? 7)
        maxPerDay = defaults.object(forKey: Keys.maxPerDay) as? Int ?? 4
        load()
    }

    // MARK: - Persistence

    private struct MemoryFile: Codable {
        var said: [MemoryItem]
        var forgottenInferred: [String]
        var pinned: [String]
        var usage: [String: Int]
    }

    private var memoryURL: URL { folder.appendingPathComponent("memories.json") }
    private var rulesURL: URL { folder.appendingPathComponent("automations.json") }

    private func load() {
        if let data = try? Data(contentsOf: memoryURL), let file = try? JSONDecoder().decode(MemoryFile.self, from: data) {
            said = file.said
            forgottenInferred = Set(file.forgottenInferred)
            pinned = Set(file.pinned)
            usage = file.usage
        }
        if let data = try? Data(contentsOf: rulesURL), let list = try? JSONDecoder().decode([AutomationRule].self, from: data) {
            rules = list
        }
    }

    private func saveMemories() {
        let file = MemoryFile(said: said, forgottenInferred: Array(forgottenInferred), pinned: Array(pinned), usage: usage)
        if let data = try? JSONEncoder().encode(file) { try? data.write(to: memoryURL, options: [.atomic, .completeFileProtection]) }
    }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) { try? data.write(to: rulesURL, options: [.atomic, .completeFileProtection]) }
    }

    private func saveSettings() {
        defaults.set(quietHours.startHour, forKey: Keys.quietStart)
        defaults.set(quietHours.endHour, forKey: Keys.quietEnd)
        defaults.set(maxPerDay, forKey: Keys.maxPerDay)
    }

    // MARK: - Memories

    /// Photo corrections from the existing learning engine, shown as one category.
    var photoCorrections: [MemoryItem] {
        MealLearningEngine.shared.allCorrections.map { c in
            MemoryItem(id: "correction.\(c.id.uuidString)", text: "\(c.correctedName), \(Int(c.calories)) kcal (was \(c.originalName))",
                       category: .photoCorrections, source: .correction, createdAt: c.updatedAt)
        }
    }

    /// Everything the assistant may use, pinned first.
    var memories: [MemoryItem] {
        let learned = learnFromActivity ? inferred.filter { !forgottenInferred.contains($0.id) } : []
        return (said + learned + photoCorrections).map { m in
            var m = m
            m.isPinned = pinned.contains(m.id)
            m.usedCount = usage[m.id] ?? 0
            return m
        }
        .sorted { ($0.isPinned ? 0 : 1, $1.createdAt) < ($1.isPinned ? 0 : 1, $0.createdAt) }
    }

    func remember(_ item: MemoryItem) {
        said.removeAll { $0.text.caseInsensitiveCompare(item.text) == .orderedSame }
        said.insert(item, at: 0)
        saveMemories()
    }

    func forget(_ ids: [String]) {
        for id in ids {
            if id.hasPrefix("correction."), let uuid = UUID(uuidString: String(id.dropFirst("correction.".count))) {
                MealLearningEngine.shared.delete(id: uuid)
            } else if said.contains(where: { $0.id == id }) {
                said.removeAll { $0.id == id }
            } else {
                forgottenInferred.insert(id)
            }
            pinned.remove(id)
            usage[id] = nil
        }
        saveMemories()
        objectWillChange.send()
    }

    func edit(_ id: String, text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if let i = said.firstIndex(where: { $0.id == id }) {
            said[i].text = clean
        } else if let m = memories.first(where: { $0.id == id }) {
            // Editing an inferred memory turns it into something the user said.
            forgottenInferred.insert(id)
            said.insert(MemoryItem(id: "said.\(UUID().uuidString)", text: clean, category: m.category, source: .youSaid, createdAt: Date()), at: 0)
        }
        saveMemories()
    }

    func togglePin(_ id: String) {
        if pinned.contains(id) { pinned.remove(id) } else { pinned.insert(id) }
        saveMemories()
    }

    func markUsed(_ items: [MemoryItem]) {
        guard !items.isEmpty else { return }
        for m in items { usage[m.id, default: 0] += 1 }
        saveMemories()
    }

    /// What "Forget everything" will remove, for the confirmation step.
    var forgetEverythingSummary: String {
        let s = said.count, i = inferred.filter { !forgottenInferred.contains($0.id) }.count, c = photoCorrections.count
        return "\(s) thing\(s == 1 ? "" : "s") you told me, \(i) learned from your logs, and \(c) photo correction\(c == 1 ? "" : "s"). Your food, workout and weight logs are not touched."
    }

    func forgetEverything() {
        said = []
        forgottenInferred.formUnion(inferred.map(\.id))
        pinned = []
        usage = [:]
        MealLearningEngine.shared.reset()
        saveMemories()
    }

    // MARK: - Refresh (after every change in the app)

    func attach(_ store: ExperienceStore) { experience = store }

    /// The snapshot from the last refresh (cheap to read in view bodies).
    var latest: IntelligenceSnapshot? { lastSnapshot }

    func snapshot() -> IntelligenceSnapshot? {
        experience.map { $0.intelligenceSnapshot(memories: memories) }
    }

    /// Re-infers memories, fires in-app event rules, records runs and re-plans notifications.
    func refresh() {
        guard let store = experience else { return }
        let base = store.intelligenceSnapshot(memories: said)
        inferred = MemoryInference.infer(from: base)
        var snap = base
        snap.memories = memories
        detectEvents(old: lastSnapshot?.today, new: snap.today, proteinTarget: snap.proteinTarget, store: store)
        lastSnapshot = snap
        replan(snap)
    }

    private func detectEvents(old: DayFacts?, new: DayFacts?, proteinTarget: Double, store: ExperienceStore) {
        guard let old, let new, Calendar.current.isDate(old.date, inSameDayAs: new.date) else { return }
        var fired: [AutomationRule.Trigger] = []
        if new.workoutKcal > old.workoutKcal + 1 { fired.append(.workoutLogged) }
        if new.meals.count > old.meals.count { fired.append(.mealLogged) }
        if new.weightKg != nil && new.weightKg != old.weightKg { fired.append(.weightLogged) }
        for trigger in fired {
            for i in rules.indices where rules[i].isOn && rules[i].trigger == trigger
                && AutomationPlanner.conditionHolds(rules[i].condition, day: new, proteinTarget: proteinTarget) {
                let text: String
                switch rules[i].action {
                case .budgetEffect:
                    let b = store.budget
                    text = "Workout logged · +\(Int(b.earned)) kcal earned today. Budget now \(Fmt.kcal(b.budget)) kcal."
                default:
                    text = body(for: rules[i], today: new, proteinTarget: proteinTarget, isToday: true)
                }
                rules[i].runs.append(Date())
                eventBanner = EventBanner(ruleID: rules[i].id, text: text)
            }
        }
        saveRules()
    }

    // MARK: - Rules

    func isOn(templateID: String) -> Bool { rules.contains { $0.templateID == templateID && $0.isOn } }

    func upsert(_ rule: AutomationRule) {
        if let i = rules.firstIndex(where: { $0.id == rule.id }) { rules[i] = rule } else { rules.append(rule) }
        saveRules()
        Task { await requestAuthorizationIfNeeded() }
        replanSoon()
    }

    func setOn(_ id: String, _ on: Bool) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[i].isOn = on
        saveRules()
        if on { Task { await requestAuthorizationIfNeeded() } }
        replanSoon()
    }

    func delete(_ id: String) {
        rules.removeAll { $0.id == id }
        saveRules()
        replanSoon()
    }

    func backtest(_ rule: AutomationRule) -> Int {
        guard let snap = lastSnapshot ?? snapshot() else { return 0 }
        let lastWeek = snap.lastDays(8).filter { !Calendar.current.isDate($0.date, inSameDayAs: snap.now) }
        return AutomationPlanner.backtest(rule, days: lastWeek, proteinTarget: snap.proteinTarget, quiet: quietHours)
    }

    /// Templates that fit the user's habits and aren't on yet.
    var suggestedTemplates: [AutomationRule] {
        let ids = Set(memories.map(\.id))
        var out: [AutomationRule] = []
        func add(_ id: String) {
            if let r = AutomationTemplates.all.first(where: { $0.rule.id == id })?.rule, !rules.contains(where: { $0.templateID == id }) { out.append(r) }
        }
        if ids.contains("usual.breakfast") { add("t.usualBreakfast") }
        if let today = lastSnapshot?.today, today.water < today.waterTarget / 2 { add("t.water") }
        if ids.contains("routine.gym") { add("t.afterWorkout") }
        add("t.recap")
        return Array(out.prefix(3))
    }

    // MARK: - Notifications

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .notDetermined:
            notificationsAuthorized = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        case .denied:
            notificationsAuthorized = false
        default:
            notificationsAuthorized = true
        }
    }

    private func replanSoon() {
        replanTask?.cancel()
        replanTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, let snap = self.lastSnapshot ?? self.snapshot() else { return }
            self.replan(snap)
        }
    }

    private func replan(_ snap: IntelligenceSnapshot) {
        // Planned fires that have passed since last time count as runs.
        let now = Date()
        var changed = false
        for p in lastPlan where p.fireDate <= now {
            if let i = rules.firstIndex(where: { $0.id == p.ruleID }), !rules[i].runs.contains(p.fireDate) {
                rules[i].runs.append(p.fireDate)
                rules[i].runs = rules[i].runs.filter { now.timeIntervalSince($0) < 30 * 86_400 }
                changed = true
            }
        }
        if changed { saveRules() }

        let plan = AutomationPlanner.plan(rules, now: now, today: snap.today, proteinTarget: snap.proteinTarget,
                                          quiet: quietHours, maxPerDay: maxPerDay)
        lastPlan = plan
        let requests = plan.compactMap { p -> UNNotificationRequest? in
            guard let rule = rules.first(where: { $0.id == p.ruleID }) else { return nil }
            let isToday = Calendar.current.isDateInToday(p.fireDate)
            let content = UNMutableNotificationContent()
            content.title = rule.name
            content.body = body(for: rule, today: snap.today, proteinTarget: snap.proteinTarget, isToday: isToday)
            content.sound = .default
            content.threadIdentifier = "lx.automations"
            content.categoryIdentifier = ExperienceNotifications.category(for: rule.action)
            content.userInfo = ["ruleID": rule.id, "presetID": presetID(for: rule) ?? ""]
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: p.fireDate)
            return UNNotificationRequest(identifier: p.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
        }
        let center = UNUserNotificationCenter.current()
        Task {
            let old = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("lx.auto.") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for r in requests { try? await center.add(r) }
        }
    }

    private func presetID(for rule: AutomationRule) -> String? {
        guard case .suggestUsual(let slot) = rule.action else { return nil }
        return experience?.presets(for: slot, limit: 1).first?.id
    }

    func body(for rule: AutomationRule, today: DayFacts?, proteinTarget: Double, isToday: Bool) -> String {
        switch rule.action {
        case .notify(let text):
            if isToday, case .waterBelow = rule.condition, let d = today { return "\(text). \(d.water) of \(d.waterTarget) glasses so far." }
            return text
        case .suggestUsual(let slot):
            if let p = experience?.presets(for: slot, limit: 1).first {
                return "\(slot.title) isn't logged yet. Usual: \(p.nutrient.name), \(Int(p.nutrient.kcal)) kcal."
            }
            return "\(slot.title) isn't logged yet. Tap to log it."
        case .morningBrief:
            if let s = lastSnapshot, let line = Briefs.morning(s) { return line }
            return "Today's budget is ready. Tap to see it."
        case .eveningRecap:
            return "Tap to see how today went."
        case .weeklyReview:
            return "Your weekly review is ready: the week in a few pages."
        case .budgetEffect:
            return "See what your workout added to today's budget."
        case .suggestHighProtein:
            if isToday, let d = today, proteinTarget > 0 {
                return "Protein is \(Fmt.grams(d.protein)) of \(Fmt.grams(proteinTarget)). A high-protein dinner closes the gap."
            }
            return "Check your protein before dinner."
        }
    }
}
