import Combine
import Foundation
import LifeOSData
import UserNotifications

/// Phase 5 §9: backup, restore, CSV export and the 7-day refresh reminder.
///
/// A backup is one JSON file (`BackupArchive`) holding every LifeOS data file
/// under Application Support plus the app's settings. Restore replaces those
/// files, then the app closes so every manager reloads from disk; nothing
/// in memory can write stale data back over the restored files.
@MainActor
final class BackupService: ObservableObject {
    static let shared = BackupService()

    @Published private(set) var lastBackup: Date?
    @Published private(set) var lastBackupBytes: Int?
    @Published var autoBackup: Bool { didSet { defaults.set(autoBackup, forKey: Keys.auto) } }
    @Published private(set) var expiry: Date?

    private let defaults = UserDefaults.standard
    private let fm = FileManager.default

    private enum Keys {
        static let auto = "lx.backup.auto"
        static let last = "lx.backup.last"
        static let lastBytes = "lx.backup.lastBytes"
        static let notifiedExpiry = "lx.refresh.notifiedFor"
    }

    private init() {
        autoBackup = defaults.object(forKey: Keys.auto) as? Bool ?? true
        lastBackup = defaults.object(forKey: Keys.last) as? Date
        lastBackupBytes = defaults.object(forKey: Keys.lastBytes) as? Int
        expiry = Self.readExpiry()
    }

    // MARK: Locations

    var appSupport: URL {
        fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
    }

