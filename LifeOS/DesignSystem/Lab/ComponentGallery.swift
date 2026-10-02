import SwiftUI

/// Gallery sections. Each is rendered in the app (Settings → Direction Lab →
/// Component gallery) and snapshot-tested in light, dark and accessibility XXL.
enum LXGallerySection: String, CaseIterable, Identifiable, Sendable {
    case buttons, chips, inputs, rows, cards, metrics, data, budget, feedback, proposal, workout
    var id: String { rawValue }
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    @ViewBuilder var content: some View {
        switch self {
        case .buttons: GalleryButtons()
        case .chips: GalleryChips()
        case .inputs: GalleryInputs()
        case .rows: GalleryRows()
        case .cards: GalleryCards()
        case .metrics: GalleryMetrics()
        case .data: GalleryData()
        case .budget: GalleryBudget()
        case .feedback: GalleryFeedback()
        case .proposal: GalleryProposal()
        case .workout: GalleryWorkout()
        }
    }
}

struct ComponentGalleryView: View {
    @State private var largeText = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LX.Space.s700) {
                LXToggleRow(title: "Accessibility XXL text", explanation: "Preview every component at the largest text size.", isOn: $largeText)
                ForEach(LXGallerySection.allCases) { section in
                    VStack(alignment: .leading, spacing: LX.Space.s300) {
                        LXSectionHeader(title: section.title)
                        section.content
                    }
                }
            }
            .padding(LX.Space.screenMargin)
        }
        .background(LXScreenBackground(heroGlow: false))
        .dynamicTypeSize(largeText ? .accessibility3 : .large)
        .navigationTitle("Components")
    }
}

// MARK: - Sections

private struct GalleryButtons: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            HStack(spacing: LX.Space.s200) {
                Button("Log") {}.buttonStyle(.lx(.primary))
                Button("Edit") {}.buttonStyle(.lx(.secondary))
                Button("Saving") {}.buttonStyle(.lx(.primary, loading: true))
            }
            HStack(spacing: LX.Space.s200) {
                Button("Ask") {}.buttonStyle(.lx(.glass))
                Button("Details") {}.buttonStyle(.lx(.plain))
                Button("Delete") {}.buttonStyle(.lx(.destructive))
                Button("Off") {}.buttonStyle(.lx(.primary)).disabled(true)
            }
            HStack(spacing: LX.Space.s200) {
                LXIconButton(systemImage: "xmark", label: "Close") {}
                LXIconButton(systemImage: "calendar", label: "Calendar", glass: false) {}
            }
        }
    }
}

private struct GalleryChips: View {
    @State private var seg = 0
    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            HStack(spacing: LX.Space.s200) {
                LXChip(title: "All", kind: .filter(selected: true))
                LXChip(title: "Breakfast", kind: .filter(selected: false))
                LXChip(title: "Ask", systemImage: "sparkles", kind: .suggestion)
            }
            HStack(spacing: LX.Space.s200) {
                LXChip(title: "On track", systemImage: "checkmark", kind: .status(.statusOnTrack))
                LXChip(title: "120 over", kind: .status(.statusOver))
            }
            HStack(spacing: LX.Space.s200) {
                LXSourceBadge(source: .onDevice)
                LXSourceBadge(source: .watch)
                LXSourceBadge(source: .preset)
            }
            LXSegmented(options: [("Day", 0), ("Week", 1), ("Month", 2)], selection: $seg)
        }
    }
}

private struct GalleryInputs: View {
    @State private var grams = "180"
    @State private var bad = "abc"
    @State private var query = ""
    @State private var water = 5
    @State private var countActivity = true
    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s400) {
            LXTextField(label: "Portion", text: $grams, unit: "g", isNumeric: true)
            LXTextField(label: "Weight", text: $bad, unit: "kg", error: "Enter a number, for example 72.4", isNumeric: true)
            LXSearchField(query: $query, recents: ["Usual breakfast", "Chai"], suggestions: ["Dal tadka", "Paneer bowl"])
            LXQuickStepper(label: "Water", value: $water, range: 0...20, unit: "glasses", systemImage: "drop.fill", role: .dataWater)
            LXToggleRow(title: "Count activity calories", explanation: "Adds part of your Apple Watch active energy to today's budget.", systemImage: "flame", isOn: $countActivity)
            LXSettingsRow(title: "How much to eat back", systemImage: "fork.knife", value: "50%")
        }
    }
}

private struct GalleryRows: View {
    var body: some View {
        VStack(spacing: 0) {
            LXListRow(title: "Dal, 2 rotis, salad", subtitle: "520 kcal · 24 g protein", valueCaption: "1:10 pm", systemImage: "fork.knife", iconRole: .dataEnergy, source: .voice)
            LXListRow(title: "Water", subtitle: "5 of 8 glasses", value: "+1", systemImage: "drop.fill", iconRole: .dataWater, showsChevron: true)
        }
        .lxCard(padding: LX.Space.s300)
    }
}

private struct GalleryCards: View {
    var body: some View {
        VStack(spacing: LX.Space.cardGap) {
            LXCard(size: .hero, title: "Hero card", subtitle: "28 pt radius, 24 pt padding") { LXProgressBar(value: 0.6, role: .dataEnergy) }
            LXCard(title: "Standard card", subtitle: "22 pt radius") { Text("Content").lxFont(.body).foregroundStyle(.lx(.textSecondary)) }
            LXCard(size: .compact, title: "Compact") { EmptyView() }
            LXSheetHeader(title: "Log weight", primaryTitle: "Save", onClose: {})
                .lxCard(radius: LX.Radius.sheet, role: .surfaceRaised, padding: 0)
        }
    }
}

