import AppIntents
import SwiftUI

// Phase 5 §5: the six top intents for Siri and Shortcuts, each with a small
// snippet view. They run in the app's process through `IntentRuntime`.
// Personal automations in the Shortcuts app ("When I arrive at the gym…") use these too.

// MARK: - Preset entity

struct PresetEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Usual meal"
    static let defaultQuery = PresetQuery()

    var id: String
    var name: String
    var kcal: Double
    var protein: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(Fmt.kcal(kcal)) kcal · \(Fmt.grams(protein)) protein")
    }

    init(_ c: ExperiencePresetCandidate) {
        id = c.id
        name = c.nutrient.name
        kcal = c.nutrient.kcal
        protein = c.nutrient.protein
    }
}

struct PresetQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [PresetEntity] {
        let store = await IntentRuntime.store()
        return store.presets(limit: 500).filter { identifiers.contains($0.id) }.map(PresetEntity.init)
    }

    /// The ones that fit this time of day first, same ranking as Capture.
    @MainActor
    func suggestedEntities() async throws -> [PresetEntity] {
        let store = await IntentRuntime.store()
        return store.presets(for: store.currentSlot, limit: 8).map(PresetEntity.init)
    }
}

// MARK: - Intents

struct RemainingCaloriesIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories left today"
    static let description = IntentDescription("How many calories you have left today, including what you've earned from activity.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let b = await IntentRuntime.store().budget
        let sentence = IntentRuntime.remainingSentence(b)
        return .result(dialog: IntentDialog(stringLiteral: sentence), view: RemainingSnippet(budget: b))
    }
}

struct LogPresetIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a usual meal"
    static let description = IntentDescription("Logs one of your usual meals to today.")

    @Parameter(title: "Meal") var preset: PresetEntity

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$preset)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let p = preset
        guard try await $preset.requestConfirmation(for: p, dialog: "Log \(p.name), \(Fmt.kcal(p.kcal)) kcal?") else {
            throw IntentError.message("Okay, nothing logged.")
        }
        let store = await IntentRuntime.store()
        guard store.logPreset(id: p.id) != nil else {
            throw IntentError.message("That meal isn't in LifeOS any more. Open the app to pick another.")
        }
        let left = IntentRuntime.remainingSentence(store.budget)
        return .result(dialog: "Logged \(p.name). \(left)", view: PresetSnippet(preset: p, logged: true, budget: store.budget))
    }
}

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Add water"
    static let description = IntentDescription("Adds glasses of water to today.")

    @Parameter(title: "Glasses", default: 1, inclusiveRange: (1, 6)) var glasses: Int

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = await IntentRuntime.store()
        store.addWater(glasses)
        let n = store.waterCount
        return .result(dialog: "That's \(n) of \(store.waterTarget) glasses today.",
                       view: WaterSnippet(count: n, target: store.waterTarget))
    }
}

struct LogWeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Log weight"
    static let description = IntentDescription("Logs today's weight in kilograms.")

    @Parameter(title: "Weight (kg)", inclusiveRange: (20, 400)) var kg: Double

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = await IntentRuntime.store()
        let before = PersistenceManager.shared.loadWeightHistory().last { !Calendar.current.isDateInToday($0.date) }
        store.logWeight(kg: kg)
        let delta = before.map { kg - $0.weightKg }
        var line = String(format: "Logged %.1f kg", kg)
        if let delta, abs(delta) >= 0.05 { line += String(format: ", %@%.1f since %@", delta > 0 ? "+" : "−", abs(delta), Fmt.shortDay(before!.date, .current)) }
        return .result(dialog: IntentDialog(stringLiteral: line + "."), view: WeightSnippet(kg: kg, delta: delta))
    }
}

struct AskLifeOSIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask LifeOS"
    static let description = IntentDescription("Answers questions about your food, training, water and weight from your own data, on this iPhone.")

    @Parameter(title: "Question", requestValueDialog: "What would you like to know?") var question: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        _ = await IntentRuntime.store()
        guard let snap = IntelligenceStore.shared.snapshot() else {
            throw IntentError.message("LifeOS couldn't read your data just now. Open the app and try again.")
        }
        let reply = AssistantBrain.reply(to: question, snap)
        var text = reply.text
        switch reply.card {
        case .logProposal, .rule, .remembered, .forgotten:
            text += " Open LifeOS to confirm."
        default:
            break
        }
        if reply.needsModel { text = "I can answer that in the LifeOS app. Here I can tell you about calories, protein, water, workouts and weight." }
        return .result(dialog: IntentDialog(stringLiteral: text), view: AskSnippet(reply: reply, text: text))
    }
}

struct StartGymSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Start gym session"
    static let description = IntentDescription("Opens LifeOS on Training, ready to log today's sets.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let store = await IntentRuntime.store()
        IntelligenceStore.shared.pendingRoute = .training
        let done = store.dayWorkout.totalSets
        return .result(dialog: done > 0 ? "Opening Training. \(done) sets logged so far today." : "Opening Training. Have a good session.",
                       view: GymSnippet(setsToday: done, exercises: store.dayWorkout.exercises.map(\.displayName)))
    }
}

enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case message(String)
    var localizedStringResource: LocalizedStringResource {
        switch self { case .message(let m): return "\(m)" }
    }
}

// MARK: - Shortcuts

