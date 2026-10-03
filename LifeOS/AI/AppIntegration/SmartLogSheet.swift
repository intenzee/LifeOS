import Observation
import SwiftUI

/// Say it or type it: natural-language + voice food logging with presets
/// (F02, F03). Works fully on-device on any iPhone; a Groq/Gemini key only
/// improves parsing of unusual phrasing and estimates unknown foods.
struct SmartLogSheet: View {
    @State private var model: SmartLogModel
    @Binding var isPresented: Bool
    @State private var editingItem: ResolvedFoodItem?
    @State private var showPresets = false
    @State private var showLabelScan = false

    init(isPresented: Binding<Bool>, meal: MealType?, onLog: @escaping ([FoodItem]) -> Void) {
        _isPresented = isPresented
        _model = State(initialValue: SmartLogModel(preferredMeal: meal, onLog: onLog))
    }

    var body: some View {
        VStack(spacing: 0) {
            LXSheetHeader(title: "Log food", primaryTitle: "Presets", onClose: close, onPrimary: { showPresets = true })
            ScrollView {
                VStack(alignment: .leading, spacing: LX.Space.s400) {
                    if let suggestion = model.suggestion, model.phase == .input { suggestionCard(suggestion) }
                    if !model.quickPresets.isEmpty, model.phase == .input { presetChips }
                    inputSection
                    phaseContent
                    if let message = model.message {
                        LXInlineBanner(kind: message.isError ? .attention : .info, message: message.text,
                                       onDismiss: { model.message = nil })
                    }
                }
                .padding(LX.Space.s400)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(.lx(.surfaceRaised), ignoresSafeAreaEdges: .all)
        .task { await model.load() }
        .onDisappear { model.speech.cancel() }
        .sheet(item: $editingItem) { item in
            FoodItemEditor(item: item) { updated, remember in model.replace(updated, remember: remember) }
                .lxSheetStyle(detents: [.medium, .large])
        }
        .sheet(isPresented: $showPresets, onDismiss: { Task { await model.reloadPresets() } }) {
            PresetsView(onUse: { preset in
                showPresets = false
                model.use(preset)
            })
            .lxSheetStyle(detents: [.large])
        }
        .sheet(isPresented: $showLabelScan) {
            LabelScanView(meal: model.selectedMeal) { foods, summary in model.logExternal(foods, summary: summary) }
                .lxSheetStyle(detents: [.large])
        }
        .onChange(of: model.shouldClose) { _, close in if close { isPresented = false } }
    }

    private func close() {
        model.speech.cancel()
        isPresented = false
    }

    // MARK: Input

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            if model.speech.isListening, model.listeningFor == .meal {
                listeningView
            } else if model.phase == .input || model.phase == .thinking {
                LXTextField(label: "What did you eat?", text: $model.text,
                            placeholder: "2 rotis, dal and curd for lunch",
                            onVoice: { Task { await model.startVoice(.meal) } })
                    .onSubmit { Task { await model.submit() } }
                    .submitLabel(.done)
                Button {
                    Task { await model.submit() }
                } label: {
                    Text(model.phase == .thinking ? "Reading…" : "Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.lx(.primary, loading: model.phase == .thinking))
                .disabled(model.text.trimmingCharacters(in: .whitespaces).isEmpty || model.phase == .thinking)
                Text(model.engineNote).lxFont(.caption).foregroundStyle(.lx(.textTertiary))
                Button { showLabelScan = true } label: {
                    Label("Scan a nutrition label", systemImage: "text.viewfinder")
                }
                .buttonStyle(.lx(.plain))
            }
        }
    }

    private var listeningView: some View {
        VStack(spacing: LX.Space.s300) {
            Image(systemName: "waveform")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.lx(.accentPrimary))
                .scaleEffect(1 + model.speech.level * 0.35)
                .animation(.easeOut(duration: 0.12), value: model.speech.level)
            Text(model.speech.transcript.isEmpty ? "Listening… say what you ate" : model.speech.transcript)
                .lxFont(.headline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.lx(model.speech.transcript.isEmpty ? .textSecondary : .textPrimary))
            Text(model.speech.isOnDevice ? "Processed on this iPhone" : "Apple speech recognition")
                .lxFont(.caption).foregroundStyle(.lx(.textTertiary))
            Button("Done") { model.speech.stop() }.buttonStyle(.lx(.secondary))
        }
        .frame(maxWidth: .infinity)
        .lxCard(padding: LX.Space.s500)
    }

    private var presetChips: some View {
        VStack(alignment: .leading, spacing: LX.Space.s200) {
            Text("Your presets").lxFont(.footnote, weight: .medium).foregroundStyle(.lx(.textSecondary))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LX.Space.s200) {
                    ForEach(model.quickPresets) { preset in
                        Button { model.use(preset) } label: {
                            LXChip(title: preset.name, systemImage: "star.square.on.square", kind: .suggestion,
                                   trailing: "\(Int(preset.totals.kcal.rounded()))")
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func suggestionCard(_ suggestion: PresetSuggestion) -> some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            Label("Routine spotted", systemImage: "sparkles").lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.accentPrimary))
            Text(suggestion.message).lxFont(.subhead).foregroundStyle(.lx(.textPrimary)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: LX.Space.s300) {
                Button("Not now") { model.dismissSuggestion() }.buttonStyle(.lx(.secondary))
                Button("Save preset") { Task { await model.acceptSuggestion() } }.buttonStyle(.lx(.primary))
            }
        }
        .lxCard()
    }

    // MARK: Phases

    @ViewBuilder
    private var phaseContent: some View {
        switch model.phase {
        case .input, .thinking:
            EmptyView()
        case .draft:
            if let draft = model.draft { draftView(draft) }
        case .choose(let options):
            VStack(alignment: .leading, spacing: LX.Space.s300) {
                Text("Which one?").lxFont(.title3).foregroundStyle(.lx(.textPrimary))
                ForEach(options) { preset in
                    Button { model.use(preset, modifications: model.pendingModifications) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.name).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                                Text(preset.items.map(\.displayName).joined(separator: ", "))
                                    .lxFont(.footnote).foregroundStyle(.lx(.textSecondary)).lineLimit(1)
                            }
                            Spacer()
                            Text("\(Int(preset.totals.kcal.rounded())) kcal").lxFont(.subhead, numeric: true)
                        }
                        .lxCard()
                    }
                    .buttonStyle(.plain)
                }
                Button("None of these") { model.reset() }.buttonStyle(.lx(.plain))
            }
        case .define(let name):
            if let draft = model.draft {
                VStack(alignment: .leading, spacing: LX.Space.s300) {
                    LXTextField(label: "Preset name", text: $model.presetName, placeholder: name)
                    proposal(draft, savePreset: nil)
                    Button { Task { await model.saveDefinedPreset() } } label: {
                        Text("Save preset").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.lx(.secondary))
                }
            }
        case .logged(let summary):
            VStack(spacing: LX.Space.s300) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 44)).foregroundStyle(.lx(.statusOnTrack))
                Text(summary).lxFont(.headline).foregroundStyle(.lx(.textPrimary)).multilineTextAlignment(.center)
                HStack(spacing: LX.Space.s300) {
                    Button("Undo") { model.undo() }.buttonStyle(.lx(.secondary))
                    Button("Log more") { model.reset() }.buttonStyle(.lx(.plain))
                }
            }
            .frame(maxWidth: .infinity)
            .lxCard(padding: LX.Space.s500)
        }
    }

    private func draftView(_ draft: MealDraft) -> some View {
        VStack(alignment: .leading, spacing: LX.Space.s400) {
            LXSegmented(options: MealType.allCases.map { (label: $0.rawValue, value: $0) }, selection: $model.selectedMeal)
            if model.editing {
                editableItems(draft)
            } else {
                proposal(draft, savePreset: draft.preset == nil ? { model.showSavePreset = true } : nil)
            }
            if model.showSavePreset {
                VStack(alignment: .leading, spacing: LX.Space.s200) {
                    LXTextField(label: "Save as preset", text: $model.presetName, placeholder: model.suggestedPresetName)
                    HStack {
                        Button("Cancel") { model.showSavePreset = false }.buttonStyle(.lx(.plain))
                        Spacer()
                        Button("Save") { Task { await model.saveCurrentAsPreset() } }.buttonStyle(.lx(.primary))
                    }
                }
                .lxCard()
            }
            correctionField
        }
    }

    private func proposal(_ draft: MealDraft, savePreset: (() -> Void)?) -> some View {
        LXProposalCard(
            mealTitle: model.selectedMeal.rawValue,
            time: Date().formatted(date: .omitted, time: .shortened),
            source: model.sourceBadge,
            items: draft.items.map { item in
                LXProposalItem(id: item.id.uuidString, name: item.displayName.capitalizedFirst,
                               amount: item.matchKind == .unresolved ? "\(item.servingDescription) · add calories" : item.servingDescription,
                               kcal: Int(item.macros.kcal.rounded()), confidence: item.lxConfidence)
            },
            macros: [
                .init(name: "Protein", grams: draft.totals.protein, target: 120, role: .dataProtein),
                .init(name: "Carbs", grams: draft.totals.carbs, target: 250, role: .dataCarbs),
                .init(name: "Fat", grams: draft.totals.fat, target: 70, role: .dataFat),
            ],
            note: model.draftNote,
            onLog: { model.log() },
            onEdit: { model.editing = true },
            onSavePreset: savePreset)
    }

    private func editableItems(_ draft: MealDraft) -> some View {
        VStack(alignment: .leading, spacing: LX.Space.s200) {
            ForEach(draft.items) { item in
                HStack(spacing: LX.Space.s300) {
                    LXConfidenceDot(confidence: item.lxConfidence)
                    Button { editingItem = item } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.displayName.capitalizedFirst).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                            Text("\(item.servingDescription) · \(Int(item.macros.kcal.rounded())) kcal")
                                .lxFont(.footnote, numeric: true)
                                .foregroundStyle(.lx(item.needsReview ? .statusAttention : .textSecondary))
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    stepButton("minus", enabled: item.quantity > 0.5) { model.changeQuantity(item.id, by: -step(for: item)) }
                    Text(item.quantity.formatted(.number.precision(.fractionLength(0...1))))
                        .lxFont(.headline, numeric: true).frame(minWidth: 28)
                    stepButton("plus", enabled: true) { model.changeQuantity(item.id, by: step(for: item)) }
                    Button { model.remove(item.id) } label: {
                        Image(systemName: "trash").foregroundStyle(.lx(.statusOver))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(item.displayName)")
                }
                .padding(.vertical, LX.Space.s100)
            }
            HStack {
                Text("\(Int(draft.totals.kcal.rounded())) kcal total").lxFont(.headline, numeric: true)
                Spacer()
                Button("Done") { model.editing = false }.buttonStyle(.lx(.primary))
            }
        }
        .lxCard()
    }

    private var correctionField: some View {
        VStack(alignment: .leading, spacing: LX.Space.s200) {
            if model.speech.isListening, model.listeningFor == .correction {
                listeningView
            } else {
                LXTextField(label: "Correct it in words", text: $model.correction,
                            placeholder: "no curd, 3 rotis, add a banana",
                            onVoice: { Task { await model.startVoice(.correction) } })
                    .onSubmit { Task { await model.applyCorrection() } }
                    .submitLabel(.done)
                if !model.correction.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Apply correction") { Task { await model.applyCorrection() } }.buttonStyle(.lx(.secondary))
                }
            }
        }
    }

    private func step(for item: ResolvedFoodItem) -> Double {
        switch item.unit {
        case "g", "ml": 25
        case "piece", "slice", "tsp", "tbsp", "scoop": 1
        default: 0.5
        }
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.footnote.weight(.bold)).frame(width: 32, height: 32)
                .background(Circle().fill(.lx(.surfaceRaised)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(icon == "plus" ? "More" : "Less")
    }
}

