import Foundation
import Testing
@testable import LifeOSCore

private func tz(_ id: String) -> TimeZone { TimeZone(identifier: id)! }

/// `yyyy-MM-ddTHH:mm` interpreted in `zone`.
private func date(_ string: String, _ zone: TimeZone) -> Date {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.timeZone = zone
    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
    return formatter.date(from: string)!
}

@Suite("DayKey")
struct DayKeyTests {
    @Test func parsesAndFormats() {
        let key = DayKey("2026-10-03")
        #expect(key?.year == 2026 && key?.month == 10 && key?.day == 3)
        #expect(key?.rawValue == "2026-10-03")
        #expect(key?.monthKey == "2026-10")
        #expect(DayKey(year: 2026, month: 1, day: 5)?.rawValue == "2026-01-05")
    }

    @Test(arguments: ["2026-02-30", "2026-13-01", "2026-1-01", "26-01-01", "2026/01/01", "", "2026-01-01x", "２０２６-01-01", "2025-02-29"])
    func rejectsInvalid(_ raw: String) {
        #expect(DayKey(raw) == nil)
    }

    @Test func acceptsLeapDay() {
        #expect(DayKey("2028-02-29") != nil)
    }

    @Test func midnightEdges() {
        let zone = tz("Asia/Kolkata")
        #expect(DayKey.make(for: date("2026-10-03T23:59", zone), timeZone: zone).rawValue == "2026-10-03")
        #expect(DayKey.make(for: date("2026-10-04T00:00", zone), timeZone: zone).rawValue == "2026-10-04")
    }

    @Test func sameInstantDiffersByTimeZone() {
        // 20:30 UTC is already the next day in Delhi.
        let instant = date("2026-10-03T20:30", tz("UTC"))
        #expect(DayKey.make(for: instant, timeZone: tz("UTC")).rawValue == "2026-10-03")
        #expect(DayKey.make(for: instant, timeZone: tz("Asia/Kolkata")).rawValue == "2026-10-04")
        #expect(DayKey.make(for: instant, timeZone: tz("America/Los_Angeles")).rawValue == "2026-10-03")
    }

    @Test func travelDoesNotRekeyStampedRecords() throws {
        // A key stamped in Delhi survives encoding and stays the same after "flying" to London.
        let stamped = DayKey.make(for: date("2026-10-03T23:30", tz("Asia/Kolkata")), timeZone: tz("Asia/Kolkata"))
        let data = try JSONEncoder().encode(stamped)
        let decoded = try JSONDecoder().decode(DayKey.self, from: data)
        #expect(decoded == stamped)
        #expect(String(data: data, encoding: .utf8) == "\"2026-10-03\"")
    }

    @Test func dstDaysHaveCorrectLength() {
        let ny = tz("America/New_York")
        // 2026-03-08: spring forward (23 h). 2026-11-01: fall back (25 h).
        let spring = DayKey("2026-03-08")!
        let fall = DayKey("2026-11-01")!
        #expect(spring.endDate(timeZone: ny).timeIntervalSince(spring.startDate(timeZone: ny)) == 23 * 3600)
        #expect(fall.endDate(timeZone: ny).timeIntervalSince(fall.startDate(timeZone: ny)) == 25 * 3600)
        // 01:30 on the fall-back day happens twice. Both belong to the same day.
        #expect(DayKey.make(for: date("2026-11-01T01:30", ny), timeZone: ny) == fall)
        // Arithmetic across DST is pure date maths.
        #expect(DayKey("2026-03-07")!.adding(days: 2).rawValue == "2026-03-09")
    }

    @Test func arithmetic() {
        let key = DayKey("2026-12-31")!
        #expect(key.adding(days: 1).rawValue == "2027-01-01")
        #expect(key.adding(days: -365).rawValue == "2025-12-31")
        #expect(DayKey("2028-02-28")!.adding(days: 1).rawValue == "2028-02-29")
        #expect(DayKey("2026-01-01")!.days(to: DayKey("2027-01-01")!) == 365)
        #expect(DayKey("2026-01-10")!.days(to: DayKey("2026-01-01")!) == -9)
    }

    @Test func ordering() {
        #expect(DayKey("2026-09-30")! < DayKey("2026-10-01")!)
        #expect(DayKey("2025-12-31")! < DayKey("2026-01-01")!)
        #expect([DayKey("2026-10-02")!, DayKey("2026-01-15")!].sorted().first?.rawValue == "2026-01-15")
    }

    @Test func weekdaysAndWeeks() {
        let saturday = DayKey("2026-10-03")!
        #expect(saturday.weekday == .saturday)
        #expect(saturday.startOfWeek(firstWeekday: .monday).rawValue == "2026-09-28")
        #expect(saturday.startOfWeek(firstWeekday: .sunday).rawValue == "2026-09-27")
        #expect(DayKey("2026-09-28")!.startOfWeek().rawValue == "2026-09-28")
        #expect(DayKey("2026-10-04")!.startOfWeek().rawValue == "2026-09-28") // Sunday ends the week
    }

    @Test func ranges() {
        let range = DayKey.range(from: DayKey("2026-02-27")!, through: DayKey("2026-03-02")!)
        #expect(range.map(\.rawValue) == ["2026-02-27", "2026-02-28", "2026-03-01", "2026-03-02"])
        #expect(DayKey.range(from: DayKey("2026-03-02")!, through: DayKey("2026-03-01")!).isEmpty)
    }

    @Test func alwaysGregorianRegardlessOfDeviceCalendar() {
        // `make` builds its own Gregorian calendar, so a Buddhist-calendar device
        // still gets 2026, not 2569.
        let instant = date("2026-10-03T12:00", tz("Asia/Bangkok"))
        #expect(DayKey.make(for: instant, timeZone: tz("Asia/Bangkok")).year == 2026)
    }

    @Test func decodingRejectsGarbage() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(DayKey.self, from: Data("\"10/03/2026\"".utf8))
        }
    }
}

@Suite("Legacy weekday names")
struct LegacyWeekdayNameTests {
    let saturday = DayKey("2026-10-03")!

    @Test func mapsEnglishNamesIntoMondayFirstWeek() {
        #expect(LegacyWeekdayName.dayKey(for: "Monday", inWeekOf: saturday)?.rawValue == "2026-09-28")
        #expect(LegacyWeekdayName.dayKey(for: "Saturday", inWeekOf: saturday)?.rawValue == "2026-10-03")
        #expect(LegacyWeekdayName.dayKey(for: "Sunday", inWeekOf: saturday)?.rawValue == "2026-10-04")
        #expect(LegacyWeekdayName.dayKey(for: "friday", inWeekOf: saturday)?.rawValue == "2026-10-02")
    }

    @Test func mapsLocalizedNames() {
        let german = [Locale(identifier: "en_US_POSIX"), Locale(identifier: "de_DE")]
        #expect(LegacyWeekdayName.dayKey(for: "Montag", inWeekOf: saturday, locales: german)?.rawValue == "2026-09-28")
        #expect(LegacyWeekdayName.dayKey(for: "Sonntag", inWeekOf: saturday, locales: german)?.rawValue == "2026-10-04")
    }

    @Test func unknownNameIsNil() {
        #expect(LegacyWeekdayName.dayKey(for: "Funday", inWeekOf: saturday,
                                         locales: [Locale(identifier: "en_US_POSIX")]) == nil)
    }
}
