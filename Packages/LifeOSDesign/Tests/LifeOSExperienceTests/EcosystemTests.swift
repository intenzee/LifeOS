import Foundation
import Testing
@testable import LifeOSExperienceCore

private enum Fx {
    static var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        return c
    }()
    static func date(_ d: Int, _ h: Int = 12, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: d, hour: h, minute: m))!
    }

    static func archive() -> BackupArchive {
        BackupArchive(createdAt: date(3, 8, 2), appVersion: "1.0",
                      summary: .init(meals: 1204, workoutDays: 40, weights: 30, memories: 6, automations: 3, firstDay: "2026-01-01", lastDay: "2026-10-03"),
                      files: ["LifeOSStore/v1/food/2026-10.json": Data("[1,2]".utf8), "LifeOS/Experience/memories.json": Data("[]".utf8)],
                      defaults: Data([1, 2, 3]))
    }
}

@Suite struct BackupTests {
    @Test func archiveRoundTrips() throws {
        let a = Fx.archive()
        let back = try BackupArchive.decode(a.encoded())
        #expect(back == a)
    }

    @Test func rejectsOtherFilesAndNewerVersions() throws {
        #expect(throws: BackupArchive.ReadError.notABackup) { try BackupArchive.decode(Data(#"{"hello":1}"#.utf8)) }
        var newer = Fx.archive()
        newer.version = 99
        #expect(throws: BackupArchive.ReadError.newerVersion(99)) { try BackupArchive.decode(newer.encoded()) }
    }

    @Test func previewLineMatchesPlan() {
        // Day/month order follows the device locale ("3 Oct" in en_IN, "Oct 3" in en_US).
        let line = Fx.archive().previewLine()
        #expect(line.hasPrefix("This backup is from "))
        #expect(line.hasSuffix(" with 1,204 meals"))
    }

    @Test func policyKeepsDataAndSkipsCachesAndSecrets() {
        #expect(BackupPolicy.includes("LifeOSStore/v1/food/2026-10.json"))
        #expect(BackupPolicy.includes("meal_corrections.json"))
        #expect(!BackupPolicy.includes("AI/quota.json"))
        #expect(!BackupPolicy.includes("LifeOSStore/.DS_Store"))
        #expect(BackupPolicy.includesDefault("calorieLimit"))
        #expect(!BackupPolicy.includesDefault("lx.backup.last"))
        #expect(!BackupPolicy.includesDefault("AppleLanguages"))
    }

    @Test func autoBackupOncePerDayAfterMidnight() {
        #expect(BackupPolicy.autoBackupDue(last: nil, now: Fx.date(3), calendar: Fx.cal))
        #expect(!BackupPolicy.autoBackupDue(last: Fx.date(3, 0, 5), now: Fx.date(3, 23), calendar: Fx.cal))
        #expect(BackupPolicy.autoBackupDue(last: Fx.date(2, 23, 59), now: Fx.date(3, 0, 1), calendar: Fx.cal))
    }

    @Test func pruneKeepsNewestSeven() {
        let files = (1...10).map { (name: "b\($0)", date: Fx.date($0)) }
        #expect(Set(BackupPolicy.toPrune(files)) == ["b1", "b2", "b3"])
        #expect(BackupPolicy.toPrune(Array(files.prefix(5))).isEmpty)
    }

    @Test func lastBackupLine() {
        let line = BackupPolicy.lastBackupLine(date: Fx.date(3, 8, 2), bytes: 1_400_000, now: Fx.date(3, 20), calendar: Fx.cal)
        #expect(line.hasPrefix("Last backup: today, "))
        #expect(line.contains("MB"))
        #expect(BackupPolicy.lastBackupLine(date: nil, bytes: nil) == "No backup yet")
    }

    @Test func csvEscapes() {
        #expect(CSV.field("Dal, rice") == "\"Dal, rice\"")
        #expect(CSV.field("5\" pizza") == "\"5\"\" pizza\"")
        #expect(CSV.number(.nan) == "")
        #expect(CSV.document(header: ["a", "b"], rows: [["1", "x,y"]]) == "a,b\r\n1,\"x,y\"\r\n")
    }
}