// MARK: - Model

@Observable
final class SmartLogModel {
    enum Phase: Equatable {
        case input, thinking, draft
        case choose([FoodPreset])
        case define(String)
        case logged(String)
    }
    enum ListeningTarget { case meal, correction }
    struct Message: Equatable { var text: String; var isError: Bool }

    var phase: Phase = .input
    var text = ""
    var correction = ""
    var draft: MealDraft? {
        didSet { if let draft, oldValue?.items.map(\.id) != draft.items.map(\.id) || oldValue == nil { syncMeal(from: draft) } }
    }
    var selectedMeal: MealType = .lunch
    var editing = false
    var showSavePreset = false
    var presetName = ""
    var message: Message?
    var quickPresets: [FoodPreset] = []
    var suggestion: PresetSuggestion?
    var pendingModifications: String?
    var listeningFor: ListeningTarget = .meal
    var shouldClose = false
    var engineNote = "Understood on this iPhone"
    let speech = SpeechCaptureService()

    private let preferredMeal: MealType?
    private let onLog: ([FoodItem]) -> Void
    private var loggedIDs: [UUID] = []
    private var loggedDraft: MealDraft?
    private var rememberedEdits: [UUID: Bool] = [:]
    private let logger = AIServices.shared.foodLogger
    private static let dismissedKey = "ai.presetSuggestions.dismissed"

