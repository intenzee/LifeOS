import SwiftUI

/// UI/UX Phase 3 shell: five labelled tabs with the raised Capture button
/// (master plan §5). Shown when `lx.newExperience` is on; the classic UI stays
/// one switch away in You → "Classic layout".
struct ExperienceRootView: View {
    let dependencies: AppDependencies
    @StateObject private var store: ExperienceStore

    @State private var tab: LXTab = .today
    @State private var showCapture = false
    @State private var captureStartsTyping = false
    @State private var captureSlot: ExperienceMealSlot?
    @State private var showBudget = false
    @State private var legacyRoute: LegacyCaptureRoute = .none
    @State private var toast: LXToastModel?
    @State private var undoIDs: [UUID] = []
    @State private var loggedTick = 0

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
                                onNextUp: handleNextUp)
                case .nutrition:
                    NutritionScreen(store: store, onCapture: { slot in openCapture(slot: slot) },
                                    onLogPreset: { id in logPreset(id) })
                case .training:
                    TrainingScreen(store: store, onBudget: { showBudget = true })
                case .you:
                    YouScreen(store: store)
                }
            }
            .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 76) } // last row clears the tab bar (audit A4)

            LXTabBar(selection: $tab,
                     onCapture: { openCapture() },
                     onAssistant: { openCapture(typing: true) })
                .padding(.bottom, 4)

            LegacyCaptureHost(route: $legacyRoute, slot: store.currentSlot, apiClient: dependencies.apiClient,
                              onLog: { food, source in logged(store.log([food], slot: ExperienceMealSlot(food.mealType), source: source),
                                                              kcal: food.calories, protein: food.protein) },
                              onSaveCustom: { dependencies.foodDatabase.addCustomFood($0) })
        }
        .sheet(isPresented: $showCapture) {
            CaptureSheet(store: store, startTyping: captureStartsTyping, initialSlot: captureSlot,
                         onLogged: { ids, kcal, protein in showCapture = false; logged(ids, kcal: kcal, protein: protein) },
                         onRoute: { route in
                             showCapture = false
                             // Let the sheet finish dismissing before the full-screen flow appears.
                             Task { @MainActor in
                                 try? await Task.sleep(for: .milliseconds(350))
                                 legacyRoute = route
                             }
                         })
                .lxSheetStyle()
        }
        .sheet(isPresented: $showBudget) {
            BudgetExplainerSheet(store: store).lxSheetStyle(detents: [.large])
        }
        .lxToast($toast) {
            store.remove(undoIDs)
            undoIDs = []
        }
        .lxHaptic(.logged, trigger: loggedTick)
        .onAppear { store.onAppear() }
        .onChange(of: store.health.stepsToday) { _, steps in
            dependencies.watchConnectivity.latestSteps = steps
        }
        .onChange(of: tab) { _, new in
            if new == .capture { tab = .today; openCapture() }
        }
    }

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