struct LifeOSShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .teal }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RemainingCaloriesIntent(), phrases: [
            "How many calories do I have left in \(.applicationName)",
            "Calories left in \(.applicationName)",
        ], shortTitle: "Calories left", systemImageName: "flame")
        AppShortcut(intent: LogPresetIntent(), phrases: [
            "Log my usual in \(.applicationName)",
            "Log \(\.$preset) in \(.applicationName)",
        ], shortTitle: "Log usual meal", systemImageName: "fork.knife")
        AppShortcut(intent: LogWaterIntent(), phrases: [
            "Add a glass of water in \(.applicationName)",
            "Log water in \(.applicationName)",
        ], shortTitle: "Add water", systemImageName: "drop.fill")
        AppShortcut(intent: LogWeightIntent(), phrases: [
            "Log my weight in \(.applicationName)",
        ], shortTitle: "Log weight", systemImageName: "scalemass")
        AppShortcut(intent: AskLifeOSIntent(), phrases: [
            "Ask \(.applicationName)",
            "Ask \(.applicationName) a question",
        ], shortTitle: "Ask LifeOS", systemImageName: "sparkles")
        AppShortcut(intent: StartGymSessionIntent(), phrases: [
            "Start my workout in \(.applicationName)",
            "Start a gym session in \(.applicationName)",
        ], shortTitle: "Start gym session", systemImageName: "figure.strengthtraining.traditional")
    }
}

// MARK: - Snippet views (no 3D, no animation: they render outside the app)

private struct SnippetRing: View {
    let fill: Double
    let over: Bool
    var body: some View {
        ZStack {
            Circle().stroke(.lx(.separator), lineWidth: 7)
            Circle().trim(from: 0, to: min(max(fill, 0), 1))
                .stroke(over ? AnyShapeStyle(.lx(.statusOver)) : AnyShapeStyle(.lx(.dataEnergy)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }
}

struct RemainingSnippet: View {
    let budget: ExperienceBudget
    var body: some View {
        HStack(spacing: 16) {
            SnippetRing(fill: budget.fill, over: budget.isOver)
            VStack(alignment: .leading, spacing: 2) {
                Text(budget.isOver ? "\(Fmt.kcal(-budget.remaining)) over" : "\(Fmt.kcal(budget.remaining)) left")
                    .font(.title2.weight(.semibold)).monospacedDigit()
                Text("\(Fmt.kcal(budget.eaten)) eaten of \(Fmt.kcal(budget.budget)) kcal" + (budget.earned >= 1 ? " · \(Fmt.kcal(budget.earned)) earned" : ""))
                    .font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

struct PresetSnippet: View {
    let preset: PresetEntity
    let logged: Bool
    let budget: ExperienceBudget
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: logged ? "checkmark.circle.fill" : "fork.knife").font(.title).foregroundStyle(.lx(.statusOnTrack))
            VStack(alignment: .leading, spacing: 2) {
                Text(preset.name).font(.headline)
                Text("\(Fmt.kcal(preset.kcal)) kcal · \(Fmt.grams(preset.protein)) protein").font(.subheadline).monospacedDigit()
                Text("\(Fmt.kcal(max(budget.remaining, 0))) kcal left today").font(.footnote).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer(minLength: 0)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

struct WaterSnippet: View {
    let count: Int
    let target: Int
    var body: some View {
        HStack(spacing: 16) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6).stroke(.lx(.dataWater), lineWidth: 2)
                RoundedRectangle(cornerRadius: 5).fill(.lx(.dataWater))
                    .frame(height: 50 * min(Double(count) / Double(max(target, 1)), 1))
                    .padding(3)
            }
            .frame(width: 36, height: 56)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(count) of \(target) glasses").font(.title3.weight(.semibold)).monospacedDigit()
                Text(count >= target ? "Water goal reached" : "\(target - count) to go").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

struct WeightSnippet: View {
    let kg: Double
    let delta: Double?
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "scalemass.fill").font(.title).foregroundStyle(.lx(.dataWeight))
            Text(String(format: "%.1f kg", kg)).font(.title2.weight(.semibold)).monospacedDigit()
            if let delta, abs(delta) >= 0.05 {
                Label(String(format: "%.1f", abs(delta)), systemImage: delta > 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    .accessibilityLabel(String(format: "%@ %.1f kilograms since last weigh-in", delta > 0 ? "Up" : "Down", abs(delta)))
            }
            Spacer(minLength: 0)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}

struct AskSnippet: View {
    let reply: AssistantReply
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if case .chart(let title, let points, let goal, _) = reply.card, !points.isEmpty {
                Text(title).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                MiniBars(values: points.suffix(7).map(\.value), goal: goal)
                    .frame(height: 56)
                    .accessibilityLabel(title)
            }
            if let based = reply.basedOn {
                Label(based, systemImage: "iphone").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

/// Swift Charts-free bars, so the snippet stays light.
private struct MiniBars: View {
    let values: [Double]
    let goal: Double?
    var body: some View {
        GeometryReader { geo in
            let top = max(values.max() ?? 1, goal ?? 0, 1)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(values.indices, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 3).fill(.lx(.dataProtein))
                        .frame(height: max(geo.size.height * values[i] / top, 2))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .bottom) {
                if let goal {
                    Rectangle().fill(.lx(.textSecondary)).frame(height: 1).offset(y: -geo.size.height * goal / top)
                }
            }
        }
    }
}

struct GymSnippet: View {
    let setsToday: Int
    let exercises: [String]
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "figure.strengthtraining.traditional").font(.title).foregroundStyle(.lx(.dataActivity))
            VStack(alignment: .leading, spacing: 2) {
                Text(setsToday > 0 ? "\(setsToday) sets today" : "New session").font(.headline).monospacedDigit()
                Text(exercises.isEmpty ? "Pick an exercise in Training" : exercises.prefix(3).joined(separator: " · "))
                    .font(.footnote).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding()
        .accessibilityElement(children: .combine)
    }
}