    init(preferredMeal: MealType?, onLog: @escaping ([FoodItem]) -> Void) {
        self.preferredMeal = preferredMeal
        self.onLog = onLog
        selectedMeal = preferredMeal ?? ParsedMeal.MealSlot.inferred().mealType ?? .lunch
    }

    // MARK: Lifecycle

    func load() async {
        await reloadPresets()
        let presets = await AIServices.shared.presets.all()
        let dismissed = Set(UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? [])
        suggestion = RoutineMiner.suggest(history: AIServices.recentMeals(), existing: presets, dismissed: dismissed)
        speech.contextualStrings = await AIServices.shared.speechVocabulary()
        let availability = await AIServices.shared.gateway.availability(for: .foodTextParse)
        engineNote = switch availability.primary {
        case .appleOnDevice?, .applePCC?: "Understood by Apple Intelligence, privately"
        case .geminiBYOK?, .groqBYOK?: "Understood with your \(availability.primary == .groqBYOK ? "Groq" : "Gemini") key"
        default: "Understood on this iPhone · add a Groq or Gemini key for tricky phrasing"
        }
        await AIServices.shared.gateway.prewarm(for: .foodTextParse)
    }

    func reloadPresets() async {
        let all = await AIServices.shared.presets.all().filter { !$0.archived }
        let ranked = PresetResolver(presets: all).rank("my usual").map(\.preset)
        quickPresets = Array((ranked + all).reduce(into: [FoodPreset]()) { result, preset in
            if !result.contains(where: { $0.id == preset.id }) { result.append(preset) }
        }.prefix(6))
    }

