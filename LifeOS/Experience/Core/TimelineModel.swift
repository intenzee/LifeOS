import Foundation

/// One row of the Today timeline (Phase 3 §3.1 item 6): meals, workouts, water
/// and weight in time order, newest first, each with its source.
nonisolated struct ExperienceTimelineEntry: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: String, Sendable { case meal, workout, water, weight }
    nonisolated enum Source: String, Sendable { case manual, barcode, photo, voice, preset, watch, health }

    let id: String
    var kind: Kind
    var title: String
    var detail: String
    /// Signed kcal effect on the budget: food positive, workouts negative (earned). nil = none.
    var kcal: Int?
    /// nil for day-level summaries (water count, gym sets) that have no clock time.
    var time: Date?
    var source: Source

    /// Timed rows newest first, then untimed day summaries in kind order.
    static func ordered(_ entries: [ExperienceTimelineEntry]) -> [ExperienceTimelineEntry] {
        let timed = entries.filter { $0.time != nil }.sorted { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }
        let rank: [Kind: Int] = [.workout: 0, .meal: 1, .water: 2, .weight: 3]
        let untimed = entries.filter { $0.time == nil }.sorted { (rank[$0.kind] ?? 9, $0.id) < (rank[$1.kind] ?? 9, $1.id) }
        return timed + untimed
    }
}

/// The "Next up" line (Phase 3 §3.1 item 4): one sentence and one action, or nothing.
nonisolated struct ExperienceNextUp: Equatable, Sendable {
    nonisolated enum Action: Equatable, Sendable {
        case capture
        case logPreset(id: String)
        case addWater
    }
    var message: String
    var actionTitle: String
    var action: Action

    /// Rules, most useful first. Returns nil when there is nothing worth saying.
    static func make(hasLoggedToday: Bool,
                     slot: ExperienceMealSlot,
                     slotIsLogged: Bool,
                     topPreset: ExperiencePresetCandidate?,
                     waterGlasses: Int,
                     waterTarget: Int,
                     hour: Int) -> ExperienceNextUp? {
        if !hasLoggedToday {
            return ExperienceNextUp(message: "Log your first meal: just say it.", actionTitle: "Capture", action: .capture)
        }
        if !slotIsLogged, let p = topPreset {
            return ExperienceNextUp(message: "\(slot.title) not logged yet. Usual: \(p.nutrient.name), \(Int(p.nutrient.kcal)) kcal.",
                                    actionTitle: "Log it", action: .logPreset(id: p.id))
        }
        if !slotIsLogged {
            return ExperienceNextUp(message: "\(slot.title) not logged yet.", actionTitle: "Capture", action: .capture)
        }
        // Water is "behind" when below the pro-rata target for the waking day (8 am–10 pm).
        if waterTarget > 0 {
            let progress = min(max(Double(hour - 8) / 14, 0), 1)
            let expected = Int((Double(waterTarget) * progress).rounded(.down))
            if waterGlasses < expected {
                return ExperienceNextUp(message: "\(waterGlasses) of \(waterTarget) glasses so far. A glass now keeps you on pace.",
                                        actionTitle: "+1 glass", action: .addWater)
            }
        }
        return nil
    }
}
