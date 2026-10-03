import Foundation

// Engine v2 inputs (doc 03 §4.1): a smoothed weight trend and an observed
// expenditure from intake vs. that trend. Pure and suggestion-only: nothing here
// changes a budget. CAL-12 decides when (and how fast) a budget adopts it.

/// Exponentially smoothed weight (CAL-10), so day-to-day water swings don't read
/// as fat gained or lost.
public enum TrendWeight {
    public struct Point: Sendable, Equatable {
        public let day: DayKey
        public let trendKg: Double
        /// The day's reading, when there was one.
        public let rawKg: Double?

        public init(day: DayKey, trendKg: Double, rawKg: Double?) {
            self.day = day
            self.trendKg = trendKg
            self.rawKg = rawKg
        }
    }

    /// The trend for every day in `from...through`, starting at the first reading.
    /// Readings before `from` warm the trend up. Several readings on one day count
    /// as the latest one. A gap of `g` days applies `1 − (1 − alpha)^g` to the next
    /// reading, as if the weight had stayed put in between; days without a reading
    /// carry the trend over.
    public static func series(_ entries: [WeightEntry], from: DayKey, through: DayKey,
                              alpha: Double = 0.1) -> [Point] {
        guard from <= through else { return [] }
        let readings = dailyReadings(entries.filter { $0.dayKey <= through && $0.kg > 0 })
        guard let first = readings.first else { return [] }

        var points: [Point] = []
        var trend = first.kg
        var lastDay = first.day
        var next = 0
        for day in DayKey.range(from: min(first.day, from), through: through) {
            var raw: Double?
            if next < readings.count, readings[next].day == day {
                raw = readings[next].kg
                if day != first.day {
                    let gap = Double(lastDay.days(to: day))
                    trend += (1 - pow(1 - alpha, gap)) * (readings[next].kg - trend)
                }
                lastDay = day
                next += 1
            }
            if day >= from, day >= first.day {
                points.append(Point(day: day, trendKg: trend, rawKg: raw))
            }
        }
        return points
    }

    private static func dailyReadings(_ entries: [WeightEntry]) -> [(day: DayKey, kg: Double)] {
        Dictionary(grouping: entries, by: \.dayKey)
            .compactMap { day, entries in entries.max { $0.measuredAt < $1.measuredAt }.map { (day, $0.kg) } }
            .sorted { $0.day < $1.day }
    }
}

/// What the adaptive estimator concluded (CAL-11).
public struct TDEEEstimate: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        /// Enough data: `observedKcal` is set and blended in.
        case estimated
        /// Fewer than 14 qualifying days, or under 80% of the window.
        case notEnoughLoggedDays
        /// Fewer than 8 weigh-ins in the window.
        case notEnoughWeighIns
        /// The weigh-ins span under 14 days, so the trend can't show a rate yet.
        case tooFewDays
        /// The observed figure is outside 1,000–6,000 kcal: almost certainly
        /// a logging or scale problem, not a metabolism.
        case implausible
    }

    public let status: Status
    /// `mean(intake) − Δtrend × 7700 / days`. `nil` unless `status == .estimated`.
    public let observedKcal: Double?
    public let formulaKcal: Double
    /// `w × observed + (1 − w) × formula`. The formula alone unless `status == .estimated`.
    public let blendedKcal: Double
    /// `w`, from 0 to 0.8 with data quality.
    public let weight: Double
    public let windowDays: Int
    public let qualifyingDays: Int
    public let weighIns: Int
    /// Trend change across the window, negative when losing.
    public let trendDeltaKg: Double?

    /// How far the observed expenditure is from the formula's.
    public var differenceKcal: Double? { observedKcal.map { $0 - formulaKcal } }
}

public enum AdaptiveTDEE {
    public static let kcalPerKg = 7700.0
    public static let maxWeight = 0.8
    static let minQualifyingDays = 14
    static let minCoverage = 0.8
    static let minWeighIns = 8
    static let minWeighInSpan = 14
    static let qualifyingShare = 0.6
    static let plausible = 1000.0...6000.0

    /// - Parameters:
    ///   - intakeKcal: logged kcal per day.
    ///   - budgetKcal: each day's budget (`EnergyDay.budgetKcal`). A day qualifies
    ///     when its intake is at least 60% of it, or of `formulaKcal` without one.
    ///   - weights: every reading available; earlier ones warm up the trend.
    ///   - formulaKcal: today's formula TDEE, which the estimate blends with.
    ///   - windowDays: 21–28, ending on `through`.
    public static func estimate(intakeKcal: [DayKey: Double], budgetKcal: [DayKey: Double],
                                weights: [WeightEntry], formulaKcal: Double, through: DayKey,
                                windowDays: Int = 28) -> TDEEEstimate {
        let window = min(max(windowDays, 21), 28)
        let start = through.adding(days: -(window - 1))
        let days = DayKey.range(from: start, through: through)

        let qualifying = days.compactMap { day -> Double? in
            guard let intake = intakeKcal[day], intake > 0 else { return nil }
            let reference = budgetKcal[day] ?? formulaKcal
            return intake >= qualifyingShare * reference ? intake : nil
        }
        let weighInDays = Set(weights.filter { $0.dayKey >= start && $0.dayKey <= through && $0.kg > 0 }.map(\.dayKey))
        let coverage = Double(qualifying.count) / Double(window)

        func result(_ status: TDEEEstimate.Status, observed: Double? = nil, weight blend: Double = 0,
                    delta: Double? = nil) -> TDEEEstimate {
            TDEEEstimate(status: status, observedKcal: observed, formulaKcal: formulaKcal,
                         blendedKcal: observed.map { blend * $0 + (1 - blend) * formulaKcal } ?? formulaKcal,
                         weight: observed == nil ? 0 : blend, windowDays: window, qualifyingDays: qualifying.count,
                         weighIns: weighInDays.count, trendDeltaKg: delta)
        }

        guard qualifying.count >= minQualifyingDays, coverage >= minCoverage else {
            return result(.notEnoughLoggedDays)
        }
        guard weighInDays.count >= minWeighIns else { return result(.notEnoughWeighIns) }
        guard let firstWeighIn = weighInDays.min(), let lastWeighIn = weighInDays.max(),
              firstWeighIn.days(to: lastWeighIn) >= minWeighInSpan else {
            return result(.tooFewDays)
        }

        // The trend from the window's first day (or the first reading ever, if
        // that's later) to its last.
        let trend = TrendWeight.series(weights, from: start, through: through)
        guard let first = trend.first, let last = trend.last, first.day.days(to: last.day) >= minWeighInSpan else {
            return result(.tooFewDays)
        }
        let delta = last.trendKg - first.trendKg
        let span = Double(first.day.days(to: last.day))
        let meanIntake = qualifying.reduce(0, +) / Double(qualifying.count)
        let observed = meanIntake - delta * kcalPerKg / span
        guard plausible.contains(observed) else { return result(.implausible, delta: delta) }

        // Weighing every other day counts as full density.
        let density = min(Double(weighInDays.count) / (Double(window) * 0.5), 1)
        let blend = maxWeight * min(coverage, 1) * density
        return result(.estimated, observed: observed, weight: blend, delta: delta)
    }
}