    // MARK: Actions

    func submit() async {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        message = nil
        phase = .thinking
        let outcome = await logger.interpret(input, current: draft)
        handle(outcome)
    }

    private func handle(_ outcome: SmartLogOutcome) {
        switch outcome {
        case .draft(let draft):
            var draft = draft
            if draft.mealWasInferred, let preferredMeal { draft.meal = ParsedMeal.MealSlot(preferredMeal) }
            self.draft = draft
            editing = draft.items.contains { $0.matchKind == .unresolved }
            phase = .draft
        case .choosePreset(let options, let modifications):
            pendingModifications = modifications
            phase = .choose(options)
        case .definePreset(let name, let draft):
            self.draft = draft
            presetName = SmartFoodLogger.presetDisplayName(name)
            phase = .define(presetName)
        case .saveDraftAsPreset(let name):
            presetName = SmartFoodLogger.presetDisplayName(name)
            Task { await saveCurrentAsPreset() }
            phase = draft == nil ? .input : .draft
        case .notFood(let reason):
            message = Message(text: reason, isError: true)
            phase = draft == nil ? .input : .draft
        }
    }

    func use(_ preset: FoodPreset, modifications: String? = nil) {
        var draft = logger.draft(from: preset, modifications: modifications)
        if draft.mealWasInferred, let preferredMeal { draft.meal = ParsedMeal.MealSlot(preferredMeal) }
        self.draft = draft
        pendingModifications = nil
        phase = .draft
    }

