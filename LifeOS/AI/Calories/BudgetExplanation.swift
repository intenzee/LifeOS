import Foundation

/// "Why is my target 2,230 today?" (F08 §7, AI-244).
///
/// Every number comes from the calorie engine's breakdown (CAL-07), read-only;
/// this type only names and orders them. A model may rephrase the template,
/// but `BudgetExplainer` rejects any phrasing that introduces a number not
/// present here.
nonisolated struct BudgetExplanation: Sendable, Equatable {
    nonisolated struct Line: Sendable, Equatable {
        var kind: LifeContext.BudgetLine.Kind
        var label: String
        var kcal: Double
        var note: String

        var signedText: String {
            let sign = kcal < 0 ? "−" : (kind == .bmr || kind == .manualTarget ? "" : "+")
            return "\(sign)\(Num.kcal(abs(kcal)))" + (note.isEmpty ? "" : " (\(note))")
        }
    }

    var total: Double
    var lines: [Line]
    var credit: Double
    var mode: String
    var workouts: [LifeContext.Workout]

    static func make(_ context: LifeContext) -> BudgetExplanation {
        let b = context.budget ?? LifeContext.Budget(total: context.today?.budget ?? 0)
        let workouts = context.today?.workouts ?? []
        let eatBack = Int((b.eatBack * 100).rounded())
        let lines = b.lines.map { line -> Line in
            switch line.kind {
            case .bmr:
                return Line(kind: .bmr, label: "Resting burn", kcal: line.kcal, note: "BMR, Mifflin-St Jeor")
            case .everydayActivity:
                return Line(kind: .everydayActivity, label: "Everyday activity", kcal: line.kcal,
                            note: b.mode == "measured" || b.mode == "estimated" ? "sedentary baseline" : "your activity level")
            case .goal:
                let note = line.kcal < 0 ? "to lose weight" : line.kcal > 0 ? "to gain weight" : "maintain"
                return Line(kind: .goal, label: "Goal", kcal: line.kcal, note: note)
            case .manualTarget:
                return Line(kind: .manualTarget, label: "Your set target", kcal: line.kcal, note: "")
            case .floorTopUp:
                return Line(kind: .floorTopUp, label: "Safe minimum", kcal: line.kcal,
                            note: "never below \(Num.kcal(b.floor)) before exercise")
            case .exerciseCredit:
                let source: String
                if b.mode == "measured" {
                    source = "\(eatBack)% of \(Num.kcal(max(0, b.rawActive - b.allowance))) kcal active energy above your everyday \(Num.kcal(b.allowance))"
                } else {
                    source = "\(eatBack)% of \(Num.kcal(b.rawActive)) kcal from logged workouts"
                }
                let detail = workouts.isEmpty ? "" : "; " + workouts.map(Self.describe).joined(separator: ", ")
                return Line(kind: .exerciseCredit, label: "Earned from activity", kcal: line.kcal, note: source + detail)
            }
        }
        return BudgetExplanation(total: b.total, lines: lines, credit: b.credit, mode: b.mode, workouts: workouts)
    }

    static func describe(_ w: LifeContext.Workout) -> String {
        "\(w.name) \(w.minutes) min, \(w.source), \(Num.kcal(w.kcal)) kcal"
    }

    /// The deterministic answer (also the fallback for any model phrasing).
    var sentence: String {
        guard total > 0 else { return "Your budget isn't set up yet. Add your profile in Settings and I'll show the breakdown." }
        let base = total - credit
        var s: String
        if credit >= 1 {
            s = "Your target is \(Num.kcal(total)) kcal today: \(Num.kcal(base)) base plus \(Num.kcal(credit)) earned from activity"
            if let w = workouts.max(by: { $0.kcal < $1.kcal }) {
                s += workouts.count == 1 ? " (your \(w.minutes)-min \(w.name.lowercased()), \(w.source))" : " (\(workouts.count) workouts, the biggest your \(w.minutes)-min \(w.name.lowercased()))"
            }
            s += "."
        } else if mode == "measured" && !workouts.isEmpty {
            s = "Your target is \(Num.kcal(total)) kcal. Today's activity is still within the everyday allowance already in your base, so nothing extra yet."
        } else if mode == "fixed" || mode == "classic" && lines.contains(where: { $0.kind == .manualTarget }) {
            s = "Your target is a fixed \(Num.kcal(total)) kcal; exercise doesn't change it in this mode."
        } else {
            s = "Your target is \(Num.kcal(total)) kcal, with nothing earned from activity yet today."
        }
        if let floor = lines.first(where: { $0.kind == .floorTopUp }) {
            s += " It includes \(Num.kcal(floor.kcal)) kcal to keep you above the safe minimum."
        }
        return s
    }

    /// Multi-line breakdown (F08 §7 format).
    var breakdownText: String {
        var out = lines.map { "\($0.label) \($0.signedText)" }
        out.append("= \(Num.kcal(total)) today")
        return out.joined(separator: "\n")
    }

    /// Every number the explanation may mention (grounding).
    var allowedNumbers: [Double] {
        var n = [total, credit, total - credit] + lines.map { abs($0.kcal) }
        for w in workouts { n += [w.kcal, Double(w.minutes)] }
        return n
    }
}

