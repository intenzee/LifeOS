import Foundation
import Testing
import LifeOSCore
@testable import LifeOSConnectivity

/// WCH-15: the training window, the snapshot's midnight reset and the timelines.
@Suite("Complications")
struct ComplicationTests {
    let tz = TimeZone(identifier: "Asia/Kolkata")!
    let day = DayKey("2026-10-03")!

    private func at(_ hour: Int, _ minute: Int = 0, on day: DayKey? = nil) -> Date {
        (day ?? self.day).startDate(timeZone: tz).addingTimeInterval(Double(hour * 3600 + minute * 60))
    }

    private func session(_ hour: Int, _ minute: Int = 0, kind: ActivityKind = .strength, daysAgo: Int = 0)
        -> WorkoutSession {
        let d = day.adding(days: -daysAgo)
        let start = at(hour, minute, on: d)
        return WorkoutSession(dayKey: d, start: start, end: start.addingTimeInterval(3600), kind: kind,
                              source: .healthKit)
    }

    private func snapshot(trained: Bool = false, active: Bool = false, updatedAt: Date? = nil,
                          window: TrainingWindow? = TrainingWindow(startMinute: 18 * 60, endMinute: 19 * 60 + 30,
                                                                   sessions: 6))
        -> ComplicationSnapshot {
        ComplicationSnapshot(day: day, budgetKcal: 2100, eatenKcal: 1460, earnedKcal: 200, proteinG: 96,
                             proteinTargetG: 120, waterGlasses: 5, waterTarget: 8, streak: 4, trainedToday: trained,
                             workoutActive: active, trainingWindow: window,
                             preset: .init(name: "Poha", kcal: 250), updatedAt: updatedAt ?? at(8))
    }

    // MARK: Training window

    @Test func learnsTheInterquartileStartsWithHalfHourMargins() throws {
        let sessions = [session(18, 30), session(18, 45, daysAgo: 2), session(19, 0, daysAgo: 4),
                        session(19, 15, daysAgo: 6), session(18, 30, daysAgo: 8),
                        session(7, 0, kind: .walk, daysAgo: 1)]       // walks don't count
        let window = try #require(TrainingWindow.learn(from: sessions, timeZone: tz))
        #expect(window.sessions == 5)
        #expect(window.startMinute == 18 * 60)                 // 18:30 − 30
        #expect(window.endMinute == 19 * 60 + 30)              // 19:00 + 30
        #expect(window.interval(on: day, timeZone: tz) == DateInterval(start: at(18), end: at(19, 30)))
    }