    func applyCorrection() async {
        let note = correction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let draft, !note.isEmpty else { return }
        if let name = SmartFoodLogger.saveCurrentIntent(note) {
            presetName = SmartFoodLogger.presetDisplayName(name)
            correction = ""
            await saveCurrentAsPreset()
            return
        }
        var updated = await logger.refine(draft, with: note)
        if updated.meal != draft.meal, let meal = updated.meal.mealType { selectedMeal = meal }
        updated.meal = ParsedMeal.MealSlot(selectedMeal)
        self.draft = updated
        correction = ""
    }

    func changeQuantity(_ id: UUID, by delta: Double) {
        guard var draft, let index = draft.items.firstIndex(where: { $0.id == id }) else { return }
        draft.items[index].setQuantity(max(0.5, draft.items[index].quantity + delta))
        self.draft = draft
    }

    func remove(_ id: UUID) {
        guard var draft else { return }
        draft.items.removeAll { $0.id == id }
        self.draft = draft
        if draft.items.isEmpty { reset() }
    }

    func replace(_ item: ResolvedFoodItem, remember: Bool) {
        guard var draft, let index = draft.items.firstIndex(where: { $0.id == item.id }) else { return }
        draft.items[index] = item
        self.draft = draft
        rememberedEdits[item.id] = remember
    }

