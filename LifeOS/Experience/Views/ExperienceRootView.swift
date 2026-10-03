import AppIntents
import Combine
import SwiftUI

/// UI/UX Phase 3 shell: five labelled tabs with the raised Capture button
/// (master plan §5), plus the Phase 4 intelligence surfaces (assistant, memory,
/// insights, automations). Shown when `lx.newExperience` is on; the classic UI
/// stays one switch away in You → "New layout".
struct ExperienceRootView: View {
    let dependencies: AppDependencies
    @StateObject private var store: ExperienceStore
    @ObservedObject private var intelligence = IntelligenceStore.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var tab: LXTab = .today
    @State private var showCapture = false
    @State private var captureStartsTyping = false
    @State private var captureSlot: ExperienceMealSlot?
    @State private var showBudget = false
    @State private var legacyRoute: LegacyCaptureRoute = .none
    @State private var toast: LXToastModel?
    @State private var undoIDs: [UUID] = []
    @State private var loggedTick = 0

    // Phase 4
    @State private var assistant: AssistantLaunch?
    @State private var showMemory = false
    @State private var automationsFocus: AutomationsLaunch?
    @State private var showPrivacy = false
    @State private var weeklyReview: ReviewLaunch?
    @State private var ruleDraft: AutomationRule?
    @State private var banner: IntelligenceStore.EventBanner?

    // Phase 5
    @ObservedObject private var backup = BackupService.shared
    @State private var showData = false
    @State private var showRefreshHelp = false
    @ObservedObject private var achievements = AchievementStore.shared
    @State private var showAchievements = false
    @State private var viewingMedal: Medal?

    struct AssistantLaunch: Identifiable { let id = UUID(); var context: String?; var listening: Bool }
    struct AutomationsLaunch: Identifiable { let id = UUID(); var focus: String? }
    struct ReviewLaunch: Identifiable { let id = UUID(); var review: WeeklyReview }

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _store = StateObject(wrappedValue: ExperienceStore(dependencies: dependencies))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            LXScreenBackground(heroGlow: tab == .today).ignoresSafeArea()

