import SwiftUI

/// 3.10 Budget explainer: "Show me exactly why my number is what it is."
struct BudgetExplainerSheet: View {
    @ObservedObject var store: ExperienceStore
    @Environment(\.dismiss) private var dismiss

    private static let shares: [(label: String, value: Double)] = [("25%", 0.25), ("50%", 0.5), ("75%", 0.75), ("100%", 1)]

    var body: some View {
        VStack(spacing: 0) {
            LXSheetHeader(title: "Today's budget", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: LX.Space.s500) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(Int(store.budget.budget).formatted())").lxFont(.displayL, numeric: true)
                            .foregroundStyle(.lx(.textPrimary)).lxNumberRoll(store.budget.budget)
                        Text("kcal today").lxFont(.headline).foregroundStyle(.lx(.textSecondary))
                    }
                    .accessibilityElement(children: .combine)

                    LXBudgetExplainer(lines: store.budgetLines.map(lxLine))
                        .lxCard(padding: LX.Space.s400)

                    Text("Tap a line with ⓘ to see where it comes from.")
                        .lxFont(.footnote).foregroundStyle(.lx(.textTertiary))

                    VStack(alignment: .leading, spacing: LX.Space.s300) {
                        Text("How much activity to eat back").lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                        LXSegmented(options: Self.shares, selection: Binding(
                            get: { Self.nearest(store.eatBackShare) },
                            set: { store.setEatBack($0) }))
                        Text("Activity calories are an estimate, so most people eat back half. Applies to the Watch and streaks too.")
                            .lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
                    }
                    .lxCard(padding: LX.Space.s400)

                    if store.calorieLimitIsManual {
                        LXInlineBanner(kind: .info, message: "You set a custom daily limit in Settings. Switch to the recommended target there to see how it's calculated.")
                    }
                }
                .padding(LX.Space.s400)
            }
        }
        .background { Rectangle().fill(.lx(.background)).ignoresSafeArea() }
    }

    private static func nearest(_ v: Double) -> Double {
        shares.map(\.value).min { abs($0 - v) < abs($1 - v) } ?? 0.5
    }

    private func lxLine(_ line: ExperienceBudget.Line) -> LXBudgetLine {
        switch line.kind {
        case .component:
            return LXBudgetLine(id: line.id, label: line.label, kcal: line.kcal, kind: .component, note: line.note, source: line.source)
        case .earned:
            return LXBudgetLine(id: line.id, label: line.label, kcal: line.kcal, kind: .component, note: line.note, source: line.source, role: .dataActivity)
        case .subtotal:
            return LXBudgetLine(id: line.id, label: line.label, kcal: line.kcal, kind: .subtotal, note: line.note, source: line.source)
        case .eaten:
            return LXBudgetLine(id: line.id, label: line.label, kcal: line.kcal, kind: .subtotal, note: "Everything logged for this day.", role: .dataEnergy)
        case .total:
            return LXBudgetLine(id: line.id, label: line.label, kcal: line.kcal, kind: .total,
                                note: store.budget.isOver ? ExperienceCopy.overNote(store.budget) : nil,
                                role: store.budget.isOver ? .statusOver : .statusOnTrack)
        }
    }
}
