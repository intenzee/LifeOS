import Foundation
import LifeOSCore

/// On-disk shape of one month of one collection.
struct Shard<R: DayRecord>: Codable {
    static var currentSchemaVersion: Int { 1 }
    var schemaVersion: Int
    var records: [R]
}

/// A day-keyed collection, sharded into one JSON file per month
/// (`<collection>/<yyyy-MM>.json`). See docs/adr/0001-persistence.md.
///
/// - All I/O happens on this actor, never the main thread (FND-15).
/// - Months load lazily and stay cached. A year of heavy logging is about
///   12 small files per collection.
/// - Writes are atomic per shard. A batch upsert writes each touched shard once.
/// - A shard that fails to decode is quarantined (renamed with `.corrupt-<time>`,
///   logged as a fault) instead of blocking the user from logging today.
public actor RecordStore<R: DayRecord> {
    private let backend: any StorageBackend
    private let bus: ChangeBus?
    private var months: [String: [R]] = [:]
    public private(set) var quarantined: [String] = []

    public init(backend: any StorageBackend, bus: ChangeBus? = nil) {
        self.backend = backend
        self.bus = bus
    }

    // MARK: Reads

    /// Records for `day`, in insertion order.
    public func records(on day: DayKey) throws -> [R] {
        try month(day.monthKey).filter { $0.dayKey == day }
    }

    /// Records with `start <= dayKey <= end`, ordered by day, then insertion.
    public func records(from start: DayKey, through end: DayKey) throws -> [R] {
        guard start <= end else { return [] }
        var result: [R] = []
        for monthKey in Self.monthKeys(from: start, through: end) {
            result += try month(monthKey).filter { $0.dayKey >= start && $0.dayKey <= end }
        }
        return Self.stableSortedByDay(result)
    }

    public func record(id: R.ID, on day: DayKey) throws -> R? {
        try month(day.monthKey).first { $0.id == id && $0.dayKey == day }
    }

    /// Every record in the collection (export, migration verification).
    public func allRecords() throws -> [R] {
        let monthKeys = try backend.list(R.collection)
            .filter { $0.hasSuffix(".json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
        var result: [R] = []
        for monthKey in monthKeys { result += try month(monthKey) }
        return Self.stableSortedByDay(result)
    }

    // MARK: Writes

    public func upsert(_ record: R) throws {
        try upsert(contentsOf: [record])
    }

    /// Inserts or replaces by `id`. Writes each touched month once.
    /// To move a record to a day in another month, `delete` it first.
    public func upsert(contentsOf records: [R]) throws {
        guard !records.isEmpty else { return }
        let byMonth = Dictionary(grouping: records, by: { $0.dayKey.monthKey })
        var changedDays = Set<DayKey>()
        for (monthKey, incoming) in byMonth {
            var current = try month(monthKey)
            for record in incoming {
                // A record that moved to another day in the same month replaces in place.
                if let index = current.firstIndex(where: { $0.id == record.id }) {
                    changedDays.insert(current[index].dayKey)
                    current[index] = record
                } else {
                    current.append(record)
                }
                changedDays.insert(record.dayKey)
            }
            try persist(current, monthKey: monthKey)
        }
        bus?.publish(StoreChange(collection: R.collection, days: changedDays))
    }

    /// Read-modify-write of one record, atomic with respect to other writers of
    /// this collection (it runs entirely on the actor). Writes, and publishes a
    /// change, only when the record actually changed. Returns the stored value.
    @discardableResult
    public func update(id: R.ID, on day: DayKey, default make: () -> R, _ mutate: (inout R) -> Void) throws -> R
    where R: Equatable {
        let existing = try record(id: id, on: day)
        var value = existing ?? make()
        mutate(&value)
        if value != existing { try upsert(value) }
        return value
    }

    /// Replaces every record on `day` with `records` in one write. Publishes
    /// only when something changed.
    public func replaceAll(on day: DayKey, with records: [R]) throws where R: Equatable {
        precondition(records.allSatisfy { $0.dayKey == day }, "replaceAll records must be on \(day)")
        let current = try month(day.monthKey)
        let others = current.filter { $0.dayKey != day }
        let existing = current.filter { $0.dayKey == day }
        guard existing != records else { return }
        try persist(others + records, monthKey: day.monthKey)
        bus?.publish(StoreChange(collection: R.collection, days: [day]))
    }

    /// Removes the record. Returns `false` if it wasn't there.
    @discardableResult
    public func delete(id: R.ID, on day: DayKey) throws -> Bool {
        var current = try month(day.monthKey)
        guard let index = current.firstIndex(where: { $0.id == id && $0.dayKey == day }) else { return false }
        current.remove(at: index)
        try persist(current, monthKey: day.monthKey)
        bus?.publish(StoreChange(collection: R.collection, days: [day]))
        return true
    }

    /// Removes every record for `day` matching `predicate`. Returns the number removed.
    @discardableResult
    public func deleteAll(on day: DayKey, where predicate: (R) -> Bool) throws -> Int {
        let current = try month(day.monthKey)
        let kept = current.filter { !($0.dayKey == day && predicate($0)) }
        let removed = current.count - kept.count
        guard removed > 0 else { return 0 }
        try persist(kept, monthKey: day.monthKey)
        bus?.publish(StoreChange(collection: R.collection, days: [day]))
        return removed
    }

    // MARK: Private

    private func month(_ monthKey: String) throws -> [R] {
        if let cached = months[monthKey] { return cached }
        let path = Self.path(monthKey)
        let loaded: [R]
        do {
            if let data = try backend.read(path) {
                loaded = try Self.decoder.decode(Shard<R>.self, from: data).records
            } else {
                loaded = []
            }
        } catch is DecodingError {
            let quarantinePath = "\(path).corrupt-\(Int(Date().timeIntervalSince1970))"
            try backend.move(path, to: quarantinePath)
            quarantined.append(quarantinePath)
            Log.data.fault("Quarantined corrupt shard \(path, privacy: .public)")
            loaded = []
        } catch {
            throw AppError.storageRead(error)
        }
        months[monthKey] = loaded
        return loaded
    }

    private func persist(_ records: [R], monthKey: String) throws {
        let path = Self.path(monthKey)
        do {
            if records.isEmpty {
                try backend.remove(path)
            } else {
                let shard = Shard(schemaVersion: Shard<R>.currentSchemaVersion, records: records)
                try backend.write(try Self.encoder.encode(shard), to: path)
            }
        } catch {
            throw AppError.storageWrite(error)
        }
        months[monthKey] = records
    }

    private static func path(_ monthKey: String) -> String {
        "\(R.collection)/\(monthKey).json"
    }

    static func monthKeys(from start: DayKey, through end: DayKey) -> [String] {
        var keys: [String] = []
        var year = start.year
        var month = start.month
        while (year, month) <= (end.year, end.month) {
            keys.append(String(format: "%04d-%02d", year, month))
            month += 1
            if month > 12 { month = 1; year += 1 }
        }
        return keys
    }

    private static func stableSortedByDay(_ records: [R]) -> [R] {
        records.enumerated()
            .sorted { ($0.element.dayKey, $0.offset) < ($1.element.dayKey, $1.offset) }
            .map(\.element)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder { JSONDecoder() }
}

/// One JSON document (profile, food library), stored at `documents/<name>.json`.
public actor DocumentStore<T: Codable & Sendable> {
    private let backend: any StorageBackend
    private let bus: ChangeBus?
    private let name: String
    private var cached: T??

    public init(name: String, backend: any StorageBackend, bus: ChangeBus? = nil) {
        self.name = name
        self.backend = backend
        self.bus = bus
    }

    public func load() throws -> T? {
        if let cached { return cached }
        let value: T?
        do {
            value = try backend.read(path).map { try JSONDecoder().decode(T.self, from: $0) }
        } catch {
            throw AppError.storageRead(error)
        }
        cached = .some(value)
        return value
    }

    public func save(_ value: T) throws {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try backend.write(try encoder.encode(value), to: path)
        } catch {
            throw AppError.storageWrite(error)
        }
        cached = .some(value)
        bus?.publish(StoreChange(collection: "documents/\(name)", days: []))
    }

    private var path: String { "documents/\(name).json" }
}