    func log() {
        guard let draft, !draft.items.isEmpty else { return }
        let source: EntrySource = draft.preset == nil ? .nlAI : .preset
        let now = Date()
        let foods = draft.items.map { item in
            FoodItem(name: item.displayName.capitalizedFirst, calories: item.macros.kcal.rounded(),
                     protein: item.macros.protein.rounded(toPlaces: 1), carbs: item.macros.carbs.rounded(toPlaces: 1),
                     fat: item.macros.fat.rounded(toPlaces: 1), servingSize: item.servingDescription,
                     mealType: selectedMeal, timestamp: now, source: source, aiConfidence: item.confidence)
        }
        // Foods the user filled in by hand become custom foods, so next time
        // the resolver uses their numbers (learning loop, F02 §4.6).
        for item in draft.items where rememberedEdits[item.id] == true {
            let perUnit = item.macrosPerUnit
            FoodDatabaseManager.shared.addCustomFood(FoodItem(
                name: item.displayName.capitalizedFirst, calories: perUnit.kcal.rounded(), protein: perUnit.protein,
                carbs: perUnit.carbs, fat: perUnit.fat, servingSize: "1 \(item.unit)", mealType: selectedMeal))
        }
        onLog(foods)
        loggedIDs = foods.map(\.id)
        loggedDraft = draft
        Task { await logger.didLog(draft, at: now) }
        let kcal = Int(draft.totals.kcal.rounded())
        phase = .logged("Logged \(foods.count) item\(foods.count == 1 ? "" : "s") · \(kcal) kcal to \(selectedMeal.rawValue.lowercased())")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let ids = loggedIDs
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self, self.loggedIDs == ids, case .logged = self.phase else { return }
            self.shouldClose = true
        }
    }

    /// Logs foods produced elsewhere (label scan) with the same undo flow.
    func logExternal(_ foods: [FoodItem], summary: String) {
        onLog(foods)
        loggedIDs = foods.map(\.id)
        loggedDraft = nil
        phase = .logged(summary)
    }

    func undo() {
        for id in loggedIDs { FoodDatabaseManager.shared.removeFood(id) }
        loggedIDs = []
        draft = loggedDraft
        phase = loggedDraft == nil ? .input : .draft
        message = Message(text: "Removed from your log.", isError: false)
    }

    func reset() {
        draft = nil
        text = ""
        correction = ""
        editing = false
        showSavePreset = false
        loggedIDs = []
        phase = .input
    }

    // MARK: Presets

    var suggestedPresetName: String {
        guard let draft else { return "My usual" }
        return PresetNamer.suggest(items: draft.items.map(\.displayName), meal: ParsedMeal.MealSlot(selectedMeal))
    }

    func saveCurrentAsPreset() async {
        guard var draft else { return }
        draft.meal = ParsedMeal.MealSlot(selectedMeal)
        let name = presetName.trimmingCharacters(in: .whitespaces).isEmpty ? suggestedPresetName : presetName
        let preset = await logger.savePreset(named: name, from: draft)
        self.draft?.preset = preset
        showSavePreset = false
        presetName = ""
        message = Message(text: "Saved “\(preset.name)”. Next time just say “log \(preset.name.lowercased())”.", isError: false)
        await reloadPresets()
    }

    func saveDefinedPreset() async {
        guard let draft else { return }
        let preset = await logger.savePreset(named: presetName.isEmpty ? suggestedPresetName : presetName, from: draft)
        message = Message(text: "Saved “\(preset.name)”.", isError: false)
        self.draft?.preset = preset
        phase = .draft
        await reloadPresets()
    }

    func acceptSuggestion() async {
        guard let suggestion else { return }
        let draft = MealDraft(items: suggestion.items, meal: suggestion.meal, mealWasInferred: false, parsedBy: nil,
                              preset: nil, sourceText: suggestion.name)
        let preset = await logger.savePreset(named: suggestion.name, from: draft, source: .aiSuggested)
        self.suggestion = nil
        message = Message(text: "Saved “\(preset.name)”. Tap it above to log it any time.", isError: false)
        await reloadPresets()
    }

    func dismissSuggestion() {
        guard let suggestion else { return }
        var dismissed = UserDefaults.standard.stringArray(forKey: Self.dismissedKey) ?? []
        dismissed.append(suggestion.id)
        UserDefaults.standard.set(dismissed, forKey: Self.dismissedKey)
        self.suggestion = nil
    }

    // MARK: Voice

    func startVoice(_ target: ListeningTarget) async {
        listeningFor = target
        await speech.start { [weak self] transcript in
            guard let self, !transcript.isEmpty else { return }
            switch target {
            case .meal:
                self.text = transcript
                Task { await self.submit() }
            case .correction:
                self.correction = transcript
                Task { await self.applyCorrection() }
            }
        }
        if case .failed(let reason) = speech.phase { message = Message(text: reason, isError: true) }
    }

    // MARK: Display

    var sourceBadge: LXSource {
        guard let draft else { return .onDevice }
        if draft.preset != nil { return .preset }
        switch draft.parsedBy {
        case .groqBYOK?: return .groq
        case .geminiBYOK?: return .gemini
        default: return .onDevice
        }
    }

    var draftNote: String? {
        guard let draft else { return nil }
        let unresolved = draft.items.filter { $0.matchKind == .unresolved }.count
        if unresolved > 0 { return "\(unresolved) item\(unresolved == 1 ? "" : "s") need calories — tap Edit" }
        if draft.items.contains(where: { $0.matchKind == .modelEstimate }) { return "Includes AI estimates" }
        if draft.needsReview { return "Check highlighted portions" }
        return nil
    }

    private func syncMeal(from draft: MealDraft) {
        if let meal = draft.meal.mealType { selectedMeal = meal }
    }
}

