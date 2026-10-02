import SwiftUI

struct DailyProgressContainer: View {
    @Environment(\.colorScheme) private var colorScheme
    let order: [MiniCardType]
    let waterCount: Int
    var waterTarget: Int = 8
    let todayTodosCompleted: Int
    let todayTodosTotal: Int
    let currentWeight: Double
    let targetWeight: Double
    let showCurrentWeight: Bool
    let todayWorkout: DayWorkout
    let sleepDuration: Double
    let todayMeals: DayMeals

    let onCardTap: (MiniCardType) -> Void
    let onCardLongPress: (MiniCardType) -> Void
    let onWaterChange: (Int) -> Void

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    var weightRemaining: Double { currentWeight - targetWeight }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.medium) {
            SectionHeader("Daily Progress")

            VStack(spacing: DesignSystem.Spacing.small) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                          spacing: DesignSystem.Spacing.small) {
                    ForEach(order, id: \.self) { card in
                        if card == .water {
                            WaterMiniCard(
                                waterCount: waterCount,
                                waterTarget: waterTarget,
                                onWaterChange: onWaterChange
                            )
                        } else {
                            miniCard(card)
                                .contentShape(Rectangle())
                                .onTapGesture { onCardTap(card) }
                                .onLongPressGesture(minimumDuration: 0.5) { onCardLongPress(card) }
                        }
                    }
                }

                HStack(spacing: DesignSystem.Spacing.small) {
                    miniCard(.weight).onTapGesture { onCardTap(.weight) }
                    miniCard(.sleep).onTapGesture { onCardTap(.sleep) }
                }
            }
            .padding(DesignSystem.Spacing.large)
            .glassCard(cornerRadius: DesignSystem.Radius.xl)
        }
    }

    func miniCard(_ type: MiniCardType) -> some View {
        MetricTile(icon: icon(for: type),
                   title: title(for: type),
                   value: value(for: type),
                   tint: color(for: type),
                   progress: progress(for: type))
    }

    func title(for type: MiniCardType) -> String {
        switch type {
        case .todo: return "To‑Do"
        case .weight: return "Weight"
        case .gym: return "Gym Intensity"
        case .sleep: return "Sleep"
        case .water: return "Water"
        case .food: return "Protein Food"
        }
    }

    func icon(for type: MiniCardType) -> String {
        switch type {
        case .todo: return "checkmark.circle.fill"
        case .weight: return "scalemass.fill"
        case .gym: return "dumbbell.fill"
        case .sleep: return "moon.zzz.fill"
        case .water: return "drop.fill"
        case .food: return "fork.knife"
        }
    }

    func value(for type: MiniCardType) -> String {
        switch type {
        case .todo: return "\(todayTodosCompleted)/\(todayTodosTotal) Done"
        case .weight:
            let baseWeight = showCurrentWeight ? "\(String(format: "%.1f", currentWeight)) kg" : "Target \(Int(targetWeight))"
            if weightRemaining > 0 {
                return "\(baseWeight)\n\(String(format: "%.1f", weightRemaining)) kg to go"
            }
            return baseWeight
        case .gym: return todayWorkout.intensity(weightKg: currentWeight)
        case .sleep: return "\(String(format: "%.1f", sleepDuration)) hrs"
        case .water: return "\(waterCount)/\(waterTarget)"
        case .food: return todayMeals.summary
        }
    }

    /// Progress bar value (0…1) for tiles where a target exists; nil to omit the bar.
    func progress(for type: MiniCardType) -> Double? {
        switch type {
        case .todo:
            return todayTodosTotal > 0 ? Double(todayTodosCompleted) / Double(todayTodosTotal) : 0
        case .water:
            return waterTarget > 0 ? Double(waterCount) / Double(waterTarget) : 0
        case .sleep:
            return min(sleepDuration / 8.0, 1)
        case .gym:
            switch todayWorkout.intensity(weightKg: currentWeight) {
            case "High": return 1.0
            case "Medium": return 0.66
            case "Low": return 0.33
            default: return 0
            }
        case .food:
            return Double(todayMeals.highProteinCount) / 4.0
        case .weight:
            return nil
        }
    }

    func color(for type: MiniCardType) -> Color {
        switch type {
        case .todo: return todayTodosTotal > 0 && todayTodosCompleted == todayTodosTotal ? palette.success : palette.warning
        case .water: return waterCount >= waterTarget ? palette.success : palette.warning
        case .sleep: return sleepDuration >= 7.0 ? palette.success : (sleepDuration > 0 ? palette.warning : palette.textSecondary)
        case .gym:
            switch todayWorkout.intensity(weightKg: currentWeight) {
            case "High": return palette.success
            case "Medium": return palette.info
            case "Low": return palette.warning
            default: return palette.textSecondary
            }
        case .food:
            let count = todayMeals.highProteinCount
            return count >= 3 ? palette.success : (count == 0 ? palette.warning : palette.info)
        default: return palette.info
        }
    }
}

