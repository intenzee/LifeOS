import Foundation
import LifeOSCore

// WCH-15: what the watch complications and Smart Stack widgets show. The watch
// app writes it to the watch's App Group after every phone snapshot; the widget
// extension only reads it. Every number comes from the phone (the engine's
// budget, the phone's protein target): nothing is computed on the watch.

public struct ComplicationSnapshot: Codable, Sendable, Equatable {
    /// The watch's own container: App Groups are per device, so this is not
    /// the iPhone's group even though the identifier matches.
    public static let appGroup = "group.com.tanmay.LifeOS"
    public static let storageKey = "lx.watch.complications.v1"

    public struct Preset: Codable, Sendable, Equatable {
        public var name: String
        public var kcal: Double

        public init(name: String, kcal: Double) {
            self.name = name
            self.kcal = kcal
        }
    }

    public var day: DayKey
    /// `EnergyDay.budgetKcal`, including today's exercise credit.
    public var budgetKcal: Double
    public var eatenKcal: Double
    /// The exercise credit inside `budgetKcal`.
    public var earnedKcal: Double
    public var proteinG: Double?
    public var proteinTargetG: Double?
    public var waterGlasses: Int
    public var waterTarget: Int
    public var streak: Int
    /// A workout synced or a set logged today.
    public var trainedToday: Bool
    /// A LifeOS workout is running on the watch right now.
    public var workoutActive: Bool
    public var trainingWindow: TrainingWindow?
    /// The phone's top preset for the meal slot it was sent in.
    public var preset: Preset?
    public var updatedAt: Date

    public init(day: DayKey, budgetKcal: Double, eatenKcal: Double, earnedKcal: Double, proteinG: Double?,
                proteinTargetG: Double?, waterGlasses: Int, waterTarget: Int, streak: Int, trainedToday: Bool,
                workoutActive: Bool, trainingWindow: TrainingWindow?, preset: Preset?, updatedAt: Date) {
        self.day = day
        self.budgetKcal = budgetKcal
        self.eatenKcal = eatenKcal
        self.earnedKcal = earnedKcal
        self.proteinG = proteinG
        self.proteinTargetG = proteinTargetG
        self.waterGlasses = waterGlasses
        self.waterTarget = waterTarget
        self.streak = streak
        self.trainedToday = trainedToday
        self.workoutActive = workoutActive
        self.trainingWindow = trainingWindow
        self.preset = preset
        self.updatedAt = updatedAt
    }

    public var remainingKcal: Double { budgetKcal - eatenKcal }
    public var isOver: Bool { budgetKcal > 0 && remainingKcal < 0 }
    /// Eaten ÷ budget, 0…1 (the orb gauge).
    public var fill: Double { budgetKcal > 0 ? min(max(eatenKcal / budgetKcal, 0), 1) : 0 }
    public var waterFill: Double { waterTarget > 0 ? min(Double(waterGlasses) / Double(waterTarget), 1) : 0 }
    public var hasBudget: Bool { budgetKcal > 0 }

    /// The snapshot as it should read on `date`. Past midnight, yesterday's
    /// eating, water and training don't carry over: the budget drops back to
    /// its base (without yesterday's credit) until the phone sends today's.
    public func forDisplay(at date: Date, timeZone: TimeZone = .current) -> ComplicationSnapshot {
        let today = DayKey.make(for: date, timeZone: timeZone)
        guard today != day else { return self }
        var shown = self
        shown.day = today
        shown.budgetKcal = max(budgetKcal - earnedKcal, 0)
        shown.eatenKcal = 0
        shown.earnedKcal = 0
        shown.proteinG = proteinG == nil ? nil : 0
        shown.waterGlasses = 0
        shown.trainedToday = false
        shown.preset = nil
        // A streak survives midnight only if yesterday was kept; the phone decides.
        return shown
    }

    /// Whether replacing `old` with this snapshot changes anything a widget
    /// shows, so the watch only spends its reload budget on real changes. A new
    /// `updatedAt` matters only when it moves to another meal slot or day (the
    /// preset line depends on it).
    public func differsVisibly(from old: ComplicationSnapshot?, timeZone: TimeZone = .current) -> Bool {
        guard let old else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var same = self
        same.updatedAt = old.updatedAt
        return same != old
            || DayKey.make(for: updatedAt, timeZone: timeZone) != DayKey.make(for: old.updatedAt, timeZone: timeZone)
            || ComplicationTimeline.slot(of: updatedAt, calendar: calendar)
                != ComplicationTimeline.slot(of: old.updatedAt, calendar: calendar)
    }