/// Phrases the breakdown with a model when one is reachable; otherwise, or when
/// the phrasing fails the numbers check, returns the template (AI-244).
nonisolated struct BudgetExplainer: Sendable {
    let gateway: any AIGatewaying

    func explain(_ context: LifeContext) async -> (text: String, provider: ProviderID) {
        let explanation = BudgetExplanation.make(context)
        guard explanation.total > 0, await gateway.availability(for: .budgetExplain).isAvailable else {
            return (explanation.sentence, .deterministic)
        }
        let prompt = AIPrompt(id: "budget.explain", version: PromptRegistry.version, instructions: """
            You explain a person's calorie target for today in at most two short, calm sentences.
            Use only the numbers in the breakdown, exactly as written; do not compute new numbers.
            No advice, no judgement, no emojis.
            """, user: "Breakdown (data):\n\(explanation.breakdownText)")
        let request = AIRequest<AIText>(task: .budgetExplain, prompt: prompt, input: .text(explanation.breakdownText),
                                        privacy: .health, latencyBudget: .seconds(6), cachePolicy: .bypass)
        guard let result = try? await gateway.run(request) else { return (explanation.sentence, .deterministic) }
        let check = GroundingValidator.validate(result.output.text, allowed: explanation.allowedNumbers)
        return check.isGrounded ? (result.output.text, result.provider) : (explanation.sentence, .deterministic)
    }
}

/// "+180 kcal added from your 42-min run · 46 g protein to go" (F07 §6, AI-307).
nonisolated struct PostWorkoutCard: Sendable, Equatable {
    var title: String
    var body: String

    /// `creditBefore` is the exercise credit the app last saw today (nil = unknown).
    static func make(workout: LifeContext.Workout, creditBefore: Double?, context: LifeContext) -> PostWorkoutCard {
        let credit = context.budget?.credit ?? 0
        let added = creditBefore.map { credit - $0 } ?? credit
        let what = "\(workout.minutes)-min \(workout.name.lowercased())"
        var body: String
        if added >= 5 {
            body = "+\(Num.kcal(added)) kcal added to today's budget from your \(what)."
        } else if context.budget?.mode == "fixed" || context.budget?.mode == "classic" && credit == 0 {
            body = "Your \(what) is logged (\(Num.kcal(workout.kcal)) kcal). Your target is fixed, so the budget stays the same."
        } else {
            body = "Your \(what) is logged (\(Num.kcal(workout.kcal)) kcal). It's within the everyday activity already in your base, so the budget is unchanged."
        }
        if let target = context.macroTargets?.protein, target > 0 {
            let left = target - (context.today?.protein ?? 0)
            body += left >= 5 ? " \(Int(left.rounded())) g protein to go." : " Protein target reached."
        }
        return PostWorkoutCard(title: "\(workout.name) synced", body: body)
    }
}

/// Wording for the adaptive-TDEE estimate engineering computes (CAL-11).
/// Speaks only when the estimate is `ok` and the gap is meaningful.
nonisolated enum MaintenanceSuggestion {
    static func text(status: String, differenceKcal: Double?, windowDays: Int, weighIns: Int) -> String? {
        guard status == "ok", let diff = differenceKcal, abs(diff) >= 100 else { return nil }
        let rounded = Int((abs(diff) / 50).rounded() * 50)
        return "Your real maintenance looks about \(rounded) kcal \(diff > 0 ? "higher" : "lower") than estimated, based on \(windowDays) days of logs and \(weighIns) weigh-ins. Update your target?"
    }
}
