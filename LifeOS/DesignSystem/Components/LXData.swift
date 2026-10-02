import SwiftUI
import Charts

// Phase 2 §7 components 13, 15, 16, 17, 19.

// MARK: 13 · Metric ring (single and stacked)

struct LXMetricRing: View {
    struct Ring: Identifiable, Sendable {
        let id: String
        let value: Double   // 0…1+, clamped for drawing
        let role: LXColorRole
    }
    let rings: [Ring]
    var lineWidth: CGFloat = 10
    var gap: CGFloat = 3
    var center: AnyView? = nil

    init(value: Double, role: LXColorRole, lineWidth: CGFloat = 10, center: AnyView? = nil) {
        self.rings = [Ring(id: "single", value: value, role: role)]
        self.lineWidth = lineWidth
        self.center = center
    }

    init(stacked rings: [Ring], lineWidth: CGFloat = 8, gap: CGFloat = 3, center: AnyView? = nil) {
        self.rings = rings
        self.lineWidth = lineWidth
        self.gap = gap
        self.center = center
    }

    var body: some View {
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.element.id) { index, ring in
                let inset = CGFloat(index) * (lineWidth + gap)
                let v = ring.value.isFinite ? min(max(ring.value, 0), 1) : 0
                Circle().inset(by: inset + lineWidth / 2).stroke(.lx(.separator), lineWidth: lineWidth)
                Circle().inset(by: inset + lineWidth / 2)
                    .trim(from: 0, to: v)
                    .stroke(.lx(ring.role), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .lxAnimation(.gentle, value: v)
            }
            center
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue(rings.map { "\($0.id) \(Int(($0.value.isFinite ? $0.value : 0) * 100)) percent" }.joined(separator: ", "))
    }
}

// MARK: 15 · Sparkline (7 / 30 days, goal line)

struct LXSparkline: View {
    let values: [Double]
    var goal: Double? = nil
    var role: LXColorRole = .dataEnergy
    var height: CGFloat = 36

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                LineMark(x: .value("Day", i), y: .value("Value", v))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(LXColor(role: role))
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            if let last = values.last {
                PointMark(x: .value("Day", values.count - 1), y: .value("Value", last))
                    .foregroundStyle(LXColor(role: role)).symbolSize(24)
            }
            if let goal {
                RuleMark(y: .value("Goal", goal))
                    .foregroundStyle(LXColor(role: .textTertiary))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false))
        .frame(height: height)
        .accessibilityElement()
        .accessibilityLabel("Trend over \(values.count) days")
        .accessibilityValue(values.last.map { "Latest \(Int($0))" } ?? "No data")
    }
}

// MARK: 16 · Chart frame (house style for Swift Charts)

struct LXChartFrame<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var chart: Content

    var body: some View {
        LXCard(title: title, subtitle: subtitle) {
            chart
                .chartXAxis { AxisMarks { _ in
                    AxisValueLabel().font(.caption).foregroundStyle(LXColor(role: .textSecondary))
                } }
                .chartYAxis { AxisMarks(position: .trailing) { _ in
                    AxisGridLine().foregroundStyle(LXColor(role: .separator))
                    AxisValueLabel().font(.caption).foregroundStyle(LXColor(role: .textSecondary))
                } }
                .frame(minHeight: 160)
        }
    }
}

// MARK: 17 · Budget explainer (expandable formula)

/// One line of the budget formula. The exact lines are owned by the Health
/// engineering spec (`BudgetBreakdown`, CAL-07); this component renders whatever it is given.
struct LXBudgetLine: Identifiable, Sendable, Equatable {
    enum Kind: Sendable { case component, subtotal, total }
    let id: String
    let label: String
    let kcal: Int
    var kind: Kind = .component
    var note: String? = nil         // e.g. "50% of 443 active kcal above baseline"
    var source: String? = nil       // e.g. "Active energy from Apple Watch, updated 6:52 pm"
    var role: LXColorRole? = nil
}

