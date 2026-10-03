import Foundation
import MetricKit

/// Keeps Apple's MetricKit payloads on device (FND-21): daily performance
/// metrics, and crash, hang and disk-write diagnostics. Nothing is uploaded.
/// Payloads go to `Application Support/Diagnostics/` (excluded from backup,
/// newest 30 kept) for the in-app feedback flow (QA-16) to attach later.
/// Optional Crashlytics stays behind a flag (doc 09).
nonisolated final class Diagnostics: NSObject, MXMetricManagerSubscriber, @unchecked Sendable {
    static let shared = Diagnostics()
    private static let keep = 30

    private let directory: URL? = {
        guard var url = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
            .appendingPathComponent("Diagnostics", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        return url
    }()

    private var started = false

    /// Subscribes once. Call it early at launch.
    func start() {
        guard !started else { return }
        started = true
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads { store(payload.jsonRepresentation(), kind: "metrics") }
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            store(payload.jsonRepresentation(), kind: "diagnostics")
            let crashes = payload.crashDiagnostics?.count ?? 0
            let hangs = payload.hangDiagnostics?.count ?? 0
            Log.ui.notice("MetricKit diagnostics: \(crashes) crashes, \(hangs) hangs")
        }
    }

    private func store(_ json: Data, kind: String) {
        guard let directory else { return }
        let file = directory.appendingPathComponent("\(Int(Date().timeIntervalSince1970))-\(kind)-\(UUID().uuidString.prefix(8)).json")
        do {
            try json.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            try prune(directory)
        } catch {
            Log.ui.error("Storing MetricKit payload failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func prune(_ directory: URL) throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // names start with the Unix time, so this is newest first
        for file in files.dropFirst(Self.keep) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
