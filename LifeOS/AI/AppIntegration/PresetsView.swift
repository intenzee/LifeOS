import SwiftUI

/// Presets screen (F03 deliverable "Presets screen data"): see, use, rename,
/// archive and delete presets. Everything the AI saved is visible and undoable.
struct PresetsView: View {
    @Environment(\.dismiss) private var dismiss
    let onUse: (FoodPreset) -> Void

    @State private var presets: [FoodPreset] = []
    @State private var renaming: FoodPreset?
    @State private var newName = ""
    @State private var showArchived = false

    private var visible: [FoodPreset] { presets.filter { $0.archived == showArchived } }

    var body: some View {
        VStack(spacing: 0) {
            LXSheetHeader(title: "Presets", onClose: { dismiss() })
            if presets.isEmpty {
                LXEmptyState(systemImage: "star.square.on.square",
                             message: "No presets yet. Log a meal, then tap “Save as preset” — or say “remember gym shake is 1 scoop whey and 300 ml milk”.")
                    .padding(LX.Space.s500)
                Spacer()
            } else {
                LXSegmented(options: [(label: "Active", value: false), (label: "Archived", value: true)], selection: $showArchived)
                    .padding(.horizontal, LX.Space.s400)
                List {
                    ForEach(visible) { preset in
                        row(preset)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { Task { await delete(preset) } } label: { Label("Delete", systemImage: "trash") }
                                Button { Task { await toggleArchive(preset) } } label: {
                                    Label(preset.archived ? "Restore" : "Archive", systemImage: preset.archived ? "tray.and.arrow.up" : "archivebox")
                                }
                                .tint(.gray)
                            }
                            .swipeActions(edge: .leading) {
                                Button { renaming = preset; newName = preset.name } label: { Label("Rename", systemImage: "pencil") }
                                    .tint(.blue)
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(.lx(.surfaceRaised), ignoresSafeAreaEdges: .all)
        .task { await reload() }
        .alert("Rename preset", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Save") { Task { await rename() } }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    private func row(_ preset: FoodPreset) -> some View {
        Button { onUse(preset) } label: {
            VStack(alignment: .leading, spacing: LX.Space.s100) {
                HStack {
                    Text(preset.name).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                    if preset.source == .aiSuggested {
                        Image(systemName: "sparkles").imageScale(.small).foregroundStyle(.lx(.accentPrimary))
                            .accessibilityLabel("Suggested by LifeOS")
                    }
                    Spacer()
                    Text("\(Int(preset.totals.kcal.rounded())) kcal").lxFont(.subhead, numeric: true).foregroundStyle(.lx(.textPrimary))
                }
                Text(preset.items.map { "\($0.servingDescription) \($0.displayName)" }.joined(separator: " · "))
                    .lxFont(.footnote).foregroundStyle(.lx(.textSecondary)).lineLimit(2)
                HStack(spacing: LX.Space.s200) {
                    if let meal = preset.defaultMeal, meal != .unknown {
                        Text(meal.rawValue.capitalizedFirst).lxFont(.caption).foregroundStyle(.lx(.textTertiary))
                    }
                    Text(preset.usageCount == 1 ? "Used once" : "Used \(preset.usageCount) times")
                        .lxFont(.caption).foregroundStyle(.lx(.textTertiary))
                    if preset.containsEstimates {
                        Text("Contains estimates").lxFont(.caption).foregroundStyle(.lx(.statusAttention))
                    }
                }
            }
            .padding(.vertical, LX.Space.s200)
        }
        .buttonStyle(.plain)
        .listRowBackground(Color.clear)
    }

    private func reload() async { presets = await AIServices.shared.presets.all() }

    private func delete(_ preset: FoodPreset) async {
        await AIServices.shared.presets.delete(preset.id)
        await reload()
    }

    private func toggleArchive(_ preset: FoodPreset) async {
        var updated = preset
        updated.archived.toggle()
        await AIServices.shared.presets.save(updated)
        await reload()
    }

    private func rename() async {
        guard var preset = renaming else { return }
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != preset.name {
            preset.aliases.append(preset.name.lowercased())
            preset.name = trimmed
            await AIServices.shared.presets.save(preset)
        }
        renaming = nil
        await reload()
    }
}
