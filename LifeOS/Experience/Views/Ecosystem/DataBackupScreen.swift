import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Phase 5 §9.2: You → Data and backup.
struct DataBackupScreen: View {
    @ObservedObject private var backup = BackupService.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lxTheme) private var theme

    @State private var working: String?
    @State private var share: ShareItems?
    @State private var importing = false
    @State private var pending: BackupArchive?
    @State private var errorText: String?
    @State private var showHelp = false

    struct ShareItems: Identifiable { let id = UUID(); let urls: [URL] }

    var body: some View {
        NavigationStack {
            Form {
                if let message = backup.refreshMessage {
                    Section {
                        LXInlineBanner(kind: backup.refreshStage == .lastDay ? .attention : .info, message: message,
                                       actionTitle: "How to refresh", action: { showHelp = true })
                            .listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
                    }
                }

                Section {
                    LabeledContent("Last backup") { Text(backup.lastBackupLine.replacingOccurrences(of: "Last backup: ", with: "")).monospacedDigit() }
                    Button { run("Backing up…") { [try await backup.backUpNowFile()] } } label: {
                        Label("Back up now", systemImage: "externaldrive.badge.plus")
                    }
                    Toggle(isOn: $backup.autoBackup) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic backup")
                            Text("A fresh file the first time you open LifeOS each day. The last 7 are kept.").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .tint(theme.color(.accentPrimary))
                } header: { Text("Backup") } footer: {
                    Text("One file with your meals, presets, workouts, weight, water, todos, memories and automations. Automatic backups are in Files → On My iPhone → LifeOS → Backups. API keys are never included; they stay in the Keychain.")
                }

                Section {
                    Button { importing = true } label: { Label("Restore from a backup…", systemImage: "arrow.counterclockwise") }
                } header: { Text("Restore") } footer: {
                    Text("Replaces what's on this iPhone with the backup. Your current data is saved to Backups first, so you can go back.")
                }

                Section {
                    Button { run("Exporting…") { try await backup.exportCSV() } } label: {
                        Label("Export for spreadsheets (CSV)", systemImage: "tablecells")
                    }
                } footer: { Text("meals.csv, workouts.csv and weight.csv, for Numbers or Excel.") }

                Section("This install") {
                    if let expiry = backup.expiry {
                        LabeledContent("Opens until") { Text(expiry.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute())).monospacedDigit() }
                    } else {
                        Text("No 7-day limit on this install.").foregroundStyle(.secondary)
                    }
                    Button { showHelp = true } label: { Label("How to refresh from Xcode", systemImage: "arrow.triangle.2.circlepath") }
                }
            }
            .navigationTitle("Data and backup").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .overlay { if let working { ProgressView(working).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .disabled(working != nil)
            .sheet(item: $share) { ActivityView(items: $0.urls).ignoresSafeArea() }
            .sheet(isPresented: $showHelp) { RefreshHelpView() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                do { pending = try backup.read(result.get()) } catch { errorText = error.localizedDescription }
            }
            .alert("Restore this backup?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } }), presenting: pending) { archive in
                Button("Restore and close LifeOS", role: .destructive) { restore(archive) }
                Button("Cancel", role: .cancel) {}
            } message: { archive in
                Text("\(archive.previewLine()), \(archive.summary.workoutDays) workout days and \(archive.summary.weights) weigh-ins. LifeOS closes when it's done; open it again to see your data.")
            }
            .alert("That didn't work", isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorText ?? "") }
        }
    }

    private func run(_ label: String, _ work: @escaping () async throws -> [URL]) {
        working = label
        Task {
            defer { working = nil }
            do { share = ShareItems(urls: try await work()) } catch { errorText = error.localizedDescription }
        }
    }

    private func restore(_ archive: BackupArchive) {
        working = "Restoring…"
        Task {
            do {
                try await backup.restore(archive)
                // Every manager holds the old data in memory; closing is the only way to be sure
                // nothing writes it back over the restored files.
                exit(0)
            } catch {
                working = nil
                errorText = error.localizedDescription
            }
        }
    }
}

/// Phase 5 §9.3: the refresh routine, in under 2 minutes.
struct RefreshHelpView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var backup = BackupService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LX.Space.s500) {
                    Text("Apps installed from Xcode with a free Apple account stop opening 7 days after install. Running LifeOS again from Xcode gives it another 7 days. Your data stays exactly as it is.")
                        .lxFont(.body).foregroundStyle(.lx(.textSecondary))
                    if let expiry = backup.expiry {
                        Text("This install opens until \(expiry.formatted(.dateTime.weekday(.wide).day().month().hour().minute())).")
                            .lxFont(.headline, numeric: true).foregroundStyle(.lx(.textPrimary))
                    }
                    step(1, "Connect", "Plug the iPhone into the Mac, or use the same Wi-Fi with wireless debugging on.")
                    step(2, "Run", "Open LifeOS.xcodeproj in Xcode, choose your iPhone at the top, press Run (⌘R).")
                    step(3, "Watch too", "If the Watch app has stopped opening, choose the \"LifeOS Watch App\" scheme and your Watch, then Run.")
                    step(4, "Done", "LifeOS opens with a fresh 7 days and all your data.")
                    LXInlineBanner(kind: .attention, message: "Don't delete the app to fix it: deleting removes all LifeOS data. If you ever need to, back up first in Data and backup.")
                }
                .padding(LX.Space.s400)
            }
            .navigationTitle("Refresh LifeOS").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    private func step(_ n: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: LX.Space.s300) {
            Text("\(n)").lxFont(.headline, numeric: true).foregroundStyle(.lx(.onAccent))
                .frame(width: 28, height: 28).background(Circle().fill(.lx(.accentPrimary)))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                Text(text).lxFont(.body).foregroundStyle(.lx(.textSecondary)).fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(n). \(title). \(text)")
    }
}

/// The system share sheet (Save to Files, AirDrop, Mail…).
struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
