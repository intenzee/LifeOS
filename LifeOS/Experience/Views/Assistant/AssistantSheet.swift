import Charts
import SwiftUI

/// 4.1 Assistant: a large sheet over the current screen, so you keep your place.
struct AssistantSheet: View {
    @ObservedObject var store: ExperienceStore
    @ObservedObject var intelligence: IntelligenceStore = .shared
    var startListening = false
    var onLogged: (_ ids: [UUID], _ kcal: Double, _ protein: Double) -> Void
    var onEditInCapture: (String) -> Void
    var onEditRule: (AutomationRule) -> Void

    @StateObject private var session: AssistantSession
    @StateObject private var speech = SpeechCapture()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lxTheme) private var theme
    @State private var input = ""
    @FocusState private var typing: Bool

    init(store: ExperienceStore, contextChip: String?, startListening: Bool = false,
         onLogged: @escaping (_ ids: [UUID], _ kcal: Double, _ protein: Double) -> Void,
         onEditInCapture: @escaping (String) -> Void,
         onEditRule: @escaping (AutomationRule) -> Void) {
        self.store = store
        self.startListening = startListening
        self.onLogged = onLogged
        self.onEditInCapture = onEditInCapture
        self.onEditRule = onEditRule
        _session = StateObject(wrappedValue: AssistantSession(contextChip: contextChip))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            conversation
            if let i = session.pendingCardIndex {
                // "Needs confirmation": the card stays pinned above the input until answered.
                card(for: session.messages[i], pinned: true)
                    .padding(.horizontal, LX.Space.s400)
                    .padding(.bottom, LX.Space.s200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            inputBar
        }
        .background { Rectangle().fill(.lx(.background)).ignoresSafeArea() }
        .onAppear { if startListening { Task { await speech.start() } } }
        .onDisappear { speech.cancel(); session.cancel() }
        .onChange(of: speech.phase) { _, phase in
            if case .finished(let heard) = phase { session.send(heard) }
        }
        .lxAnimation(.smooth, value: session.messages.count)
        .lxAnimation(.smooth, value: session.pendingCardIndex)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: LX.Space.s200) {
            LXIconButton(systemImage: "xmark", label: "Close", glass: false) { dismiss() }
            Spacer()
            if let chip = session.contextChip {
                Button { session.contextChip = nil } label: {
                    LXChip(title: chip, systemImage: "eye", kind: .neutral, trailing: "✕")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(chip). Remove context")
            } else {
                Text("Ask LifeOS").lxFont(.title3).foregroundStyle(.lx(.textPrimary))
            }
            Spacer()
            Color.clear.frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
        }
        .padding(.horizontal, LX.Space.s300)
        .padding(.top, LX.Space.s200)
    }

    // MARK: Conversation

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LX.Space.s500) {
                    if session.messages.isEmpty { emptyState }
                    ForEach(session.messages) { m in
                        messageView(m).id(m.id)
                    }
                    if case .thinking(let step) = session.phase {
                        HStack(spacing: LX.Space.s300) {
                            AssistantOrb(phase: .thinking, size: 28)
                            Text(step ?? "").lxFont(.subhead).foregroundStyle(.lx(.textSecondary)).contentTransition(.opacity)
                        }
                        .id("thinking")
                        .accessibilityLabel(step ?? "Thinking")
                    }
                }
                .padding(LX.Space.s400)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: session.messages.last?.text) { _, _ in
                withAnimation { proxy.scrollTo(session.messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: session.phase) { _, p in
                if case .thinking = p { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: LX.Space.s400) {
            AssistantOrb(phase: speech.phase == .listening ? .listening : .idle, level: speech.level, size: 120)
                .padding(.top, LX.Space.s700)
            Text(speech.phase == .listening ? (speech.transcript.isEmpty ? "Listening…" : speech.transcript) : "Ask about your day, your meals or your training.")
                .lxFont(.callout).foregroundStyle(.lx(.textSecondary)).multilineTextAlignment(.center)
            Text("Answers come from your data on this iPhone.")
                .lxFont(.caption).foregroundStyle(.lx(.textTertiary))
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private func messageView(_ m: AssistantSession.Message) -> some View {
        switch m.role {
        case .user:
            HStack {
                Spacer(minLength: LX.Space.s800)
                Text(m.text).lxFont(.body).foregroundStyle(.lx(.textPrimary))
                    .padding(.horizontal, LX.Space.s400).padding(.vertical, LX.Space.s300)
                    .background(RoundedRectangle(cornerRadius: LX.Radius.tile, style: .continuous).fill(.lx(.surfaceRaised)))
            }
        case .assistant:
            VStack(alignment: .leading, spacing: LX.Space.s300) {
                if m.reply?.isSafetyRedirect == true {
                    Label("Outside what I can advise on", systemImage: "heart.text.square").lxFont(.footnote, weight: .semibold)
                        .foregroundStyle(.lx(.statusInfo))
                }
                Text(m.text).lxFont(.body).foregroundStyle(.lx(.textPrimary))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(m.isComplete ? m.text : "")
                if m.isComplete {
                    if session.pendingCardIndex.map({ session.messages[$0].id }) != m.id {
                        card(for: m, pinned: false)
                    }
                    provenance(m)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .onChange(of: m.isComplete) { _, done in
                if done { AccessibilityNotification.Announcement(m.text).post() } // VoiceOver hears the full answer once
            }
        }
    }

    private func provenance(_ m: AssistantSession.Message) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: LX.Space.s200) {
                LXSourceBadge(source: m.source.contains("Gemini") ? .gemini : m.source.contains("Groq") ? .groq : .onDevice)
                if let based = m.reply?.basedOn {
                    Text("Based on \(based.prefix(1).lowercased() + based.dropFirst())").lxFont(.caption).foregroundStyle(.lx(.textTertiary))
                }
            }
            if let used = m.reply?.usedMemories, !used.isEmpty {
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(used) { Text("• \($0.text)").lxFont(.caption).foregroundStyle(.lx(.textSecondary)) }
                    }
                    .padding(.top, 4)
                } label: {
                    Text("Used \(used.count) thing\(used.count == 1 ? "" : "s") I know about you").lxFont(.caption, weight: .medium)
                        .foregroundStyle(.lx(.accentPrimary))
                }
                .tint(theme.color(.accentPrimary))
            }
        }
    }

    // MARK: Cards

    @ViewBuilder private func card(for m: AssistantSession.Message, pinned: Bool) -> some View {
        switch m.reply?.card ?? .none {
        case .none:
            EmptyView()
        case let .chart(title, points, goal, unit):
            ChartCard(title: title, points: points, goal: goal, unit: unit)
        case let .list(title, rows):
            ListCard(title: title, rows: rows, canLog: store.isToday) { row in
                Task { await proposeAndLog(row.logText ?? row.title) }
            }
        case .logProposal(let sentence):
            if !m.settled {
                InlineProposal(store: store, sentence: sentence,
                               onLog: { ids, kcal, protein in session.settle(m.id); onLogged(ids, kcal, protein) },
                               onEdit: { session.settle(m.id); onEditInCapture(sentence) },
                               onCancel: { session.settle(m.id) })
            }
        case .rule(let rule):
            RuleCard(rule: rule, wouldHaveRun: intelligence.backtest(rule), settled: m.settled,
                     onTurnOn: { intelligence.upsert(rule); session.settle(m.id) },
                     onEdit: { session.settle(m.id); onEditRule(rule) },
                     onCancel: { session.settle(m.id) })
        case .remembered(let item):
            HStack(spacing: LX.Space.s200) {
                LXChip(title: m.undone ? "Not remembered" : "Remembered", systemImage: m.undone ? "arrow.uturn.backward" : "brain",
                       kind: .status(m.undone ? .textTertiary : .statusOnTrack))
                if !m.undone {
                    Button("Undo") { session.undoRemember(m.id) }.buttonStyle(.plain)
                        .lxFont(.subhead, weight: .semibold).foregroundStyle(.lx(.accentPrimary))
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(m.undone ? "Not remembered" : "Remembered: \(item.text)")
        case .forgotten(let items):
            if !m.settled {
                VStack(alignment: .leading, spacing: LX.Space.s300) {
                    ForEach(items) { Text("• \($0.text)").lxFont(.subhead).foregroundStyle(.lx(.textPrimary)) }
                    HStack {
                        Button("Keep") { session.settle(m.id) }.buttonStyle(.lx(.secondary))
                        Button("Forget") { intelligence.forget(items.map(\.id)); session.settle(m.id) }.buttonStyle(.lx(.destructive))
                    }
                }
                .lxCard(padding: LX.Space.s400)
            }
        }
    }

    private func proposeAndLog(_ text: String) async {
        let p = await CaptureEngine.propose(text, source: .preset, defaultSlot: store.currentSlot, userFoods: store.userNutrients)
        guard !p.items.isEmpty else { return }
        let foods = p.items.map { FoodItem($0, slot: p.slot) }
        let ids = store.log(foods, slot: p.slot, source: .preset)
        onLogged(ids, foods.reduce(0) { $0 + $1.calories }, foods.reduce(0) { $0 + $1.protein })
    }

    // MARK: Input bar

    private var inputBar: some View {
        VStack(spacing: LX.Space.s200) {
            if session.phase == .idle && session.pendingCardIndex == nil, let snap = intelligence.latest ?? intelligence.snapshot() {
                ScrollView(.horizontal) {
                    HStack(spacing: LX.Space.s200) {
                        ForEach(AssistantBrain.suggestions(snap, screen: session.contextChip), id: \.self) { s in
                            Button { session.send(s) } label: { LXChip(title: s, kind: .suggestion) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, LX.Space.s400)
                }
                .scrollIndicators(.hidden)
            }
            HStack(spacing: LX.Space.s200) {
                Button {
                    if speech.phase == .listening { speech.finish() } else { typing = false; Task { await speech.start() } }
                } label: {
                    AssistantOrb(phase: orbPhase, level: speech.level, size: 32)
                        .frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(speech.phase == .listening ? "Stop listening" : "Speak")
                TextField(speech.phase == .listening ? (speech.transcript.isEmpty ? "Listening…" : speech.transcript) : "Ask anything about your day",
                          text: $input, axis: .vertical)
                    .lxFont(.body).lineLimit(1...4).focused($typing).submitLabel(.send)
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                        .foregroundStyle(input.trimmingCharacters(in: .whitespaces).isEmpty ? .lx(.textTertiary) : .lx(.accentPrimary))
                }
                .buttonStyle(.plain)
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || session.phase != .idle)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, LX.Space.s300).padding(.vertical, LX.Space.s200)
            .lxGlass(in: RoundedRectangle(cornerRadius: LX.Radius.sheet, style: .continuous))
            .padding(.horizontal, LX.Space.s300)
            if case .denied = speech.phase {
                Text("Microphone or speech is off for LifeOS. Type instead, or allow it in Settings.")
                    .lxFont(.caption).foregroundStyle(.lx(.textSecondary))
            }
        }
        .padding(.bottom, LX.Space.s200)
    }

    private var orbPhase: AssistantOrb.Phase {
        if speech.phase == .listening { return .listening }
        switch session.phase {
        case .thinking: return .thinking
        case .streaming: return .speaking
        case .idle: return .idle
        }
    }

    private func send() {
        let t = input
        input = ""
        session.send(t)
    }
}

// MARK: - Response cards

private struct ChartCard: View {
    let title: String
    let points: [AssistantReply.ChartPoint]
    let goal: Double?
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s200) {
            Text(title).lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.textSecondary))
            Chart {
                ForEach(points) { p in
                    BarMark(x: .value("Day", p.date, unit: .day), y: .value(unit, p.value))
                        .foregroundStyle(.lx(.dataEnergy))
                        .cornerRadius(3)
                }
                if let goal {
                    RuleMark(y: .value("Target", goal))
                        .foregroundStyle(.lx(.textSecondary))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Target \(Int(goal)) \(unit)").lxFont(.caption).foregroundStyle(.lx(.textSecondary))
                        }
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day, count: points.count > 8 ? 3 : 1)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .frame(height: 120)
        }
        .lxCard(padding: LX.Space.s400)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title). " + points.suffix(7).map { "\($0.date.formatted(.dateTime.weekday(.wide))): \(Int($0.value)) \(unit)" }.joined(separator: ", "))
    }
}