    @Test func noWindowWithoutAHabit() {
        #expect(TrainingWindow.learn(from: [session(18), session(18, daysAgo: 1), session(18, daysAgo: 2)],
                                     timeZone: tz) == nil)    // three sessions
        let scattered = [session(6), session(9, daysAgo: 1), session(13, daysAgo: 2), session(17, daysAgo: 3),
                         session(21, daysAgo: 4)]
        #expect(TrainingWindow.learn(from: scattered, timeZone: tz) == nil)
    }

    @Test func trainingWindowTravelsInTheWatchSnapshot() throws {
        var typed = WatchSnapshot.empty(day: day)
        typed.trainingWindow = TrainingWindow(startMinute: 1080, endMinute: 1170, sessions: 6)
        #expect(try WatchWire.decodeSnapshot(WatchWire.encode(typed)) == typed)
        // A snapshot from a phone without the field still decodes.
        let old = try JSONEncoder().encode(WatchSnapshot.empty(day: day))
        #expect(try JSONDecoder().decode(WatchSnapshot.self, from: old).trainingWindow == nil)
    }

    // MARK: Snapshot

    @Test func displayValuesComeStraightFromThePhone() {
        let s = snapshot()
        #expect(s.remainingKcal == 640)
        #expect(!s.isOver)
        #expect(abs(s.fill - 1460.0 / 2100) < 1e-9)
        var over = s
        over.eatenKcal = 2300
        #expect(over.isOver)
        #expect(over.fill == 1)
    }

    @Test func pastMidnightYesterdaysNumbersDontShow() {
        let s = snapshot(trained: true).forDisplay(at: at(0, 5, on: day.adding(days: 1)), timeZone: tz)
        #expect(s.day == day.adding(days: 1))
        #expect(s.eatenKcal == 0)
        #expect(s.budgetKcal == 1900)                 // yesterday's credit removed
        #expect(s.waterGlasses == 0)
        #expect(s.proteinG == 0)
        #expect(!s.trainedToday)
        #expect(s.preset == nil)
        #expect(s.streak == 4)
        #expect(snapshot().forDisplay(at: at(23), timeZone: tz) == snapshot())
    }

    @Test func storageRoundTrips() throws {
        let s = snapshot()
        #expect(ComplicationCoding.decode(try ComplicationCoding.encode(s)) == s)
        #expect(ComplicationCoding.decode(Data("nope".utf8)) == nil)
    }

    @Test func onlyVisibleChangesNeedAReload() {
        let s = snapshot(updatedAt: at(8))
        #expect(s.differsVisibly(from: nil, timeZone: tz))
        #expect(!snapshot(updatedAt: at(9)).differsVisibly(from: s, timeZone: tz))   // same slot
        #expect(snapshot(updatedAt: at(12)).differsVisibly(from: s, timeZone: tz))   // lunch now
        var drank = snapshot(updatedAt: at(9))
        drank.waterGlasses += 1
        #expect(drank.differsVisibly(from: s, timeZone: tz))
    }

    // MARK: Timeline

    @Test func timelineHasAnEntryAtEachChangeForADay() {
        let entries = ComplicationTimeline.entries(for: snapshot(), now: at(17, 10), timeZone: tz)
        let dates = entries.map(\.date)
        #expect(dates.first == at(17, 10))
        #expect(dates == dates.sorted())
        #expect(dates.contains(at(18)))                       // window opens
        #expect(dates.contains(at(19, 30)))                   // window closes
        #expect(dates.contains(at(0, on: day.adding(days: 1))))  // midnight reset
        #expect(dates.allSatisfy { $0 < at(17, 10).addingTimeInterval(24 * 3600) })
        let midnight = entries.first { $0.date == at(0, on: day.adding(days: 1)) }
        #expect(midnight?.snapshot?.eatenKcal == 0)
    }

    @Test func startWorkoutIsRelevantInsideTheWindowUntilTrained() {
        let entries = ComplicationTimeline.entries(for: snapshot(), now: at(17), timeZone: tz)
        let opening = entries.first { $0.date == at(18) }
        #expect(opening?.workoutRelevance == 1)
        #expect(abs((opening?.workoutRelevanceDuration ?? 0) - 90 * 60) < 0.001)
        #expect(entries.first { $0.date == at(17) }?.workoutRelevance == 0)
        #expect(entries.first { $0.date == at(19, 30) }?.workoutRelevance == 0)

        let trained = ComplicationTimeline.entries(for: snapshot(trained: true), now: at(17), timeZone: tz)
        #expect(trained.first { $0.date == at(18) }?.workoutRelevance == 0)
        // Training today doesn't hide tomorrow's window.
        #expect(trained.first { $0.date == at(18, on: day.adding(days: 1)) } == nil) // beyond 24 h from 17:00
        let lateTrained = ComplicationTimeline.entries(for: snapshot(trained: true), now: at(19, 45), timeZone: tz)
        #expect(lateTrained.first { $0.date == at(18, on: day.adding(days: 1)) }?.workoutRelevance == 1)

        let running = ComplicationTimeline.entries(for: snapshot(active: true), now: at(18, 10), timeZone: tz)
        #expect(running.first?.workoutRelevance == 0)
    }

    @Test func presetShowsOnlyInTheSlotItWasRankedFor() {
        let entries = ComplicationTimeline.entries(for: snapshot(updatedAt: at(8)), now: at(8, 30), timeZone: tz)
        #expect(entries.first?.showsPreset == true)                         // breakfast
        #expect(entries.first { $0.date == at(11) }?.showsPreset == false)  // lunch starts
        #expect(entries.first?.todayRelevance == 0.5)                       // 8:30 is a mealtime
        #expect(entries.first { $0.date == at(11) }?.todayRelevance == 0.1)
    }

    @Test func noSnapshotGivesEmptyEntries() {
        let entries = ComplicationTimeline.entries(for: nil, now: at(9), timeZone: tz)
        #expect(!entries.isEmpty)
        #expect(entries.allSatisfy { $0.snapshot == nil && $0.workoutRelevance == 0 })
    }
}
