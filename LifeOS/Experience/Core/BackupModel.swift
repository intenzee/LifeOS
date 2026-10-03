import Foundation

// UI/UX Phase 5 §9: backup, restore and the 7-day reinstall on a free Apple account.
// Pure logic only; file IO lives in Adapters/BackupService.swift.

/// One backup file: every data file under Application Support that LifeOS owns
/// (the record store, memories, automations, photo corrections) plus the app's
/// own settings. API keys are never in it; they live in the Keychain.
nonisolated struct BackupArchive: Codable, Equatable {
    static let format = "lifeos.backup"
    static let currentVersion = 1

    struct Summary: Codable, Equatable {
        var meals: Int
        var workoutDays: Int
        var weights: Int
        var memories: Int
        var automations: Int
        var firstDay: String?
        var lastDay: String?
    }

    var format: String = BackupArchive.format
    var version: Int = BackupArchive.currentVersion
    var createdAt: Date
    var appVersion: String
    var summary: Summary
    /// Relative path under Application Support → file bytes (base64 in JSON).
    var files: [String: Data]
    /// The app's UserDefaults domain as a binary property list.
    var defaults: Data?

    enum ReadError: LocalizedError, Equatable {
        case notABackup
        case newerVersion(Int)

        var errorDescription: String? {
            switch self {
            case .notABackup: return "This file isn't a LifeOS backup."
            case .newerVersion: return "This backup was made by a newer LifeOS. Update the app from Xcode, then try again."
            }
        }
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> BackupArchive {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let archive = try? decoder.decode(BackupArchive.self, from: data), archive.format == format else {
            throw ReadError.notABackup
        }
        guard archive.version <= currentVersion else { throw ReadError.newerVersion(archive.version) }
        return archive
    }

    /// "This backup is from 3 Oct with 1,204 meals"
    func previewLine(calendar: Calendar = .current) -> String {
        let day = createdAt.formatted(.dateTime.day().month(.abbreviated))
        let meals = summary.meals.formatted(.number)
        return "This backup is from \(day) with \(meals) \(summary.meals == 1 ? "meal" : "meals")"
    }
}

nonisolated enum BackupPolicy {
    static let keep = 7

    /// Paths under Application Support that belong in a backup. Model caches and
    /// AI quota counters (`AI/`) are rebuilt on their own and are left out.
    static func includes(_ relativePath: String) -> Bool {
        let excludedPrefixes = ["AI/", "Caches/", "tmp/"]
        guard !excludedPrefixes.contains(where: relativePath.hasPrefix) else { return false }
        let name = (relativePath as NSString).lastPathComponent
        return !name.hasPrefix(".") && !name.hasSuffix(".lock")
    }

    /// Settings that must not travel to another phone or another install.
    static func includesDefault(_ key: String) -> Bool {
        let excludedPrefixes = ["lx.backup.", "lx.refresh.", "Apple", "NS", "com.apple.", "WebKit", "INNext", "PK"]
        return !excludedPrefixes.contains(where: key.hasPrefix)
    }

    /// An automatic backup is due once per calendar day: the first open after midnight.
    static func autoBackupDue(last: Date?, now: Date, calendar: Calendar = .current) -> Bool {
        guard let last else { return true }
        return !calendar.isDate(last, inSameDayAs: now) && last < now
    }

    /// Automatic backups to delete so that only the newest `keep` remain.
    static func toPrune(_ dates: [(name: String, date: Date)], keep: Int = keep) -> [String] {
        dates.sorted { $0.date > $1.date }.dropFirst(keep).map(\.name)
    }

    static func fileName(for date: Date, automatic: Bool, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let stamp = String(format: "%04d-%02d-%02d %02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0, c.hour ?? 0, c.minute ?? 0)
        return "LifeOS \(automatic ? "Auto " : "")Backup \(stamp).json"
    }

    /// "Last backup: today, 8:02 am · 1.4 MB"
    static func lastBackupLine(date: Date?, bytes: Int?, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let date else { return "No backup yet" }
        let time = date.formatted(date: .omitted, time: .shortened)
        let day: String
        if calendar.isDate(date, inSameDayAs: now) { day = "today" }
        else if let y = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: y) { day = "yesterday" }
        else { day = date.formatted(.dateTime.day().month(.abbreviated)) }
        var line = "Last backup: \(day), \(time)"
        if let bytes { line += " · " + ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) }
        return line
    }
}

/// The free-account install lasts 7 days; this reads the end date and decides how loudly to say so.
nonisolated enum RefreshReminder {
    enum Stage: Equatable {
        case none
        /// 2 days or less: quiet banner in You → Settings (and one notification).
        case soon(daysLeft: Int)
        /// Expires today: banner moves to the top of Today.
        case lastDay
    }

    /// `embedded.mobileprovision` is a CMS envelope around an XML plist; read the plist out of it.
    static func expirationDate(fromProvisioningProfile data: Data) -> Date? {
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex) else { return nil }
        let plistData = data.subdata(in: start.lowerBound..<end.upperBound)
        let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }

    static func stage(expiry: Date?, now: Date, calendar: Calendar = .current) -> Stage {
        guard let expiry, expiry > now else { return .none }
        if calendar.isDate(expiry, inSameDayAs: now) { return .lastDay }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiry)).day ?? 99
        return days <= 2 ? .soon(daysLeft: days) : .none
    }

    /// "LifeOS needs a refresh from Xcode by Thursday. Your data is safe."
    static func message(expiry: Date, now: Date, calendar: Calendar = .current) -> String {
        let when: String
        if calendar.isDate(expiry, inSameDayAs: now) {
            when = "today, before \(expiry.formatted(date: .omitted, time: .shortened))"
        } else if let t = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(expiry, inSameDayAs: t) {
            when = "tomorrow"
        } else {
            when = expiry.formatted(.dateTime.weekday(.wide))
        }
        return "LifeOS needs a refresh from Xcode by \(when). Your data is safe."
    }

    /// The notification fires at 9 am two days before expiry (or now + 1 min if that has passed).
    static func notificationDate(expiry: Date, now: Date, calendar: Calendar = .current) -> Date? {
        guard expiry > now,
              let twoBefore = calendar.date(byAdding: .day, value: -2, to: calendar.startOfDay(for: expiry)),
              let nine = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: twoBefore) else { return nil }
        return max(nine, now.addingTimeInterval(60))
    }
}

/// RFC 4180 CSV, enough for Numbers and Excel.
nonisolated enum CSV {
    static func field(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func number(_ v: Double, decimals: Int = 1) -> String {
        guard v.isFinite else { return "" }
        return String(format: "%.\(decimals)f", locale: Locale(identifier: "en_US_POSIX"), v)
    }

    static func document(header: [String], rows: [[String]]) -> String {
        ([header] + rows).map { $0.map(field).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }
}
