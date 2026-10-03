import Combine
import Foundation
import LifeOSData

/// Phase 5 §6: works out medal progress from the streak history and the store,
/// remembers when each medal was earned, and raises one earning moment at a time.
@MainActor
final class AchievementStore: ObservableObject {
    static let shared = AchievementStore()

    @Published private(set) var progress: [MedalProgress] = Medal.allCases.map { MedalProgress(medal: $0, current: 0, earned: false, reachedOn: nil) }
    @Published private(set) var earnedOn: [Medal: Date] = [:]
    @Published private(set) var topPresetName: String?
    /// The medal whose earning moment should show now.
    @Published var celebrating: Medal?

    private var queue: [Medal] = []
    private var running = false
    private let key = "lx.medals.earned"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let stored = try? JSONDecoder().decode([String: Date].self, from: data) {
            earnedOn = Dictionary(uniqueKeysWithValues: stored.compactMap { k, v in Medal(rawValue: k).map { ($0, v) } })
        }
    }

    /// Reads every record once; call on appear and when the app becomes active, not on every change.
    func refresh(streaks: StreakManager? = nil, food: FoodDatabaseManager? = nil) {
        guard !running, LocalStore.shared.phase == .ready else { return }
        let streaks = streaks ?? .shared
        let food = food ?? .shared
        running = true
        Task {
            defer { running = false }
            guard let snapshot = try? await LocalStore.shared.database.loadAll() else { return }
            let inputs = Self.inputs(summaries: Array(streaks.summaries.values), snapshot: snapshot,
                                     usualNames: Set((food.favoriteFoods + food.customFoods).map { $0.name.lowercased() }))
            topPresetName = inputs.topPresetName
            let next = Achievements.progress(inputs)
            progress = next
            let known: Set<Medal>? = UserDefaults.standard.data(forKey: key) == nil ? nil : Set(earnedOn.keys)
            let fresh = Achievements.newlyEarned(next, known: known)
            for p in next where p.earned && earnedOn[p.medal] == nil {
                earnedOn[p.medal] = p.reachedOn ?? Date()
            }
            save()
            queue.append(contentsOf: fresh.filter { !queue.contains($0) })
            showNext()
        }
    }

    /// Call when an earning moment is dismissed.
    func didCelebrate() {
        celebrating = nil
        showNext()
    }

    private func showNext() {
        guard celebrating == nil, !queue.isEmpty else { return }
        celebrating = queue.removeFirst()
    }

    private func save() {
        let raw = Dictionary(uniqueKeysWithValues: earnedOn.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(raw) { UserDefaults.standard.set(data, forKey: key) }
    }

    static func inputs(summaries: [DailySummary], snapshot: DataSnapshot, usualNames: Set<String>, now: Date = Date(),
                       calendar: Calendar = .current) -> AchievementInputs {
        let perfect = summaries.filter(\.isPerfectDay).map { $0.dayKey.startDate() }

        // Ritual: the usual meal logged most often.
        var counts: [String: (name: String, n: Int)] = [:]
        for f in snapshot.food where usualNames.contains(f.name.lowercased()) {
            let k = f.name.lowercased()
            counts[k] = (counts[k]?.name ?? f.name, (counts[k]?.n ?? 0) + 1)
        }
        let top = counts.values.max { $0.n < $1.n }

        let sessions = snapshot.workouts.filter { $0.totalSets > 0 || $0.treadmillDone }.count

        // Balance: complete Monday weeks only (the current one isn't over yet).
        var mondayCal = calendar
        mondayCal.firstWeekday = 2
        let thisWeek = mondayCal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        var byWeek: [Date: [DailySummary]] = [:]
        for s in summaries where s.caloriesConsumed > 0 && s.calorieLimit > 0 {
            guard let start = mondayCal.dateInterval(of: .weekOfYear, for: s.dayKey.startDate())?.start, start < thisWeek else { continue }
            byWeek[start, default: []].append(s)
        }
        let weeks = byWeek.map { start, days in
            AchievementInputs.Week(start: start,
                                   avgEaten: days.map(\.caloriesConsumed).reduce(0, +) / Double(days.count),
                                   avgBudget: days.map(\.calorieLimit).reduce(0, +) / Double(days.count),
                                   loggedDays: days.count)
        }.sorted { $0.start < $1.start }

        return AchievementInputs(perfectDays: perfect, topPresetUses: top?.n ?? 0, topPresetName: top?.name,
                                 trainingSessions: sessions, weeks: weeks)
    }
}