    /// `Documents/Backups`, visible in Files → On My iPhone → LifeOS.
    var backupsFolder: URL {
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
        let url = docs.appendingPathComponent("Backups", isDirectory: true)
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    var lastBackupLine: String { BackupPolicy.lastBackupLine(date: lastBackup, bytes: lastBackupBytes) }

    // MARK: Back up

    /// Waits for every queued store write to reach disk.
    private func flushWrites() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            LocalStore.shared.enqueue { c.resume() }
        }
    }

    func makeArchive() async throws -> BackupArchive {
        await flushWrites()
        let root = appSupport
        let files = try await Task.detached(priority: .userInitiated) { try Self.collectFiles(under: root) }.value
        let snapshot = try await LocalStore.shared.database.loadAll()
        let days = (snapshot.food.map(\.dayKey) + snapshot.workouts.map(\.dayKey)).sorted()
        let intelligence = IntelligenceStore.shared
        let summary = BackupArchive.Summary(
            meals: snapshot.food.count,
            workoutDays: snapshot.workouts.filter { !$0.isEmpty }.count,
            weights: snapshot.weight.count,
            memories: intelligence.memories.count,
            automations: intelligence.rules.count,
            firstDay: days.first?.rawValue, lastDay: days.last?.rawValue)
        let domain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
        let kept = domain.filter { BackupPolicy.includesDefault($0.key) }
        let defaultsData = try? PropertyListSerialization.data(fromPropertyList: kept, format: .binary, options: 0)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        return BackupArchive(createdAt: Date(), appVersion: version, summary: summary, files: files, defaults: defaultsData)
    }

    nonisolated private static func collectFiles(under root: URL) throws -> [String: Data] {
        var out: [String: Data] = [:]
        let rootPath = root.standardizedFileURL.path
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return out }
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            var rel = url.standardizedFileURL.path
            guard rel.hasPrefix(rootPath) else { continue }
            rel.removeFirst(rootPath.count)
            if rel.hasPrefix("/") { rel.removeFirst() }
            guard BackupPolicy.includes(rel) else { continue }
            out[rel] = try Data(contentsOf: url)
        }
        return out
    }

    /// "Back up now": a file in the temporary folder, handed to the system "Save to Files" picker.
    func backUpNowFile() async throws -> URL {
        let archive = try await makeArchive()
        let data = try archive.encoded()
        let url = fm.temporaryDirectory.appendingPathComponent(BackupPolicy.fileName(for: archive.createdAt, automatic: false))
        try data.write(to: url, options: .atomic)
        record(date: archive.createdAt, bytes: data.count)
        return url
    }

    private func record(date: Date, bytes: Int) {
        lastBackup = date
        lastBackupBytes = bytes
        defaults.set(date, forKey: Keys.last)
        defaults.set(bytes, forKey: Keys.lastBytes)
    }

    /// Call when the app becomes active: the first open after midnight writes an
    /// automatic backup into Documents/Backups and keeps the newest 7.
    func autoBackupIfDue(now: Date = Date()) {
        guard autoBackup, LocalStore.shared.phase == .ready,
              BackupPolicy.autoBackupDue(last: lastAutoBackupDate(), now: now) else { return }
        Task {
            do {
                let archive = try await makeArchive()
                let data = try archive.encoded()
                let url = backupsFolder.appendingPathComponent(BackupPolicy.fileName(for: archive.createdAt, automatic: true))
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                record(date: archive.createdAt, bytes: data.count)
                pruneAutoBackups()
            } catch {
                Log.data.error("Automatic backup failed: \(String(describing: error), privacy: .private)")
            }
        }
    }

    private func autoBackups() -> [(name: String, date: Date)] {
        let names = (try? fm.contentsOfDirectory(atPath: backupsFolder.path)) ?? []
        return names.filter { $0.hasPrefix("LifeOS Auto Backup") && $0.hasSuffix(".json") }.compactMap { name in
            let attrs = try? fm.attributesOfItem(atPath: backupsFolder.appendingPathComponent(name).path)
            return (attrs?[.creationDate] as? Date).map { (name, $0) }
        }
    }

    private func lastAutoBackupDate() -> Date? { autoBackups().map(\.date).max() }

    private func pruneAutoBackups() {
        for name in BackupPolicy.toPrune(autoBackups()) {
            try? fm.removeItem(at: backupsFolder.appendingPathComponent(name))
        }
    }

    // MARK: Restore

    func read(_ url: URL) throws -> BackupArchive {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try BackupArchive.decode(Data(contentsOf: url))
    }

    /// Replaces LifeOS's data with the archive. A safety backup of the current
    /// data is written to Documents/Backups first, so a restore can be undone.
    /// The caller closes the app afterwards.
    func restore(_ archive: BackupArchive) async throws {
        let current = try await makeArchive()
        let safety = backupsFolder.appendingPathComponent("LifeOS Before Restore \(BackupPolicy.fileName(for: current.createdAt, automatic: false).dropFirst(14))")
        try current.encoded().write(to: safety, options: .atomic)
        await flushWrites()

        let root = appSupport
        let files = archive.files
        try await Task.detached(priority: .userInitiated) {
            // Remove what a backup would contain, so nothing newer is left mixed in.
            for rel in try Self.collectFiles(under: root).keys {
                try? FileManager.default.removeItem(at: root.appendingPathComponent(rel))
            }
            for (rel, data) in files where BackupPolicy.includes(rel) && !rel.contains("..") {
                let url = root.appendingPathComponent(rel)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
        }.value

        if let blob = archive.defaults,
           let values = try? PropertyListSerialization.propertyList(from: blob, format: nil) as? [String: Any] {
            let domain = defaults.persistentDomain(forName: Bundle.main.bundleIdentifier ?? "") ?? [:]
            for key in domain.keys where BackupPolicy.includesDefault(key) { defaults.removeObject(forKey: key) }
            for (key, value) in values where BackupPolicy.includesDefault(key) { defaults.set(value, forKey: key) }
        }
        defaults.synchronize()
    }

    // MARK: CSV

    /// meals.csv, workouts.csv and weight.csv in a temporary folder.
    func exportCSV() async throws -> [URL] {
        await flushWrites()
        let s = try await LocalStore.shared.database.loadAll()
        let folder = fm.temporaryDirectory.appendingPathComponent("LifeOS CSV", isDirectory: true)
        try? fm.removeItem(at: folder)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let time = DateFormatter()
        time.locale = Locale(identifier: "en_US_POSIX")
        time.dateFormat = "HH:mm"

        let meals = CSV.document(
            header: ["date", "time", "meal", "food", "serving", "kcal", "protein_g", "carbs_g", "fat_g", "source"],
            rows: s.food.sorted { $0.loggedAt < $1.loggedAt }.map {
                [$0.dayKey.rawValue, time.string(from: $0.loggedAt), $0.meal.rawValue, $0.name, $0.servingDescription,
                 CSV.number($0.calories, decimals: 0), CSV.number($0.proteinG), CSV.number($0.carbsG), CSV.number($0.fatG), "\($0.source)"]
            })
        let workouts = CSV.document(
            header: ["date", "exercise", "body_part", "sets", "treadmill_minutes"],
            rows: s.workouts.sorted { $0.dayKey < $1.dayKey }.flatMap { day -> [[String]] in
                var rows = day.exercises.map { [day.dayKey.rawValue, $0.displayName, "\($0.bodyPart)", "\($0.setsCompleted)", ""] }
                if day.treadmillDone { rows.append([day.dayKey.rawValue, "Treadmill", "", "", CSV.number(day.treadmillMinutes, decimals: 0)]) }
                return rows
            })
        let weight = CSV.document(
            header: ["date", "kg", "source"],
            rows: s.weight.sorted { $0.measuredAt < $1.measuredAt }.map { [$0.dayKey.rawValue, CSV.number($0.kg), "\($0.source)"] })

        var urls: [URL] = []
        for (name, text) in [("meals.csv", meals), ("workouts.csv", workouts), ("weight.csv", weight)] {
            let url = folder.appendingPathComponent(name)
            try Data(text.utf8).write(to: url, options: .atomic)
            urls.append(url)
        }
        return urls
    }

    // MARK: 7-day refresh

    var refreshStage: RefreshReminder.Stage { RefreshReminder.stage(expiry: expiry, now: Date()) }

    var refreshMessage: String? {
        guard let expiry, refreshStage != .none else { return nil }
        return RefreshReminder.message(expiry: expiry, now: Date())
    }

    nonisolated private static func readExpiry() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil } // App Store / simulator builds have none.
        return RefreshReminder.expirationDate(fromProvisioningProfile: data)
    }

    /// One notification per install, two days before it stops opening. Never asks for permission itself.
    func scheduleRefreshNotification() {
        guard let expiry, let fire = RefreshReminder.notificationDate(expiry: expiry, now: Date()) else { return }
        let stamp = Int(expiry.timeIntervalSince1970)
        guard defaults.integer(forKey: Keys.notifiedExpiry) != stamp else { return }
        let center = UNUserNotificationCenter.current()
        Task {
            let status = await center.notificationSettings().authorizationStatus
            guard status == .authorized || status == .provisional else { return }
            let content = UNMutableNotificationContent()
            content.title = "Refresh LifeOS soon"
            content.body = RefreshReminder.message(expiry: expiry, now: fire)
            content.categoryIdentifier = "lx.refresh"
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let request = UNNotificationRequest(identifier: "lx.refresh.\(stamp)", content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
            guard (try? await center.add(request)) != nil else { return }
            defaults.set(stamp, forKey: Keys.notifiedExpiry)
        }
    }
}