private struct GalleryMetrics: View {
    var body: some View {
        VStack(spacing: LX.Space.cardGap) {
            HStack(spacing: LX.Space.cardGap) {
                LXMetricTile(label: "Protein", value: "96", unit: "g", systemImage: "fork.knife", dataRole: .dataProtein, progress: 0.8, caption: "24 g to go")
                LXMetricTile(label: "Water", value: "5", unit: "of 8", systemImage: "drop.fill", dataRole: .dataWater, progress: 0.62)
            }
            HStack(spacing: LX.Space.s700) {
                LXMetricRing(value: 0.64, role: .dataEnergy, lineWidth: 12, center: AnyView(Text("64%").lxFont(.headline, numeric: true).foregroundStyle(.lx(.textPrimary))))
                    .frame(width: 96, height: 96)
                LXMetricRing(stacked: [
                    .init(id: "Protein", value: 0.8, role: .dataProtein),
                    .init(id: "Carbs", value: 0.55, role: .dataCarbs),
                    .init(id: "Fat", value: 0.4, role: .dataFat),
                ])
                .frame(width: 96, height: 96)
            }
            LXMacroBar(macros: [
                .init(name: "Protein", grams: 96, target: 120, role: .dataProtein),
                .init(name: "Carbs", grams: 150, target: 220, role: .dataCarbs),
                .init(name: "Fat", grams: 40, target: 60, role: .dataFat),
            ])
        }
    }
}

private struct GalleryData: View {
    var body: some View {
        VStack(spacing: LX.Space.cardGap) {
            LXCard(title: "Energy, 7 days", subtitle: "Goal 1,793 kcal") {
                LXSparkline(values: [1650, 1820, 1710, 1905, 1600, 1760, 1153], goal: 1793, role: .dataEnergy, height: 48)
            }
            LXEmptyState(systemImage: "chart.xyaxis.line", message: "Your trends appear after three days of logging.", actionTitle: "Log a meal")
        }
    }
}

private struct GalleryBudget: View {
    var body: some View {
        LXCard(title: "Today's budget") {
            LXBudgetExplainer(lines: LXBudgetSample.lines)
        }
    }
}

/// The plan's example breakdown (Phase 3 §3.10). Real lines come from the Health engineering spec.
enum LXBudgetSample {
    static let lines: [LXBudgetLine] = [
        .init(id: "maint", label: "Maintenance (BMR × 1.2)", kcal: 2_121, note: "Your resting energy from age, height, weight and sex, times a desk-day factor.", source: "Health profile, updated 1 Oct"),
        .init(id: "goal", label: "Goal: lose 0.5 kg/week", kcal: -550, note: "About 550 kcal a day below maintenance."),
        .init(id: "base", label: "Base budget", kcal: 1_571, kind: .subtotal),
        .init(id: "earned", label: "Earned from activity", kcal: 222, note: "50% of 443 active kcal above baseline.", source: "Active energy from Apple Watch, updated 6:52 pm", role: .dataActivity),
        .init(id: "budget", label: "Today's budget", kcal: 1_793, kind: .subtotal),
        .init(id: "eaten", label: "Eaten so far", kcal: 1_153, role: .dataEnergy),
        .init(id: "left", label: "Remaining", kcal: 640, kind: .total),
    ]
}

private struct GalleryFeedback: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            LXInlineBanner(kind: .info, message: "Using quick on-device estimates for the rest of today.")
            LXInlineBanner(kind: .attention, message: "Quick estimate. Check the portions.", actionTitle: "Review", onDismiss: {})
            LXInlineBanner(kind: .error, message: "Camera access is off.", actionTitle: "Open Settings")
            LXToast(model: LXToastModel(message: "Logged. 412 kcal, 31 g protein."))
            VStack(alignment: .leading, spacing: LX.Space.s200) {
                LXSkeleton(height: 18, width: 180)
                LXSkeleton(height: 12)
                LXSkeleton(height: 12, width: 220)
            }
            .lxCard()
        }
    }
}

private struct GalleryProposal: View {
    var body: some View {
        LXProposalCard(
            mealTitle: "Lunch", time: "1:10 pm", source: .onDevice,
            items: [
                .init(id: "dal", name: "Dal tadka", amount: "1 katori · 150 g", kcal: 180, confidence: .high),
                .init(id: "rice", name: "Rice", amount: "1 bowl · 180 g", kcal: 234, confidence: .low),
                .init(id: "roti", name: "Roti", amount: "2 pieces", kcal: 206, confidence: .medium),
            ],
            macros: [
                .init(name: "Protein", grams: 24, target: 120, role: .dataProtein),
                .init(name: "Carbs", grams: 104, target: 220, role: .dataCarbs),
                .init(name: "Fat", grams: 12, target: 60, role: .dataFat),
            ],
            note: "Check the rice portion.",
            onSavePreset: {}
        )
    }
}

private struct GalleryWorkout: View {
    var body: some View {
        VStack(spacing: LX.Space.cardGap) {
            LXWorkoutCard(title: "Strength", durationMinutes: 48, earnedKcal: 222, time: "6:40 pm", highlight: true)
            LXWorkoutCard(title: "Treadmill", durationMinutes: 20, earnedKcal: 0, time: "7:00 am", systemImage: "figure.walk", isPlanned: true)
        }
    }
}
