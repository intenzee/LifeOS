import Charts
import SwiftUI

/// 4.3 Weekly review: a full-screen story of up to 5 pages, swiped horizontally.
struct WeeklyReviewView: View {
    let review: WeeklyReview
    @ObservedObject var intelligence: IntelligenceStore = .shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var reminderCreated = false

    private var pageCount: Int { review.pattern == nil ? 4 : 5 }

    var body: some View {
        ZStack(alignment: .top) {
            LXScreenBackground(heroGlow: true).ignoresSafeArea()
            TabView(selection: $page) {
                pageOne.tag(0)
                numbers.tag(1)
                bestDay.tag(2)
                if let p = review.pattern { patternPage(p).tag(3) }
                focus.tag(pageCount - 1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : nil, value: page)

            VStack(spacing: LX.Space.s300) {
                HStack(spacing: 4) {
                    ForEach(0..<pageCount, id: \.self) { i in
                        Capsule().fill(i <= page ? AnyShapeStyle(.lx(.textPrimary)) : AnyShapeStyle(.lx(.separator))).frame(height: 3)
                    }
                }
                HStack {
                    Text(review.range).lxFont(.footnote, numeric: true).foregroundStyle(.lx(.textSecondary))
                    Spacer()
                    LXIconButton(systemImage: "xmark", label: "Close review", glass: true) { dismiss() }
                }
            }
            .padding(.horizontal, LX.Space.s400)
            .padding(.top, LX.Space.s200)
            .accessibilityElement(children: .contain)
        }
    }

    private func pageFrame<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: LX.Space.s500) {
            Text(title).lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.textSecondary)).textCase(.uppercase)
            content()
            Spacer()
        }
        .padding(.horizontal, LX.Space.s600)
        .padding(.top, 110)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var pageOne: some View {
        VStack(spacing: LX.Space.s600) {
            Spacer()
            LifeOrb(state: LifeOrbState(fillLevel: review.averageFill, rimIntensity: Double(review.workouts) / 5))
            Text(review.oneLine).lxFont(.title2).foregroundStyle(.lx(.textPrimary)).multilineTextAlignment(.center)
            Text("Swipe for the week in a few pages").lxFont(.footnote).foregroundStyle(.lx(.textTertiary))
            Spacer()
        }
        .padding(.horizontal, LX.Space.s600)
    }

    private var numbers: some View {
        pageFrame("The numbers") {
            VStack(alignment: .leading, spacing: LX.Space.s300) {
                stat("Average intake", "\(Fmt.kcal(review.avgIntake)) kcal", sub: review.avgBudget > 0 ? "against \(Fmt.kcal(review.avgBudget)) budget" : nil)
                stat("Protein", Fmt.grams(review.avgProtein), sub: review.proteinTarget > 0 ? "a day, target \(Fmt.grams(review.proteinTarget))" : "a day")
                stat("Workouts", "\(review.workouts)", sub: "logged days with training")
                stat("Days logged", "\(review.loggedDays) of 7", sub: nil)
            }
            Chart {
                ForEach(review.daily, id: \.date) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("kcal", d.kcal))
                        .foregroundStyle(d.budget > 0 && d.kcal > d.budget ? AnyShapeStyle(.lx(.statusOver)) : AnyShapeStyle(.lx(.dataEnergy)))
                        .cornerRadius(4)
                }
                if review.avgBudget > 0 {
                    RuleMark(y: .value("Budget", review.avgBudget)).foregroundStyle(.lx(.textSecondary))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .chartXAxis { AxisMarks(values: .stride(by: .day)) { _ in AxisValueLabel(format: .dateTime.weekday(.narrow)) } }
            .frame(height: 160)
            .accessibilityLabel("Calories each day this week")
        }
    }

    private func stat(_ label: String, _ value: String, sub: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).lxFont(.body).foregroundStyle(.lx(.textSecondary))
            Spacer()
            VStack(alignment: .trailing, spacing: 0) {
                Text(value).lxFont(.title3, numeric: true).foregroundStyle(.lx(.textPrimary))
                if let sub { Text(sub).lxFont(.caption).foregroundStyle(.lx(.textTertiary)) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var bestDay: some View {
        pageFrame("Best day") {
            if let best = review.bestDay {
                Text(Fmt.weekday(best.date)).lxFont(.displayL).foregroundStyle(.lx(.textPrimary))
                Text(best.reason).lxFont(.title3).foregroundStyle(.lx(.textSecondary))
            } else {
                Text("No day landed on budget this week.").lxFont(.title3).foregroundStyle(.lx(.textPrimary))
                Text("That's useful to know, not a verdict. Next week is a fresh start.").lxFont(.body).foregroundStyle(.lx(.textSecondary))
            }
        }
    }

    private func patternPage(_ card: InsightCard) -> some View {
        pageFrame("One pattern") {
            InsightCardView(card: card)
        }
    }

    private var focus: some View {
        pageFrame("Next week's focus") {
            Text(review.focus.claim).lxFont(.title2).foregroundStyle(.lx(.textPrimary))
            if case .createReminder(let rule) = review.focus.action {
                Text(AutomationText.sentence(rule)).lxFont(.body).foregroundStyle(.lx(.textSecondary))
                Button {
                    intelligence.upsert(rule)
                    reminderCreated = true
                } label: {
                    Text(reminderCreated ? "Reminder on" : (review.focus.actionTitle ?? "Create reminder")).frame(maxWidth: .infinity)
                }
                .buttonStyle(.lx(.primary))
                .disabled(reminderCreated || intelligence.rules.contains { $0.id == rule.id && $0.isOn })
            }
            Button("Done") { dismiss() }.buttonStyle(.lx(.plain)).frame(maxWidth: .infinity)
        }
        .lxHaptic(.logged, trigger: reminderCreated)
    }
}

/// Insight card anatomy (Phase 4 §4.3): claim, evidence with range, action, "Not useful", source.
struct InsightCardView: View {
    let card: InsightCard
    var onAction: (() -> Void)? = nil
    @AppStorage("lx.insights.notUseful") private var notUsefulRaw = ""

    private var dismissed: Bool { notUsefulRaw.split(separator: ",").contains { $0 == card.id } }

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            Text(card.claim).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
            if !card.evidence.isEmpty {
                Chart {
                    ForEach(card.evidence, id: \.label) { e in
                        BarMark(x: .value("Value", e.value), y: .value("Group", e.label))
                            .foregroundStyle(.lx(.dataEnergy)).cornerRadius(4)
                            .annotation(position: .trailing) { Text(Fmt.kcal(e.value)).lxFont(.caption, numeric: true).foregroundStyle(.lx(.textSecondary)) }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(card.evidence.count) * 36)
                Text(card.evidenceRange).lxFont(.caption).foregroundStyle(.lx(.textTertiary))
            }
            HStack {
                LXSourceBadge(source: .onDevice)
                Text(card.learnedFrom).lxFont(.caption).foregroundStyle(.lx(.textTertiary))
                Spacer()
                Button(dismissed ? "Thanks, noted" : "Not useful") {
                    if !dismissed { notUsefulRaw = (notUsefulRaw.isEmpty ? "" : notUsefulRaw + ",") + card.id }
                }
                .buttonStyle(.plain).lxFont(.caption, weight: .medium).foregroundStyle(.lx(.textSecondary))
                .disabled(dismissed)
            }
            if let title = card.actionTitle, let onAction {
                Button(title, action: onAction).buttonStyle(.lx(.secondary))
            }
        }
        .lxCard(padding: LX.Space.s400)
    }
}
