import Foundation

/// When the user usually starts training, as minutes after local midnight
/// (WCH-15). The Watch's "Start workout" Smart Stack card is relevant inside it.
public struct TrainingWindow: Codable, Sendable, Equatable {
    public var startMinute: Int
    public var endMinute: Int
    /// Sessions the window was learned from.
    public var sessions: Int

    public init(startMinute: Int, endMinute: Int, sessions: Int) {
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.sessions = sessions
    }

    public static let minSessions = 4
    /// Wider than this and there's no habit to point at.
    public static let maxWidthMinutes = 240
    static let margin = 30

    /// From workout start times (the last few weeks). Walks are left out: they
    /// happen at any hour and would smear the window.
    ///
    /// The window runs from 30 min before the 25th percentile to 30 min after the
    /// 75th, so a usual 6:30–7:15 pm start gives 6:00–7:45 pm. `nil` with fewer
    /// than four sessions, or when the starts are too spread out.
    public static func learn(from sessions: [WorkoutSession], timeZone: TimeZone = .current) -> TrainingWindow? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let minutes = sessions.filter { $0.kind != .walk }.map { session -> Int in
            let parts = calendar.dateComponents([.hour, .minute], from: session.start)
            return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        }.sorted()
        guard minutes.count >= minSessions else { return nil }

        let start = max(percentile(minutes, 0.25) - margin, 0)
        let end = min(percentile(minutes, 0.75) + margin, 24 * 60 - 1)
        guard end - start <= maxWidthMinutes else { return nil }
        return TrainingWindow(startMinute: start, endMinute: end, sessions: minutes.count)
    }

    /// The window on `day`, as dates.
    public func interval(on day: DayKey, timeZone: TimeZone = .current) -> DateInterval {
        let midnight = day.startDate(timeZone: timeZone)
        return DateInterval(start: midnight.addingTimeInterval(Double(startMinute) * 60),
                            end: midnight.addingTimeInterval(Double(endMinute) * 60))
    }

    /// Nearest-rank percentile of sorted values.
    private static func percentile(_ sorted: [Int], _ fraction: Double) -> Int {
        let rank = Int((fraction * Double(sorted.count - 1)).rounded())
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }
}