// MARK: - Item editor

/// Fix an item by hand — name, amount and nutrition. Unknown foods can be
/// remembered as custom foods so they resolve next time.
struct FoodItemEditor: View {
    @Environment(\.dismiss) private var dismiss
    let item: ResolvedFoodItem
    let onSave: (ResolvedFoodItem, Bool) -> Void

    @State private var name: String
    @State private var quantity: String
    @State private var kcal: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var remember: Bool

    init(item: ResolvedFoodItem, onSave: @escaping (ResolvedFoodItem, Bool) -> Void) {
        self.item = item
        self.onSave = onSave
        func text(_ v: Double) -> String { v == 0 ? "" : v.formatted(.number.precision(.fractionLength(0...1))) }
        _name = State(initialValue: item.displayName.capitalizedFirst)
        _quantity = State(initialValue: item.quantity.formatted(.number.precision(.fractionLength(0...2))))
        _kcal = State(initialValue: text(item.macros.kcal.rounded()))
        _protein = State(initialValue: text(item.macros.protein))
        _carbs = State(initialValue: text(item.macros.carbs))
        _fat = State(initialValue: text(item.macros.fat))
        _remember = State(initialValue: item.matchKind == .unresolved)
    }

    var body: some View {
        VStack(spacing: 0) {
            LXSheetHeader(title: "Edit item", primaryTitle: "Save", primaryEnabled: Double(kcal) != nil,
                          onClose: { dismiss() }, onPrimary: save)
            ScrollView {
                VStack(spacing: LX.Space.s300) {
                    LXTextField(label: "Food", text: $name)
                    LXTextField(label: "Amount", text: $quantity, unit: item.unit, isNumeric: true)
                    LXTextField(label: "Calories (total)", text: $kcal, unit: "kcal", isNumeric: true)
                    HStack(spacing: LX.Space.s200) {
                        LXTextField(label: "Protein", text: $protein, unit: "g", isNumeric: true)
                        LXTextField(label: "Carbs", text: $carbs, unit: "g", isNumeric: true)
                        LXTextField(label: "Fat", text: $fat, unit: "g", isNumeric: true)
                    }
                    LXToggleRow(title: "Remember for next time", isOn: $remember)
                }
                .padding(LX.Space.s400)
            }
        }
        .background(.lx(.surfaceRaised), ignoresSafeAreaEdges: .all)
    }

    private func save() {
        let qty = max(0.1, Double(quantity) ?? item.quantity)
        let total = Macros(kcal: Double(kcal) ?? 0, protein: Double(protein) ?? 0, carbs: Double(carbs) ?? 0, fat: Double(fat) ?? 0)
        var updated = item
        updated.displayName = name.trimmingCharacters(in: .whitespaces).isEmpty ? item.displayName : name
        updated.quantity = qty
        if let grams = item.grams, item.quantity > 0 { updated.grams = grams / item.quantity * qty }
        updated.macros = total
        updated.macrosPerUnit = total.scaled(1 / qty)
        updated.matchKind = .userFood
        updated.sourceRef = "user:edited"
        updated.parseConfidence = 1
        updated.unitConfidence = 1
        onSave(updated, remember)
        dismiss()
    }
}

// MARK: - Helpers

extension ResolvedFoodItem {
    var lxConfidence: LXConfidence {
        switch band {
        case .high: .high
        case .medium: .medium
        case .low: .low
        }
    }
}

extension ParsedMeal.MealSlot {
    static func inferred(at date: Date = Date()) -> ParsedMeal.MealSlot { SmartFoodLogger.inferMeal(at: date) }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

private extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10, Double(places))
        return (self * factor).rounded() / factor
    }
}