    public static let placeholder = ComplicationSnapshot(
        day: .today(), budgetKcal: 1_920, eatenKcal: 1_280, earnedKcal: 190, proteinG: 96, proteinTargetG: 120,
        waterGlasses: 5, waterTarget: 8, streak: 6, trainedToday: false, workoutActive: false,
        trainingWindow: TrainingWindow(startMinute: 18 * 60, endMinute: 19 * 60 + 45, sessions: 8),
        preset: Preset(name: "Poha", kcal: 250), updatedAt: Date())
}

/// Codable storage (seconds since 1970, like the phone's widget snapshot).
public enum ComplicationCoding {
    public static func encode(_ snapshot: ComplicationSnapshot) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    public static func decode(_ data: Data) -> ComplicationSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(ComplicationSnapshot.self, from: data)
    }
}

/// The widget timelines (WCH-15): an entry now, one at each moment the display
/// changes on its own (midnight, the training window, meal slots), up to a day ahead.
public enum ComplicationTimeline {
    public struct Entry: Sendable, Equatable {
        public let date: Date
        /// `nil` until the phone has sent anything.
        public let snapshot: ComplicationSnapshot?
        /// Smart Stack relevance of the "Start workout" card, 0…1.
        public let workoutRelevance: Double
        /// How long that relevance lasts from `date`.
        public let workoutRelevanceDuration: TimeInterval
        /// Show the phone's preset ("Next: Poha") on the Today card.
        public let showsPreset: Bool
        /// Smart Stack relevance of the Today card, 0…1: higher around meals.
        public let todayRelevance: Double
    }

    /// The phone's meal slots by hour (breakfast 4–11, lunch 11–16, snack 16–19,
    /// dinner from 19), matching `ExperienceMealSlot.slot(for:)`.
    static let slotStartHours = [4, 11, 16, 19]
    /// Mealtimes the Today card rises for in the Smart Stack.
    static let mealHours: [ClosedRange<Int>] = [7...9, 12...14, 19...21]
    static let horizon: TimeInterval = 24 * 3600

    public static func entries(for snapshot: ComplicationSnapshot?, now: Date,
                               timeZone: TimeZone = .current) -> [Entry] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let end = now.addingTimeInterval(horizon)

        var moments: Set<Date> = [now]
        let today = DayKey.make(for: now, timeZone: timeZone)
        for day in [today, today.adding(days: 1)] {
            let midnight = day.startDate(timeZone: timeZone)
            moments.insert(midnight)
            for hour in slotStartHours + mealHours.flatMap({ [$0.lowerBound, $0.upperBound + 1] }) {
                moments.insert(midnight.addingTimeInterval(Double(hour) * 3600))
            }
            if let window = snapshot?.trainingWindow?.interval(on: day, timeZone: timeZone) {
                moments.insert(window.start)
                moments.insert(window.end)
            }
        }

        return moments.filter { $0 >= now && $0 < end }.sorted().map { date in
            guard let snapshot else {
                return Entry(date: date, snapshot: nil, workoutRelevance: 0, workoutRelevanceDuration: 0,
                             showsPreset: false, todayRelevance: 0)
            }
            let shown = snapshot.forDisplay(at: date, timeZone: timeZone)
            let hour = calendar.component(.hour, from: date)

            var workoutRelevance = 0.0
            var duration: TimeInterval = 0
            if !shown.trainedToday, !shown.workoutActive,
               let window = shown.trainingWindow?.interval(on: shown.day, timeZone: timeZone),
               window.start <= date, date < window.end {
                workoutRelevance = 1
                duration = window.end.timeIntervalSince(date)
            }
            let showsPreset = shown.preset != nil
                && slot(of: date, calendar: calendar) == slot(of: snapshot.updatedAt, calendar: calendar)
                && DayKey.make(for: snapshot.updatedAt, timeZone: timeZone) == shown.day
            let todayRelevance = mealHours.contains { $0.contains(hour) } ? 0.5 : 0.1
            return Entry(date: date, snapshot: shown, workoutRelevance: workoutRelevance,
                         workoutRelevanceDuration: duration, showsPreset: showsPreset,
                         todayRelevance: todayRelevance)
        }
    }

    /// Index into `slotStartHours`; hours before 4 belong to the previous dinner.
    static func slot(of date: Date, calendar: Calendar) -> Int {
        let hour = calendar.component(.hour, from: date)
        return slotStartHours.lastIndex { hour >= $0 } ?? slotStartHours.count - 1
    }
}
