import Foundation

/// When this user actually eats each meal, learned from their own log (F05
/// `MealWindowSlice`, F02 meal-type inference, FOOD-16).
///
/// Fixed clock hours mislabel anyone who eats late (lunch at 15:30, dinner at
/// 23:00) or early. With ≥ 3 logs of a meal in the last weeks, its window is the
/// interquartile range of the logged times, and a new entry takes the meal
/// whose window it falls in (nearest median when several do).
nonisolated struct MealWindows: Sendable, Equatable {
    nonisolated struct Window: Sendable, Equatable {
        var slot: ParsedMeal.MealSlot
        /// Minutes after midnight.
        var median: Int
        var start: Int
        var end: Int
        var count: Int
    }

    var windows: [ParsedMeal.MealSlot: Window]

    static let minimumSamples = 3
    /// How far outside its interquartile range a time may be and still count.
    static let slack = 60

    static let empty = MealWindows(windows: [:])

    static func learn(_ meals: [(slot: ParsedMeal.MealSlot, time: Date)], calendar: Calendar = .current) -> MealWindows {
        var out: [ParsedMeal.MealSlot: Window] = [:]
        let grouped = Dictionary(grouping: meals.filter { $0.slot != .unknown }, by: \.slot)
        for (slot, entries) in grouped {
            // One sample per meal occasion: several items logged together count once.
            var seen = Set<String>()
            let minutes = entries.compactMap { entry -> Int? in
                let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: entry.time)
                let key = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)-\(slot.rawValue)"
                guard seen.insert(key).inserted else { return nil }
                return (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }.sorted()
            guard minutes.count >= minimumSamples else { continue }
            func quantile(_ q: Double) -> Int { minutes[min(minutes.count - 1, Int((Double(minutes.count - 1) * q).rounded()))] }
            out[slot] = Window(slot: slot, median: quantile(0.5), start: quantile(0.25), end: quantile(0.75), count: minutes.count)
        }
        return MealWindows(windows: out)
    }

    var isEmpty: Bool { windows.isEmpty }

    /// The meal a log at `date` most likely belongs to, or nil when no learned
    /// window covers it (callers fall back to fixed hours).
    func slot(at date: Date, calendar: Calendar = .current) -> ParsedMeal.MealSlot? {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let t = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        let covering = windows.values.filter { t >= $0.start - Self.slack && t <= $0.end + Self.slack }
        if let best = covering.min(by: { abs($0.median - t) < abs($1.median - t) }) { return best.slot }
        // Between two learned main meals with no window here → a snack.
        let mains = windows.values.filter { $0.slot != .snacks }.map(\.median).sorted()
        if mains.count >= 2, let first = mains.first, let last = mains.last, t > first, t < last { return .snacks }
        return nil
    }

    /// "usual lunch 13:30–14:30" lines for the context packet.
    var summaryLines: [String] {
        [ParsedMeal.MealSlot.breakfast, .lunch, .snacks, .dinner].compactMap { slot in
            windows[slot].map { "usual \(slot.rawValue) \(Self.hhmm($0.start))–\(Self.hhmm($0.end))" }
        }
    }

    static func hhmm(_ minutes: Int) -> String { String(format: "%02d:%02d", minutes / 60 % 24, minutes % 60) }
}
