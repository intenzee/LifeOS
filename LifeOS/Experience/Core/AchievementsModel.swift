import Foundation

// UI/UX Phase 5 §6: a small, meaningful set of medals. No points, no levels.

nonisolated enum Medal: String, CaseIterable, Codable, Identifiable, Sendable {
    case firstWeek, month, century, ritual, synced, balance

    var id: String { rawValue }

    var title: String {
        switch self {
        case .firstWeek: return "First week"
        case .month: return "Month"
        case .century: return "Century"
        case .ritual: return "Ritual"
        case .synced: return "Synced"
        case .balance: return "Balance"
        }
    }

    var criterion: String {
        switch self {
        case .firstWeek: return "7 perfect days in a row"
        case .month: return "A 30-day perfect streak"
        case .century: return "A 100-day perfect streak"
        case .ritual: return "One usual meal logged 20 times"
        case .synced: return "50 training sessions in LifeOS"
        case .balance: return "4 weeks in a row within 5% of budget"
        }
    }

    /// Engraved symbol (SF Symbols).
    var symbol: String {
        switch self {
        case .firstWeek: return "7.circle"
        case .month: return "calendar"
        case .century: return "100.circle"
        case .ritual: return "fork.knife"
        case .synced: return "applewatch"
        case .balance: return "scale.3d"
        }
    }

    var target: Int {
        switch self {
        case .firstWeek: return 7
        case .month: return 30
        case .century: return 100
        case .ritual: return 20
        case .synced: return 50
        case .balance: return 4
        }
    }
}

nonisolated struct AchievementInputs: Sendable {
    /// Days that were perfect (all four goals), any order.
    var perfectDays: [Date]
    /// Highest number of times any single usual meal has been logged.
    var topPresetUses: Int
    var topPresetName: String?
    /// Training sessions logged in LifeOS (iPhone or Watch).
    var trainingSessions: Int
    /// Mondays-first weeks, oldest first: average eaten and budget over logged days.
    var weeks: [Week]

    struct Week: Sendable, Equatable {
        var start: Date
        var avgEaten: Double
        var avgBudget: Double
        var loggedDays: Int
    }
}

nonisolated struct MedalProgress: Equatable, Sendable {
    var medal: Medal
    var current: Int
    var earned: Bool
    /// When the threshold was reached, if the data says so.
    var reachedOn: Date?

    var text: String {
        if earned { return "Earned" }
        switch medal {
        case .firstWeek, .month, .century: return "Best run so far: \(current) of \(medal.target) days"
        case .ritual: return "\(current) of \(medal.target) times"
        case .synced: return "\(current) of \(medal.target) sessions"
        case .balance: return "\(current) of \(medal.target) weeks"
        }
    }
}

nonisolated enum Achievements {
    /// Longest run of consecutive perfect days, and the day each length was first reached.
    static func perfectRuns(_ days: [Date], calendar: Calendar) -> (longest: Int, reached: [Int: Date]) {
        let sorted = Set(days.map { calendar.startOfDay(for: $0) }).sorted()
        var longest = 0, run = 0
        var previous: Date?
        var reached: [Int: Date] = [:]
        for d in sorted {
            if let p = previous, calendar.date(byAdding: .day, value: 1, to: p) == d { run += 1 } else { run = 1 }
            previous = d
            longest = max(longest, run)
            if reached[run] == nil { reached[run] = d }
        }
        return (longest, reached)
    }

    static func withinBalance(_ w: AchievementInputs.Week) -> Bool {
        w.loggedDays >= 4 && w.avgBudget > 0 && abs(w.avgEaten / w.avgBudget - 1) <= 0.05
    }

    /// Longest run of consecutive balanced weeks, and the week it reached 4.
    static func balanceRun(_ weeks: [AchievementInputs.Week], calendar: Calendar) -> (longest: Int, reachedOn: Date?) {
        var longest = 0, run = 0
        var reachedOn: Date?
        var previous: Date?
        for w in weeks.sorted(by: { $0.start < $1.start }) {
            let consecutive = previous.flatMap { calendar.date(byAdding: .day, value: 7, to: $0) } == w.start
            run = withinBalance(w) ? (consecutive ? run + 1 : 1) : 0
            previous = w.start
            longest = max(longest, run)
            if run == Medal.balance.target, reachedOn == nil {
                reachedOn = calendar.date(byAdding: .day, value: 6, to: w.start)
            }
        }
        return (longest, reachedOn)
    }

    static func progress(_ i: AchievementInputs, calendar: Calendar = .current) -> [MedalProgress] {
        let runs = perfectRuns(i.perfectDays, calendar: calendar)
        let balance = balanceRun(i.weeks, calendar: calendar)
        return Medal.allCases.map { m in
            switch m {
            case .firstWeek, .month, .century:
                return MedalProgress(medal: m, current: min(runs.longest, m.target), earned: runs.longest >= m.target, reachedOn: runs.reached[m.target])
            case .ritual:
                return MedalProgress(medal: m, current: min(i.topPresetUses, m.target), earned: i.topPresetUses >= m.target, reachedOn: nil)
            case .synced:
                return MedalProgress(medal: m, current: min(i.trainingSessions, m.target), earned: i.trainingSessions >= m.target, reachedOn: nil)
            case .balance:
                return MedalProgress(medal: m, current: min(balance.longest, m.target), earned: balance.longest >= m.target, reachedOn: balance.reachedOn)
            }
        }
    }

    /// Medals to celebrate now. On the very first check (`known == nil`) only the
    /// most recent one is celebrated, so turning the feature on isn't a parade.
    static func newlyEarned(_ progress: [MedalProgress], known: Set<Medal>?) -> [Medal] {
        let earned = progress.filter(\.earned)
        guard let known else {
            let latest = earned.max { ($0.reachedOn ?? .distantPast) < ($1.reachedOn ?? .distantPast) }
            return latest.map { [$0.medal] } ?? []
        }
        return earned.map(\.medal).filter { !known.contains($0) }
    }
}