private struct ListCard: View {
    let title: String
    let rows: [AssistantReply.Row]
    let canLog: Bool
    let onLog: (AssistantReply.Row) -> Void
    @State private var logged: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.textSecondary)).padding(.bottom, LX.Space.s200)
            ForEach(rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                        Text("\(row.detail) · \(row.kcal) kcal").lxFont(.footnote, numeric: true).foregroundStyle(.lx(.textSecondary))
                    }
                    Spacer()
                    if row.logText != nil && canLog {
                        Button(logged.contains(row.id) ? "Logged" : "Log") {
                            logged.insert(row.id)
                            onLog(row)
                        }
                        .buttonStyle(.lx(.secondary))
                        .disabled(logged.contains(row.id))
                    }
                }
                .padding(.vertical, LX.Space.s200)
            }
        }
        .lxCard(padding: LX.Space.s400)
    }
}

/// "Log 2 eggs and toast as breakfast?" — the Phase 3 proposal card, inline.
private struct InlineProposal: View {
    @ObservedObject var store: ExperienceStore
    let sentence: String
    var onLog: (_ ids: [UUID], _ kcal: Double, _ protein: Double) -> Void
    var onEdit: () -> Void
    var onCancel: () -> Void
    @State private var proposal: CaptureProposal?

    var body: some View {
        Group {
            if let p = proposal, !p.items.isEmpty {
                VStack(spacing: LX.Space.s200) {
                    LXProposalCard(mealTitle: p.slot.title, time: Date().formatted(date: .omitted, time: .shortened),
                                   source: .onDevice,
                                   items: p.items.map { LXProposalItem(id: $0.id, name: $0.name, amount: $0.amountText, kcal: Int($0.nutrient.kcal), confidence: $0.confidence.lx) },
                                   macros: [], note: p.unresolvedCount > 0 ? "Check the \(p.items.first { $0.confidence == .low }!.name.lowercased())." : nil,
                                   onLog: {
                                       let foods = p.items.map { FoodItem($0, slot: p.slot) }
                                       let ids = store.log(foods, slot: p.slot, source: .voice)
                                       onLog(ids, foods.reduce(0) { $0 + $1.calories }, foods.reduce(0) { $0 + $1.protein })
                                   },
                                   onEdit: onEdit)
                    Button("Cancel", action: onCancel).buttonStyle(.lx(.plain))
                }
            } else if proposal != nil {
                LXInlineBanner(kind: .attention, message: "I couldn't find food in “\(sentence)”.", actionTitle: "Type it", action: onEdit, onDismiss: onCancel)
            } else {
                HStack(spacing: LX.Space.s300) { ProgressView(); Text("Working out the portions…").lxFont(.footnote).foregroundStyle(.lx(.textSecondary)) }
            }
        }
        .task(id: sentence) {
            proposal = await CaptureEngine.propose(sentence, source: .voice, defaultSlot: store.currentSlot, userFoods: store.userNutrients)
        }
    }
}

