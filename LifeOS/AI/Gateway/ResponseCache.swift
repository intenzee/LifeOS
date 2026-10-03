import CryptoKit
import Foundation

/// Content-addressed cache of validated answers (F01 FR9).
///
/// Key = SHA-256 of task + prompt id/version + rendered user text + image bytes +
/// context. Changing the prompt version therefore invalidates old answers
/// automatically. Only validated outputs are stored. `.health` answers stay in
/// memory only; everything else may be persisted to a protected file.
actor AIResponseCache {

    nonisolated struct Entry: Codable, Sendable {
        var outputJSON: Data
        var provider: ProviderID
        var model: String
        var promptVersion: String
        var expiresAt: Date
        var persistable: Bool
    }

    private let now: @Sendable () -> Date
    private let fileURL: URL?
    private let capacity: Int
    private var entries: [String: Entry] = [:]
    private var order: [String] = []        // oldest first, for eviction
    private var loaded = false

    init(fileURL: URL? = nil, capacity: Int = 500, now: @escaping @Sendable () -> Date = { Date() }) {
        self.fileURL = fileURL
        self.capacity = capacity
        self.now = now
    }

    /// Default TTL per task. `nil` = never cache (chat, anything personalised
    /// per moment, and — in Phase 0 — photo analysis, to keep behaviour identical).
    nonisolated static func defaultTTL(for task: AITask) -> TimeInterval? {
        switch task {
        case .foodTextParse: 30 * 86_400
        case .nutritionLabelRead: 30 * 86_400
        case .presetSuggestName: 7 * 86_400
        case .nutritionEstimate: 30 * 86_400
        default: nil
        }
    }

    nonisolated static func key(for call: ProviderCall) -> String {
        var hasher = SHA256()
        func feed(_ string: String) {
            hasher.update(data: Data(string.utf8))
            hasher.update(data: Data([0]))
        }
        feed(call.task.rawValue)
        feed(call.prompt.id)
        feed(call.prompt.version)
        feed(call.prompt.instructions)
        feed(normalise(call.prompt.user))
        for image in call.input.images {
            hasher.update(data: Data(SHA256.hash(data: image.data)))
        }
        if let context = call.context { feed(context.rendered()) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Case/whitespace-insensitive so "2 Rotis " and "2 rotis" share an answer.
    nonisolated static func normalise(_ text: String) -> String {
        text.lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    func lookup(_ key: String) -> Entry? {
        loadIfNeeded()
        guard let entry = entries[key] else { return nil }
        guard entry.expiresAt > now() else {
            entries[key] = nil
            order.removeAll { $0 == key }
            return nil
        }
        return entry
    }

    func store(_ key: String, outputJSON: Data, provider: ProviderID, model: String,
               promptVersion: String, ttl: TimeInterval, privacy: PrivacyClass) {
        loadIfNeeded()
        entries[key] = Entry(outputJSON: outputJSON, provider: provider, model: model,
                             promptVersion: promptVersion, expiresAt: now().addingTimeInterval(ttl),
                             persistable: privacy < .health)
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity {
            entries[order.removeFirst()] = nil
        }
        persist()
    }

    func removeAll() {
        entries = [:]
        order = []
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
    }

    var count: Int {
        loadIfNeeded()
        return entries.count
    }

    // MARK: - Persistence

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
              let stored = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        let date = now()
        for (key, entry) in stored where entry.expiresAt > date {
            entries[key] = entry
            order.append(key)
        }
    }

    private func persist() {
        guard let fileURL else { return }
        let persistable = entries.filter { $0.value.persistable }
        guard let data = try? JSONEncoder().encode(persistable) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS) || os(watchOS)
        try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try? data.write(to: fileURL, options: [.atomic])
        #endif
    }
}