@Suite struct RefreshReminderTests {
    @Test func readsExpiryFromProfileEnvelope() {
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>ExpirationDate</key><date>2026-10-09T19:42:32Z</date></dict></plist>
        """
        var data = Data([0x30, 0x82, 0x01, 0x00]) // CMS bytes before the plist
        data.append(Data(plist.utf8))
        data.append(Data([0x00, 0xA0]))
        let expiry = RefreshReminder.expirationDate(fromProvisioningProfile: data)
        #expect(expiry == ISO8601DateFormatter().date(from: "2026-10-09T19:42:32Z"))
        #expect(RefreshReminder.expirationDate(fromProvisioningProfile: Data("nothing".utf8)) == nil)
    }

    @Test func stagesFollowPlan() {
        let expiry = Fx.date(9, 19, 42)
        #expect(RefreshReminder.stage(expiry: expiry, now: Fx.date(3), calendar: Fx.cal) == .none)
        #expect(RefreshReminder.stage(expiry: expiry, now: Fx.date(7), calendar: Fx.cal) == .soon(daysLeft: 2))
        #expect(RefreshReminder.stage(expiry: expiry, now: Fx.date(8), calendar: Fx.cal) == .soon(daysLeft: 1))
        #expect(RefreshReminder.stage(expiry: expiry, now: Fx.date(9, 8), calendar: Fx.cal) == .lastDay)
        #expect(RefreshReminder.stage(expiry: expiry, now: Fx.date(10), calendar: Fx.cal) == .none)
        #expect(RefreshReminder.stage(expiry: nil, now: Fx.date(9), calendar: Fx.cal) == .none)
    }

    @Test func messageAndNotificationTime() {
        let expiry = Fx.date(9, 19, 42)
        #expect(RefreshReminder.message(expiry: expiry, now: Fx.date(8), calendar: Fx.cal) == "LifeOS needs a refresh from Xcode by tomorrow. Your data is safe.")
        #expect(RefreshReminder.message(expiry: expiry, now: Fx.date(7), calendar: Fx.cal).hasSuffix("Your data is safe."))
        #expect(RefreshReminder.notificationDate(expiry: expiry, now: Fx.date(3), calendar: Fx.cal) == Fx.date(7, 9))
        let late = RefreshReminder.notificationDate(expiry: expiry, now: Fx.date(8, 10), calendar: Fx.cal)!
        #expect(late > Fx.date(8, 10) && late < Fx.date(8, 10, 2))
    }
}

@Suite struct AchievementTests {
    private func days(_ range: ClosedRange<Int>, month: Int = 9) -> [Date] {
        range.map { Fx.cal.date(from: DateComponents(year: 2026, month: month, day: $0))! }
    }
    private func week(_ startDay: Int, eaten: Double, budget: Double = 2000, logged: Int = 7) -> AchievementInputs.Week {
        .init(start: Fx.cal.date(from: DateComponents(year: 2026, month: 8, day: startDay))!, avgEaten: eaten, avgBudget: budget, loggedDays: logged)
    }

    @Test func perfectRunsFindTheLongestAndWhenItWasReached() {
        let d = days(1...3) + days(10...17) // 3, then 8 in a row
        let r = Achievements.perfectRuns(d.shuffled(), calendar: Fx.cal)
        #expect(r.longest == 8)
        #expect(r.reached[7] == days(16...16)[0])
    }

    @Test func streakMedalsAndProgressText() {
        let i = AchievementInputs(perfectDays: days(10...17), topPresetUses: 12, topPresetName: "Poha", trainingSessions: 50, weeks: [])
        let p = Dictionary(uniqueKeysWithValues: Achievements.progress(i, calendar: Fx.cal).map { ($0.medal, $0) })
        #expect(p[.firstWeek]!.earned)
        #expect(!p[.month]!.earned && p[.month]!.text == "Best run so far: 8 of 30 days")
        #expect(p[.ritual]!.text == "12 of 20 times")
        #expect(p[.synced]!.earned)
    }

    @Test func balanceNeedsFourConsecutiveWeeksWithin5Percent() {
        let ok = [week(3, eaten: 1950), week(10, eaten: 2080), week(17, eaten: 2000), week(24, eaten: 1910)]
        #expect(Achievements.balanceRun(ok, calendar: Fx.cal).longest == 4)
        var broken = ok
        broken[2] = week(17, eaten: 2300) // 15% over
        #expect(Achievements.balanceRun(broken, calendar: Fx.cal).longest == 2)
        var thin = ok
        thin[1] = week(10, eaten: 2000, logged: 2) // not enough logged days
        #expect(Achievements.balanceRun(thin, calendar: Fx.cal).longest == 2)
        let gap = [week(3, eaten: 2000), week(17, eaten: 2000)] // not consecutive
        #expect(Achievements.balanceRun(gap, calendar: Fx.cal).longest == 1)
    }

    @Test func firstCheckCelebratesOnlyTheLatest() {
        let i = AchievementInputs(perfectDays: days(1...8), topPresetUses: 25, topPresetName: nil, trainingSessions: 0, weeks: [])
        let p = Achievements.progress(i, calendar: Fx.cal)
        #expect(Achievements.newlyEarned(p, known: nil).count == 1)
        #expect(Achievements.newlyEarned(p, known: [.firstWeek]) == [.ritual])
        #expect(Achievements.newlyEarned(p, known: [.firstWeek, .ritual]).isEmpty)
    }
}