/// Rule preview card (Phase 4 §4.4) with "how it would have run".
struct RuleCard: View {
    let rule: AutomationRule
    let wouldHaveRun: Int
    var settled = false
    var onTurnOn: () -> Void
    var onEdit: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            Label(rule.name, systemImage: "bolt.badge.clock").lxFont(.headline).foregroundStyle(.lx(.textPrimary))
            Text(AutomationText.sentence(rule)).lxFont(.body).foregroundStyle(.lx(.textPrimary))
            Text(rule.trigger.isScheduled
                 ? "Last week this would have run \(wouldHaveRun) time\(wouldHaveRun == 1 ? "" : "s"). Quiet hours and the daily limit still apply."
                 : "Runs while LifeOS is open, right after you log.")
                .lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
            if settled {
                Text("Done").lxFont(.subhead, weight: .semibold).foregroundStyle(.lx(.statusOnTrack))
            } else {
                HStack(spacing: LX.Space.s300) {
                    Button("Cancel", action: onCancel).buttonStyle(.lx(.plain))
                    Button("Edit", action: onEdit).buttonStyle(.lx(.secondary))
                    Button(action: onTurnOn) { Text("Turn on").frame(maxWidth: .infinity) }.buttonStyle(.lx(.primary))
                }
            }
        }
        .lxCard(padding: LX.Space.s400)
    }
}