// MARK: - Water Mini Card
/// Dedicated card for water tracking.
/// - Tap: adds one glass.
/// - Long-press + drag left/right: adjusts count (every ~20pt = 1 glass, clamped 0–12).
///   Releases finger → saves and dismisses the drag indicator automatically.
private struct WaterMiniCard: View {
    @Environment(\.colorScheme) private var colorScheme

    let waterCount: Int
    var waterTarget: Int = 8
    let onWaterChange: (Int) -> Void

    @State private var isDragging = false
    @State private var dragGlasses: Int = 0
    @State private var dragStartCount: Int = 0

    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }
    private var displayCount: Int { isDragging ? dragGlasses : waterCount }
    private var tintColor: Color { displayCount >= waterTarget ? palette.success : palette.warning }

    var body: some View {
        ZStack(alignment: .top) {
            cardFace

            if isDragging {
                dragPill
                    .offset(y: -14)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isDragging)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture()
                .onEnded {
                    guard !isDragging else { return }
                    let newValue = min(12, waterCount + 1)
                    onWaterChange(newValue)
                }
        )
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5)
                .onEnded { _ in
                    isDragging = true
                    dragStartCount = waterCount
                    dragGlasses = waterCount
                }
                .sequenced(before: DragGesture(minimumDistance: 5))
                .onChanged { value in
                    if case .second(true, let drag?) = value {
                        let delta = Int(drag.translation.width / 20.0)
                        dragGlasses = max(0, min(12, dragStartCount + delta))
                    }
                }
                .onEnded { _ in
                    if isDragging {
                        onWaterChange(dragGlasses)
                    }
                    withAnimation { isDragging = false }
                }
        )
    }

    // MARK: - Subviews

    private var cardFace: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(tintColor)
                Text("Water")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            Text("\(displayCount)/\(waterTarget)")
                .font(.system(.headline, design: .rounded))
                .foregroundColor(tintColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            LinearProgress(value: waterTarget > 0 ? Double(displayCount) / Double(waterTarget) : 0,
                           tint: tintColor, track: palette.track, height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(DesignSystem.Spacing.medium)
        .glassCard(cornerRadius: DesignSystem.Radius.md, elevation: isDragging ? 0.9 : 0.4)
        .scaleEffect(isDragging ? 1.04 : 1.0)
    }

    private var dragPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "drop.fill").font(.caption2)
            Text("\(dragGlasses) / 12").font(.caption.weight(.semibold))
        }
        .foregroundColor(.black)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(palette.success))
    }
}

// MARK: - Calories Ring
struct CaloriesRing: View {
    @Environment(\.colorScheme) private var colorScheme
    let consumed: Double
    let limit: Double
    let burned: Double
    let water: Int // using water for the third stat

    /// Guards against divide-by-zero / non-finite values when no goal is set yet.
    var progress: Double {
        guard limit > 0 else { return 0 }
        let p = consumed / limit
        return p.isFinite ? min(max(p, 0), 1) : 0
    }
    /// Over-budget shows a warning tint; otherwise the accent.
    private var ringColor: Color { consumed > limit && limit > 0 ? palette.warning : palette.primaryAccent }
    var remaining: Int { max(0, Int(limit) - Int(consumed)) }

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: DesignSystem.Spacing.xLarge) {
            RingGauge(progress: progress, lineWidth: 22, color: ringColor, track: palette.track) {
                VStack(spacing: 4) {
                    Text("CALORIES REMAINING")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .kerning(1.5)
                        .foregroundColor(palette.textSecondary)

                    Text("\(remaining)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundColor(palette.textPrimary)
                        .contentTransition(.numericText())

                    Text("kcal")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(ringColor)
                }
            }
            .frame(width: 250, height: 250)

            // Sub-metrics (Eaten, Burned, Water)
            HStack(spacing: 0) {
                metricColumn(title: "EATEN", value: "\(Int(consumed))")
                Spacer()
                metricColumn(title: "BURNED", value: "\(Int(burned))")
                Spacer()
                metricColumn(title: "WATER", value: "\(water)")
            }
            .padding(.horizontal, 40)
        }
    }
    
    @ViewBuilder
    private func metricColumn(title: String, value: String) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .kerning(1.2)
                .foregroundColor(palette.textSecondary)
            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundColor(palette.textPrimary)
        }
    }
}
