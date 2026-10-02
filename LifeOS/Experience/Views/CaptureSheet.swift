import Speech
import SwiftUI

/// 3.2 Capture sheet + 3.3 proposal card.
/// "Let me log anything the fastest way I can, and let the app work out the details."
struct CaptureSheet: View {
    @ObservedObject var store: ExperienceStore
    var startTyping = false
    var initialSlot: ExperienceMealSlot? = nil
    var onLogged: (_ ids: [UUID], _ kcal: Double, _ protein: Double) -> Void
    var onRoute: (LegacyCaptureRoute) -> Void

    private enum Stage: Equatable {
        case input
        case thinking(String)
        case proposal(CaptureProposal)
        case editing(CaptureProposal)
        case nothing(String)
    }

    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechCapture()
    @State private var stage: Stage = .input
    @State private var slot: ExperienceMealSlot = .lunch
    @State private var text = ""
    @State private var showWeight = false
    @State private var waterTick = 0
    @State private var savedPresetTick = 0
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            LXSheetHeader(title: title, onClose: { speech.cancel(); dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: LX.Space.s500) {
                    switch stage {
                    case .input: inputStage
                    case .thinking(let heard): thinkingStage(heard)
                    case .proposal(let p): proposalStage(p)
                    case .editing(let p): CaptureEditor(proposal: p, onDone: { stage = .proposal($0) })
                    case .nothing(let heard): nothingStage(heard)
                    }
                }
                .padding(LX.Space.s400)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background { Rectangle().fill(.lx(.background)).ignoresSafeArea() }
        .sheet(isPresented: $showWeight) { WeightQuickSheet(store: store).lxSheetStyle(detents: [.medium]) }
        .onAppear {
            slot = initialSlot ?? store.currentSlot
            if startTyping {
                typing = true
            } else if SFSpeechRecognizer.authorizationStatus() == .authorized {
                // Opens listening (Phase 3 §3.2) once permission exists; never prompts on open.
                Task { await speech.start() }
            }
        }
        .onDisappear { speech.cancel() }
        .onChange(of: speech.phase) { _, phase in
            if case .finished(let heard) = phase { understand(heard, source: .voice) }
        }
        .lxHaptic(.logged, trigger: waterTick)
        .lxHaptic(.logged, trigger: savedPresetTick)
        .lxAnimation(.smooth, value: stage)
    }

    private var title: String {
        switch stage {
        case .proposal, .editing: return "Check and log"
        default: return "Capture"
        }
    }

    // MARK: - Input

    @ViewBuilder private var inputStage: some View {
        slotPicker
        sayButton
        typeField
        presetRow
        modeRow
    }

