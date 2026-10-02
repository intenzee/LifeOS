import Foundation

/// The canonical day bucket for every user record: a Gregorian calendar date
/// (`yyyy-MM-dd`) in the user's time zone **at the moment the record was written**.
///
/// Rules (see docs/engineering-roadmap/01-platform-foundation.md §4.2):
/// - A key is stamped once, at write time, with `DayKey.make(for:timeZone:)`.
///   It is never re-derived later, so travelling Delhi → London never moves or
///   duplicates a day.
/// - Keys are always Gregorian, even when the device uses another calendar
///   (Buddhist, Japanese, …). Otherwise "2569-10-03" and "2026-10-03" could both
///   exist for the same day.
/// - Arithmetic (`adding(days:)`, `days(to:)`) is pure calendar-date arithmetic.
///   It does not depend on time zones or DST.
public struct DayKey: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    /// Creates a key from components. Returns `nil` for impossible dates (e.g. Feb 30).
    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let comps = DateComponents(year: year, month: month, day: day)
        guard let date = Self.utcCalendar.date(from: comps) else { return nil }
        let back = Self.utcCalendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == year, back.month == month, back.day == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses a strict `yyyy-MM-dd` string (ASCII digits only).
    public init?(_ string: String) {
        let parts = string.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy { $0.isASCII && $0.isNumber } }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        self.init(year: y, month: m, day: d)
    }

    /// The day `date` falls on in `timeZone` (defaults to the device's current zone).
    public static func make(for date: Date, timeZone: TimeZone = .current) -> DayKey {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        // Components from a real Date are always present and valid.
        return DayKey(unchecked: c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// 1970-01-01. A placeholder for malformed legacy data, never a real record day.
    public static let epoch = DayKey(unchecked: 1970, 1, 1)

    /// Today in the current time zone.
    public static func today(now: Date = Date(), timeZone: TimeZone = .current) -> DayKey {
        make(for: now, timeZone: timeZone)
    }

    /// `yyyy-MM-dd`.
    public var rawValue: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// `yyyy-MM`, used to shard storage by month.
    public var monthKey: String {
        String(format: "%04d-%02d", year, month)
    }

    public var description: String { rawValue }

    /// Midnight at the start of this day in `timeZone`.
    public func startDate(timeZone: TimeZone = .current) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        // A valid Gregorian date always resolves. The fallback is unreachable.
        return calendar.date(from: DateComponents(year: year, month: month, day: day))
            ?? calendar.startOfDay(for: utcMidnight)
    }

    /// Start of the following day in `timeZone`. `start..<end` covers this day,
    /// including 23- and 25-hour DST days.
    public func endDate(timeZone: TimeZone = .current) -> Date {
        adding(days: 1).startDate(timeZone: timeZone)
    }

    public func adding(days: Int) -> DayKey {
        let date = Self.utcCalendar.date(byAdding: .day, value: days, to: utcMidnight)
            ?? utcMidnight.addingTimeInterval(Double(days) * 86_400)
        return DayKey.make(for: date, timeZone: Self.utc)
    }

    /// Whole days from `self` to `other` (positive when `other` is later).
    public func days(to other: DayKey) -> Int {
        Self.utcCalendar.dateComponents([.day], from: utcMidnight, to: other.utcMidnight).day
            ?? Int((other.utcMidnight.timeIntervalSince(utcMidnight) / 86_400).rounded())
    }

    /// ISO weekday of this date.
    public var weekday: Weekday {
        Weekday(rawValue: Self.utcCalendar.component(.weekday, from: utcMidnight)) ?? .sunday
    }

    /// The first day of the week containing `self`.
    public func startOfWeek(firstWeekday: Weekday = .monday) -> DayKey {
        let offset = (weekday.rawValue - firstWeekday.rawValue + 7) % 7
        return adding(days: -offset)
    }

    /// Every key from `start` through `end`, inclusive. Empty when `end < start`.
    public static func range(from start: DayKey, through end: DayKey) -> [DayKey] {
        guard start <= end else { return [] }
        return (0...start.days(to: end)).map { start.adding(days: $0) }
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    // MARK: - Private

    private init(unchecked year: Int, _ month: Int, _ day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    private static let utc = TimeZone(secondsFromGMT: 0) ?? .gmt

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar
    }()

    private var utcMidnight: Date {
        // UTC has no DST gaps, so a valid date always resolves.
        Self.utcCalendar.date(from: DateComponents(year: year, month: month, day: day))
            ?? Date(timeIntervalSince1970: 0)
    }
}

extension DayKey: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let key = DayKey(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid DayKey '\(raw)'")
        }
        self = key
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Gregorian weekday numbers, matching `Calendar.component(.weekday)` (1 = Sunday).
public enum Weekday: Int, CaseIterable, Sendable, Codable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday
}