            Group {
                switch tab {
                case .today, .capture:
                    TodayScreen(store: store, loggedTick: loggedTick,
                                onCapture: { openCapture() },
                                onBudget: { showBudget = true },
                                onNextUp: handleNextUp,
                                onAsk: { openAssistant(context: "Looking at: Today, \(store.day.formatted(.dateTime.day().month(.abbreviated)))") },
                                brief: morningBrief,
                                recap: eveningRecap,
                                onWeeklyReview: weeklyReviewAvailable ? { openWeeklyReview() } : nil,
                                refreshBanner: backup.refreshStage == .lastDay ? backup.refreshMessage : nil,
                                onRefreshHelp: { showRefreshHelp = true })
                case .nutrition:
                    NutritionScreen(store: store, onCapture: { slot in openCapture(slot: slot) },
                                    onLogPreset: { id in logPreset(id) })
                case .training:
                    TrainingScreen(store: store, onBudget: { showBudget = true })
                case .you:
                    YouScreen(store: store,
                              onMemory: { showMemory = true },
                              onAutomations: { automationsFocus = AutomationsLaunch(focus: nil) },
                              onPrivacy: { showPrivacy = true },
                              onWeeklyReview: currentReview() != nil ? { openWeeklyReview() } : nil,
                              onData: { showData = true },
                              onRefreshHelp: { showRefreshHelp = true },
                              onAchievements: { showAchievements = true })
                }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) } // last row clears the tab bar (audit A4)

            LXTabBar(selection: $tab,
                     onCapture: { openCapture() },
                     onAssistant: { openAssistant(context: nil, listening: true) })
                .padding(.bottom, 4)

            LegacyCaptureHost(route: $legacyRoute, slot: store.currentSlot, apiClient: dependencies.apiClient,
                              onLog: { food, source in logged(store.log([food], slot: ExperienceMealSlot(food.mealType), source: source),
                                                              kcal: food.calories, protein: food.protein) },
                              onSaveCustom: { dependencies.foodDatabase.addCustomFood($0) })
        }
        .overlay(alignment: .top) { eventBanner }
        .overlay {
            if let medal = achievements.celebrating {
                MedalEarningMoment(medal: medal,
                                   onDone: { achievements.didCelebrate() },
                                   onView: { achievements.didCelebrate(); viewingMedal = medal })
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showCapture) {
            CaptureSheet(store: store, startTyping: captureStartsTyping, initialSlot: captureSlot,
                         onLogged: { ids, kcal, protein in showCapture = false; logged(ids, kcal: kcal, protein: protein) },
                         onRoute: { route in
                             showCapture = false
                             // Let the sheet finish dismissing before the full-screen flow appears.
                             afterDismiss { legacyRoute = route }
                         },
                         onAsk: {
                             showCapture = false
                             afterDismiss { openAssistant(context: nil) }
                         })
                .lxSheetStyle()
        }
        .sheet(isPresented: $showBudget) {
            BudgetExplainerSheet(store: store).lxSheetStyle(detents: [.large])
        }
        .sheet(item: $assistant) { launch in
            AssistantSheet(store: store, contextChip: launch.context, startListening: launch.listening,
                           onLogged: { ids, kcal, protein in logged(ids, kcal: kcal, protein: protein) },
                           onEditInCapture: { _ in
                               assistant = nil
                               afterDismiss { openCapture(typing: true) }
                           },
                           onEditRule: { rule in
                               assistant = nil
                               afterDismiss { ruleDraft = rule }
                           })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMemory) { MemoryScreen() }
        .sheet(item: $automationsFocus) { launch in AutomationsScreen(focusRuleID: launch.focus) }
        .sheet(item: $ruleDraft) { rule in AutomationBuilder(draft: rule) }
        .sheet(isPresented: $showPrivacy) {
            AIPrivacyScreen(onOpenMemory: { afterDismiss { showMemory = true } })
        }
        .sheet(isPresented: $showData) { DataBackupScreen() }
        .sheet(isPresented: $showRefreshHelp) { RefreshHelpView() }
        .sheet(isPresented: $showAchievements) { AchievementsScreen() }
        .sheet(item: $viewingMedal) { m in MedalViewer(medal: m, earnedOn: achievements.earnedOn[m]) }
        .fullScreenCover(item: $weeklyReview) { launch in WeeklyReviewView(review: launch.review) }
        .lxToast($toast) {
            store.remove(undoIDs)
            undoIDs = []
        }
        .lxHaptic(.logged, trigger: loggedTick)
        .onAppear {
            store.onAppear()
            intelligence.attach(store)
            IntentRuntime.attach(store)
            LifeOSShortcuts.updateAppShortcutParameters()
            intelligence.refresh()
            if let route = intelligence.pendingRoute { handle(route) }
            backup.autoBackupIfDue()
            backup.scheduleRefreshNotification()
            achievements.refresh()
        }
        // Re-infer memories, fire "when I log…" rules and re-plan notifications after changes.
        .onReceive(store.objectWillChange.debounce(for: .milliseconds(700), scheduler: RunLoop.main)) { _ in
            intelligence.refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                store.reload()
                intelligence.refresh()
                backup.autoBackupIfDue()
                backup.scheduleRefreshNotification()
                achievements.refresh()
            }
        }
        .onChange(of: intelligence.pendingRoute) { _, route in if let route { handle(route) } }
        .onChange(of: intelligence.eventBanner) { _, b in
            guard let b else { return }
            banner = b
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                if banner?.id == b.id { banner = nil }
            }
        }
        .onChange(of: store.health.stepsToday) { _, steps in
            dependencies.watchConnectivity.latestSteps = steps
        }
        .onChange(of: tab) { _, new in
            if new == .capture { tab = .today; openCapture() }
        }
    }

    // MARK: Phase 4 surfaces

    @ViewBuilder private var eventBanner: some View {
        if let b = banner {
            LXInlineBanner(kind: .info, message: b.text, actionTitle: "Why?",
                           action: { banner = nil; automationsFocus = AutomationsLaunch(focus: b.ruleID) },
                           onDismiss: { banner = nil })
                .padding(.horizontal, LX.Space.s400)
                .padding(.top, LX.Space.s200)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var morningBrief: String? {
        guard Calendar.current.component(.hour, from: Date()) < 12, let snap = intelligence.latest else { return nil }
        return Briefs.morning(snap)
    }

    private var eveningRecap: String? {
        guard Calendar.current.component(.hour, from: Date()) >= 19, let snap = intelligence.latest, let today = snap.today, today.hasFood else { return nil }
        let perfect = store.todayScore == 4
        return Briefs.eveningRecap(today, perfectDay: perfect)
    }

    /// The review card shows on Sundays and Mondays; You → Weekly review always works when there's enough data.
    private var weeklyReviewAvailable: Bool {
        let weekday = Calendar.current.component(.weekday, from: Date())
        return (weekday == 1 || weekday == 2) && currentReview() != nil
    }

    private func currentReview() -> WeeklyReview? {
        intelligence.latest.flatMap(WeeklyReview.make)
    }

    private func openWeeklyReview() {
        if let r = currentReview() { weeklyReview = ReviewLaunch(review: r) }
    }

    private func openAssistant(context: String?, listening: Bool = false) {
        showCapture = false
        assistant = AssistantLaunch(context: context, listening: listening)
    }

    private func handle(_ route: IntelligenceStore.Route) {
        intelligence.pendingRoute = nil
        switch route {
        case .weeklyReview: openWeeklyReview()
        case .recap, .today: tab = .today
        case .training: tab = .training
        case .capture:
            // The Capture sheet starts in Say when speech permission exists (Phase 3 §3.2).
            tab = .today
            openCapture()
        case .automation(let id): automationsFocus = AutomationsLaunch(focus: id)
        case .logPreset(let id):
            tab = .today
            logPreset(id)
        }
    }

    private func afterDismiss(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            action()
        }
    }

    // MARK: Phase 3

    private func openCapture(typing: Bool = false, slot: ExperienceMealSlot? = nil) {
        captureStartsTyping = typing
        captureSlot = slot
        showCapture = true
    }

    private func logged(_ ids: [UUID], kcal: Double, protein: Double) {
        guard !ids.isEmpty else { return }
        undoIDs = ids
        loggedTick += 1
        toast = LXToastModel(message: ExperienceCopy.logged(kcal: Int(kcal.rounded()), proteinG: Int(protein.rounded())))
    }

    private func logPreset(_ id: String) {
        guard let ids = store.logPreset(id: id) else { return }
        let foods = store.items.filter { ids.contains($0.id) }
        logged(ids, kcal: foods.reduce(0) { $0 + $1.calories }, protein: foods.reduce(0) { $0 + $1.protein })
    }

    private func handleNextUp(_ action: ExperienceNextUp.Action) {
        switch action {
        case .capture: openCapture()
        case .logPreset(let id): logPreset(id)
        case .addWater:
            store.addWater(1)
            loggedTick += 1
        }
    }
}