    private var slotPicker: some View {
        ScrollView(.horizontal) {
            HStack(spacing: LX.Space.s200) {
                ForEach(ExperienceMealSlot.allCases, id: \.self) { s in
                    Button { slot = s } label: {
                        LXChip(title: s.title, systemImage: s.systemImage, kind: .filter(selected: s == slot))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(s == slot ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .lxHaptic(.selection, trigger: slot)
    }

    private var sayButton: some View {
        let listening = speech.phase == .listening
        return VStack(spacing: LX.Space.s300) {
            Button {
                if listening { speech.finish() } else { typing = false; Task { await speech.start() } }
            } label: {
                ZStack {
                    Circle().fill(.lx(.accentPrimary).opacity(0.18))
                        .frame(width: 112, height: 112)
                        .scaleEffect(listening ? 1 + speech.level * 0.35 : 1)
                    Circle().fill(.lx(.accentPrimary)).frame(width: 76, height: 76)
                    Image(systemName: listening ? "waveform" : "mic.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.lx(.onAccent))
                        .symbolEffect(.variableColor.iterative, isActive: listening)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(listening ? "Stop listening" : "Say what you ate")
            .animation(.easeOut(duration: 0.12), value: speech.level)

            Group {
                switch speech.phase {
                case .listening:
                    Text(speech.transcript.isEmpty ? "Listening…" : speech.transcript)
                        .foregroundStyle(speech.transcript.isEmpty ? .lx(.textSecondary) : .lx(.textPrimary))
                case .nothingHeard:
                    Text("I didn't catch that. Try again or type it.").foregroundStyle(.lx(.textSecondary))
                case .denied:
                    VStack(spacing: LX.Space.s200) {
                        Text("Microphone or speech is off for LifeOS. Type instead, or allow it in Settings.")
                            .foregroundStyle(.lx(.textSecondary))
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                        }
                        .buttonStyle(.lx(.plain))
                    }
                case .unavailable:
                    Text("Speech isn't available right now. Type it instead.").foregroundStyle(.lx(.textSecondary))
                default:
                    Text("Tap and say it: \"two rotis, dal and a cup of chai\"").foregroundStyle(.lx(.textSecondary))
                }
            }
            .lxFont(.callout)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .animation(.default, value: speech.transcript)

            if listening && speech.isOnDevice {
                LXSourceBadge(source: .onDevice)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LX.Space.s200)
    }

    private var typeField: some View {
        HStack(spacing: LX.Space.s200) {
            TextField("Or type: 2 rotis, dal, cup of chai", text: $text, axis: .vertical)
                .lxFont(.body)
                .lineLimit(1...3)
                .focused($typing)
                .submitLabel(.done)
                .onSubmit { understand(text, source: .manual) }
                .padding(.horizontal, LX.Space.s400)
                .padding(.vertical, LX.Space.s300)
                .background(RoundedRectangle(cornerRadius: LX.Radius.tile, style: .continuous).fill(.lx(.surfaceRaised)))
                .onChange(of: typing) { _, isTyping in if isTyping { speech.cancel() } }
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                LXIconButton(systemImage: "arrow.up", label: "Understand", glass: false) { understand(text, source: .manual) }
                    .background(Circle().fill(.lx(.accentPrimary).opacity(0.18)))
            }
        }
    }

    @ViewBuilder private var presetRow: some View {
        let presets = store.presets(for: slot)
        if !presets.isEmpty {
            VStack(alignment: .leading, spacing: LX.Space.s200) {
                Text("Usual for \(slot.title.lowercased())").lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.textSecondary))
                ScrollView(.horizontal) {
                    HStack(spacing: LX.Space.s200) {
                        ForEach(presets) { p in
                            Button { logPreset(p) } label: {
                                LXChip(title: p.nutrient.name, systemImage: p.isFavorite ? "star.fill" : nil,
                                       kind: .suggestion, trailing: "\(Int(p.nutrient.kcal))")
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Log \(p.nutrient.name), \(Int(p.nutrient.kcal)) kilocalories")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private var modeRow: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: LX.Space.s200), count: 5), spacing: LX.Space.s200) {
            modeButton("Photo", "camera.fill") { onRoute(.photo) }
            modeButton("Scan", "barcode.viewfinder") { onRoute(.barcode) }
            modeButton("Search", "magnifyingglass") { onRoute(.search) }
            modeButton(store.isToday ? "Water \(store.waterCount)" : "Water", "drop.fill", role: .dataWater) {
                store.addWater(1)
                waterTick += 1
            }
            .disabled(!store.isToday)
            modeButton("Weight", "scalemass.fill", role: .dataWeight) { showWeight = true }
        }
    }

    private func modeButton(_ label: String, _ icon: String, role: LXColorRole = .accentPrimary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.title3).foregroundStyle(.lx(role)).frame(height: 26)
                Text(label).lxFont(.caption, numeric: true).foregroundStyle(.lx(.textPrimary)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(RoundedRectangle(cornerRadius: LX.Radius.tile, style: .continuous).fill(.lx(.surface)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Thinking / nothing

    private func thinkingStage(_ heard: String) -> some View {
        VStack(spacing: LX.Space.s400) {
            Text("“\(heard)”").lxFont(.title3).foregroundStyle(.lx(.textPrimary)).multilineTextAlignment(.center)
            ProgressView()
            Text("Working out the portions…").lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LX.Space.s700)
        .accessibilityElement(children: .combine)
    }

    private func nothingStage(_ heard: String) -> some View {
        VStack(alignment: .leading, spacing: LX.Space.s400) {
            LXInlineBanner(kind: .attention, message: "I couldn't find food in “\(heard)”. Try again, type it, or pick one of these.")
            presetRow
            Button("Try again") { stage = .input; text = heard; typing = true }
                .buttonStyle(.lx(.secondary))
        }
    }

    // MARK: - Proposal

    @ViewBuilder private func proposalStage(_ p: CaptureProposal) -> some View {
        HStack(spacing: LX.Space.s200) {
            Text("“\(p.heard)”").lxFont(.footnote).foregroundStyle(.lx(.textSecondary)).lineLimit(2)
            Spacer(minLength: 0)
            LXChip(title: p.engineNote, systemImage: p.engineNote.hasPrefix("Offline") ? "wifi.slash" : "sparkles", kind: .neutral)
        }
        if p.unresolvedCount > 0 {
            LXInlineBanner(kind: .attention, message: p.unresolvedCount == 1
                           ? "One item isn't in your foods yet. Tap Edit to add its calories."
                           : "\(p.unresolvedCount) items aren't in your foods yet. Tap Edit to add their calories.")
        }
        LXProposalCard(
            mealTitle: p.slot.title,
            time: Date().formatted(date: .omitted, time: .shortened),
            source: p.source.lxSource == .manual ? .onDevice : p.source.lxSource,
            items: p.items.map { LXProposalItem(id: $0.id, name: $0.name, amount: $0.amountText, kcal: Int($0.nutrient.kcal), confidence: $0.confidence.lx) },
            macros: macros(p),
            note: p.items.first(where: { $0.confidence == .low }).map { "Check the \($0.name.lowercased())." },
            onLog: { log(p) },
            onEdit: { stage = .editing(p) },
            onSavePreset: p.items.isEmpty ? nil : { savePreset(p) })
        mealSlotSwitcher(p)
        Button("Start over") { stage = .input; text = "" }
            .buttonStyle(.lx(.plain)).frame(maxWidth: .infinity)
    }

    private func mealSlotSwitcher(_ p: CaptureProposal) -> some View {
        HStack {
            Text("Meal").lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
            Spacer()
            Menu {
                ForEach(ExperienceMealSlot.allCases, id: \.self) { s in
                    Button(s.title) { var q = p; q.slot = s; slot = s; stage = .proposal(q) }
                }
            } label: {
                LXChip(title: p.slot.title, systemImage: p.slot.systemImage, kind: .neutral, trailing: "Change")
            }
        }
    }

    private func macros(_ p: CaptureProposal) -> [LXMacroBar.Macro] {
        let t = store.macroTargets
        let prot = p.items.reduce(0) { $0 + $1.nutrient.protein }
        let carb = p.items.reduce(0) { $0 + $1.nutrient.carbs }
        let fat = p.items.reduce(0) { $0 + $1.nutrient.fat }
        // Meal-sized targets: a third of the day.
        return [
            .init(name: "Protein", grams: prot, target: t.protein / 3, role: .dataProtein),
            .init(name: "Carbs", grams: carb, target: t.carbs / 3, role: .dataCarbs),
            .init(name: "Fat", grams: fat, target: t.fat / 3, role: .dataFat),
        ]
    }

    // MARK: - Actions

    private func understand(_ sentence: String, source: ExperienceTimelineEntry.Source) {
        let heard = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else { return }
        typing = false
        stage = .thinking(heard)
        let userFoods = store.userNutrients
        let fallbackSlot = slot
        Task { @MainActor in
            var proposal = await CaptureEngine.propose(heard, source: source, defaultSlot: fallbackSlot, userFoods: userFoods)
            if proposal.items.isEmpty, proposal.presetPhrase != nil, let preset = store.presets(for: proposal.slot, limit: 1).first {
                // "my usual breakfast" → the top usual for that meal.
                proposal.items = [ExperienceResolvedItem(id: preset.id, name: preset.nutrient.name, quantity: 1, unit: "serving",
                                                         nutrient: preset.nutrient, confidence: .high)]
                proposal.source = .preset
            }
            slot = proposal.slot
            stage = proposal.items.isEmpty ? .nothing(heard) : .proposal(proposal)
        }
    }

    private func log(_ p: CaptureProposal) {
        let foods = p.items.map { FoodItem($0, slot: p.slot) }
        let ids = store.log(foods, slot: p.slot, source: p.source)
        onLogged(ids, foods.reduce(0) { $0 + $1.calories }, foods.reduce(0) { $0 + $1.protein })
    }

    private func logPreset(_ preset: ExperiencePresetCandidate) {
        guard let ids = store.logPreset(id: preset.id) else { return }
        onLogged(ids, preset.nutrient.kcal, preset.nutrient.protein)
    }

    /// Saves the whole proposal as one favourite food ("My Meals" lite; full presets are §3.4).
    private func savePreset(_ p: CaptureProposal) {
        let name = p.items.count == 1 ? p.items[0].name : p.items.map(\.name).joined(separator: ", ")
        let n = p.items.reduce(ExperienceNutrient(name: name, kcal: 0, serving: "1 meal")) { acc, i in
            ExperienceNutrient(name: name, kcal: acc.kcal + i.nutrient.kcal, protein: acc.protein + i.nutrient.protein,
                               carbs: acc.carbs + i.nutrient.carbs, fat: acc.fat + i.nutrient.fat, serving: "1 meal")
        }
        let food = FoodItem(name: String(name.prefix(60)), calories: n.kcal, protein: (n.protein * 10).rounded() / 10,
                            carbs: (n.carbs * 10).rounded() / 10, fat: (n.fat * 10).rounded() / 10,
                            servingSize: "1 meal", mealType: p.slot.mealType)
        store.dependencies.foodDatabase.addCustomFood(food)
        if !store.dependencies.foodDatabase.isFavorite(food) { store.toggleFavorite(food) }
        savedPresetTick += 1
    }
}

/// Inline edit of a proposal (3.3 "editing a value recalculates totals immediately").
private struct CaptureEditor: View {
    @State var proposal: CaptureProposal
    var onDone: (CaptureProposal) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s400) {
            ForEach($proposal.items) { $item in
                ItemEditorRow(item: $item, onDelete: { proposal.items.removeAll { $0.id == item.id } })
            }
            HStack(alignment: .firstTextBaseline) {
                Text("Total").lxFont(.headline).foregroundStyle(.lx(.textSecondary))
                Spacer()
                Text("\(proposal.totalKcal) kcal").lxFont(.title2, numeric: true).foregroundStyle(.lx(.textPrimary))
                    .lxNumberRoll(Double(proposal.totalKcal))
            }
            Button { onDone(proposal) } label: { Text("Done").frame(maxWidth: .infinity) }
                .buttonStyle(.lx(.primary))
                .disabled(proposal.items.isEmpty)
        }
    }
}

private struct ItemEditorRow: View {
    @Binding var item: ExperienceResolvedItem
    var onDelete: () -> Void
    @State private var kcalText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            HStack {
                TextField("Food", text: $item.name).lxFont(.headline)
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(.lx(.textTertiary))
                    .accessibilityLabel("Remove \(item.name)")
            }
            HStack(spacing: LX.Space.s300) {
                Stepper(value: Binding(get: { item.quantity }, set: { setQuantity($0) }), in: 0.5...20, step: 0.5) {
                    Text(item.amountText).lxFont(.subhead, numeric: true).foregroundStyle(.lx(.textSecondary))
                }
            }
            HStack {
                Text("kcal").lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                TextField("0", text: $kcalText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .lxFont(.headline, numeric: true)
                    .onChange(of: kcalText) { _, v in
                        if let k = Double(v), k != item.nutrient.kcal {
                            item.nutrient.kcal = k
                            item.confidence = .high // the user said so
                        }
                    }
            }
        }
        .lxCard(padding: LX.Space.s400)
        .onAppear { kcalText = String(Int(item.nutrient.kcal)) }
        .onChange(of: item.nutrient.kcal) { _, k in
            if Double(kcalText) != k { kcalText = String(Int(k)) }
        }
    }

    private func setQuantity(_ q: Double) {
        guard item.quantity > 0 else { item.quantity = q; return }
        let f = q / item.quantity
        let n = item.nutrient.scaled(f)
        item.quantity = q
        item.nutrient = n
    }
}