struct LXBudgetExplainer: View {
    let lines: [LXBudgetLine]
    @State private var expanded: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            ForEach(lines) { line in
                let expandable = line.note != nil || line.source != nil
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(line.label).lxFont(line.kind == .component ? .body : .headline)
                            .foregroundStyle(line.kind == .component ? .lx(.textSecondary) : .lx(.textPrimary))
                        if expandable {
                            Image(systemName: expanded == line.id ? "chevron.up" : "info.circle")
                                .font(.caption).foregroundStyle(.lx(.textTertiary))
                        }
                        Spacer()
                        Text(formatted(line)).lxFont(line.kind == .total ? .title2 : .headline, numeric: true)
                            .foregroundStyle(line.role.map { LXColor(role: $0) } ?? .lx(.textPrimary))
                            .lxNumberRoll(Double(line.kcal))
                    }
                    .padding(.vertical, LX.Space.s200)
                    .contentShape(Rectangle())
                    // Only lines with an explanation are tappable; the rest stay full-strength text.
                    .onTapGesture { if expandable { expanded = expanded == line.id ? nil : line.id } }
                    .accessibilityAddTraits(expandable ? .isButton : [])
                    if expanded == line.id {
                        VStack(alignment: .leading, spacing: 2) {
                            if let note = line.note { Text(note).lxFont(.footnote).foregroundStyle(.lx(.textSecondary)) }
                            if let source = line.source { Text(source).lxFont(.caption).foregroundStyle(.lx(.textTertiary)) }
                        }
                        .padding(.bottom, LX.Space.s200)
                        .transition(.opacity)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(line.label), \(formatted(line)) kilocalories")
                .accessibilityHint(line.note ?? "")
                // Hairline between lines; a heavier rule under each subtotal, none after the total.
                if line.kind != .total && line.id != lines.last?.id {
                    Rectangle().fill(.lx(.separator)).frame(height: line.kind == .subtotal ? 1 : 0.5)
                }
            }
        }
        .lxAnimation(.smooth, value: expanded)
    }

    private func formatted(_ line: LXBudgetLine) -> String {
        line.kind == .component && line.kcal > 0 && line.role == .dataActivity ? "+\(line.kcal.formatted())" : line.kcal.formatted()
    }
}

// MARK: 19 · Date scroller (swipeable day header + calendar button)

struct LXDateScroller: View {
    @Binding var date: Date
    var today: Date = Date()
    var calendar: Calendar = .current
    var onCalendar: () -> Void = {}
    @Environment(\.lxDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isToday: Bool { calendar.isDate(date, inSameDayAs: today) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(isToday ? "Today" : "Viewing").lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.textSecondary)).textCase(.uppercase)
                Spacer()
                if !isToday {
                    Button("Back to today") { move(to: today) }.buttonStyle(.plain)
                        .lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.accentPrimary))
                }
                LXIconButton(systemImage: "calendar", label: "Choose a date", glass: false, action: onCalendar)
            }
            Text(date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)))
                .lxFont(.titleLarge)
                .foregroundStyle(isToday ? .lx(.textPrimary) : .lx(.textSecondary))
                .contentTransition(.opacity)
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 24).onEnded { g in
            guard abs(g.translation.width) > abs(g.translation.height) else { return }
            shift(g.translation.width < 0 ? 1 : -1)
        })
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { d in shift(d == .increment ? 1 : -1) }
        .lxHaptic(.selection, trigger: date)
    }

    private func shift(_ days: Int) {
        guard let next = calendar.date(byAdding: .day, value: days, to: date) else { return }
        if next > today && !calendar.isDate(next, inSameDayAs: today) { return } // no future days
        move(to: next)
    }

    private func move(to d: Date) {
        withAnimation(LXMotion.smooth.animation(direction: direction, reduceMotion: reduceMotion)) { date = d }
    }
}
