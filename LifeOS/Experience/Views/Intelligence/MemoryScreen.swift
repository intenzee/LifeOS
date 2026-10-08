import SwiftUI

/// 4.2 "What LifeOS knows": find and delete any memory in under 30 seconds.
struct MemoryScreen: View {
    @ObservedObject var intelligence: IntelligenceStore = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lxTheme) private var theme
    @State private var editing: MemoryItem?
    @State private var detail: MemoryItem?
    @State private var confirmForgetAll = 0
    @State private var search = ""

    private var filtered: [MemoryItem] {
        let all = intelligence.memories
        guard !search.isEmpty else { return all }
        return all.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle(isOn: $intelligence.learnFromActivity) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Learn from my activity").lxFont(.headline)
                            Text(intelligence.learnFromActivity ? "Habits and patterns from your logs are included." : "Only what you tell LifeOS is remembered.")
                                .lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
                        }
                    }
                    .tint(theme.color(.accentPrimary))
                } footer: {
                    Text("Memories stay on this iPhone. Cloud AI only sees what a specific answer needs.")
                }

                let items = filtered
                if items.isEmpty {
                    Section {
                        Text(search.isEmpty ? "Nothing yet. Tell the assistant things like “remember I'm vegetarian”." : "No memory matches “\(search)”.")
                            .lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                    }
                }
                ForEach(MemoryItem.Category.allCases, id: \.self) { cat in
                    let rows = items.filter { $0.category == cat }
                    if !rows.isEmpty {
                        Section(cat.title) {
                            ForEach(rows) { m in row(m) }
                        }
                    }
                }

                Section {
                    Button(role: .destructive) { confirmForgetAll = 1 } label: {
                        Label("Forget everything", systemImage: "trash")
                    }
                }
            }
            .searchable(text: $search, prompt: "Find a memory")
            .navigationTitle("What LifeOS knows")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editing) { m in MemoryEditSheet(memory: m) { intelligence.edit(m.id, text: $0) } }
            .sheet(item: $detail) { m in MemoryDetailSheet(memory: m) }
            // Two-step confirmation with a summary of what goes.
            .alert("Forget everything?", isPresented: Binding(get: { confirmForgetAll == 1 }, set: { if !$0 && confirmForgetAll == 1 { confirmForgetAll = 0 } })) {
                Button("Continue", role: .destructive) { confirmForgetAll = 2 }
                Button("Cancel", role: .cancel) { confirmForgetAll = 0 }
            } message: { Text("This removes \(intelligence.forgetEverythingSummary)") }
            .alert("This can't be undone", isPresented: Binding(get: { confirmForgetAll == 2 }, set: { if !$0 { confirmForgetAll = 0 } })) {
                Button("Forget everything", role: .destructive) { intelligence.forgetEverything(); confirmForgetAll = 0 }
                Button("Keep my memories", role: .cancel) { confirmForgetAll = 0 }
            }
        }
        .lxHaptic(.destructive, trigger: confirmForgetAll == 2)
    }

    private func row(_ m: MemoryItem) -> some View {
        Button { detail = m } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if m.isPinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.lx(.accentPrimary)) }
                    Text(m.text).lxFont(.body).foregroundStyle(.lx(.textPrimary)).multilineTextAlignment(.leading)
                }
                HStack(spacing: 6) {
                    Text(m.source.label)
                    Text("·")
                    Text(m.createdAt.formatted(.dateTime.day().month(.abbreviated)))
                    if let c = m.confidenceWord { Text("· \(c)").italic() }
                }
                .lxFont(.caption).foregroundStyle(.lx(.textSecondary))
            }
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing) {
            Button(role: .destructive) { intelligence.forget([m.id]) } label: { Label("Forget", systemImage: "trash") }
            if m.category != .photoCorrections {
                Button { editing = m } label: { Label("Edit", systemImage: "pencil") }.tint(theme.color(.textSecondary))
            }
        }
        .contextMenu {
            Button(m.isPinned ? "Unpin" : "Always remember", systemImage: m.isPinned ? "pin.slash" : "pin") { intelligence.togglePin(m.id) }
            if m.category != .photoCorrections { Button("Edit", systemImage: "pencil") { editing = m } }
            Button("Forget", systemImage: "trash", role: .destructive) { intelligence.forget([m.id]) }
        }
        .accessibilityAction(named: "Forget") { intelligence.forget([m.id]) }
        .accessibilityAction(named: m.isPinned ? "Unpin" : "Always remember") { intelligence.togglePin(m.id) }
        .accessibilityActions {
            if m.category != .photoCorrections { Button("Edit") { editing = m } }
        }
    }
}

private struct MemoryEditSheet: View {
    let memory: MemoryItem
    var onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Memory", text: $text, axis: .vertical).lineLimit(2...5)
                if memory.isInferred {
                    Text("Saving turns this into something you told LifeOS.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit memory").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(text); dismiss() }.disabled(text.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear { text = memory.text }
        }
        .presentationDetents([.medium])
    }
}

private struct MemoryDetailSheet: View {
    let memory: MemoryItem
    @ObservedObject var intelligence: IntelligenceStore = .shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s400) {
            LXSheetHeader(title: memory.category.title, onClose: { dismiss() })
            Text(memory.text).lxFont(.title3).foregroundStyle(.lx(.textPrimary))
            VStack(alignment: .leading, spacing: LX.Space.s200) {
                LXListRow(title: "Source", value: memory.source.label)
                LXListRow(title: "Learned", value: memory.createdAt.formatted(date: .abbreviated, time: .omitted))
                if let e = memory.evidence { LXListRow(title: "Evidence", subtitle: e) }
                LXListRow(title: "Used in answers", value: "\(memory.usedCount)")
                if let c = memory.confidenceWord { LXListRow(title: "Confidence", value: c.capitalized) }
            }
            .lxCard(padding: LX.Space.s300)
            HStack {
                Button(memory.isPinned ? "Unpin" : "Always remember") { intelligence.togglePin(memory.id); dismiss() }.buttonStyle(.lx(.secondary))
                Spacer()
                Button("Forget") { intelligence.forget([memory.id]); dismiss() }.buttonStyle(.lx(.destructive))
            }
            Spacer()
        }
        .padding(LX.Space.s400)
        .presentationDetents([.medium, .large])
    }
}
