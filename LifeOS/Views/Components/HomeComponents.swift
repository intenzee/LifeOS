import SwiftUI

struct DailyProgressContainer: View {
    @Environment(\.colorScheme) private var colorScheme
    let order: [MiniCardType]
    let waterCount: Int
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
        VStack(alignment: .leading, spacing: 16) {
            Text("Daily Progress").font(.headline).foregroundColor(palette.textPrimary)

            VStack(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(order, id: \.self) { card in
                        if card == .water {
                            WaterMiniCard(
                                waterCount: waterCount,
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

                HStack(spacing: 12) {
                    miniCard(.weight).onTapGesture { onCardTap(.weight) }
                    miniCard(.sleep).onTapGesture { onCardTap(.sleep) }
                }
            }
            .padding(24)
            .background(RoundedRectangle(cornerRadius: 32).fill(palette.surface))
        }
    }

    func miniCard(_ type: MiniCardType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon(for: type))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(color(for: type))

                Text(title(for: type))
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }

            Text(value(for: type)).font(.headline).foregroundColor(color(for: type)).lineLimit(2).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.elevatedSurface))
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
        case .water: return "\(waterCount)/8"
        case .food: return todayMeals.summary
        }
    }

    func color(for type: MiniCardType) -> Color {
        switch type {
        case .todo: return todayTodosTotal > 0 && todayTodosCompleted == todayTodosTotal ? palette.primaryAccent : .orange
        case .water: return waterCount >= 8 ? palette.primaryAccent : .orange
        case .sleep: return sleepDuration >= 7.0 ? palette.primaryAccent : (sleepDuration > 0 ? .orange : palette.textSecondary)
        case .gym:
            let intensityLevel = todayWorkout.intensity(weightKg: currentWeight)
            switch intensityLevel {
            case "High": return palette.primaryAccent
            case "Medium": return .blue
            case "Low": return .orange
            default: return palette.textSecondary
            }
        case .food:
            let count = todayMeals.highProteinCount
            return count == 3 ? palette.primaryAccent : (count == 0 ? .orange : .blue)
        default: return .blue
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
    let onWaterChange: (Int) -> Void

    @State private var isDragging = false
    @State private var dragGlasses: Int = 0
    @State private var dragStartCount: Int = 0

    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }
    private var displayCount: Int { isDragging ? dragGlasses : waterCount }
    private var tintColor: Color { displayCount >= 8 ? palette.primaryAccent : .orange }

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
            Text("\(displayCount)/8")
                .font(.headline)
                .foregroundColor(tintColor)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(isDragging ? palette.surface : palette.elevatedSurface)
        )
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
        .background(Capsule().fill(palette.primaryAccent))
    }
}

// MARK: - Calories Ring
struct CaloriesRing: View {
    @Environment(\.colorScheme) private var colorScheme
    let consumed: Double
    let limit: Double
    let burned: Double
    let water: Int // using water for the third stat

    var progress: Double { min(consumed / limit, 1.0) }
    var remaining: Int { max(0, Int(limit) - Int(consumed)) }

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    var body: some View {
        VStack(spacing: 32) {
            // Ring
            ZStack {
                Circle()
                    .stroke(palette.elevatedSurface, lineWidth: 22)
                
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        palette.primaryAccent,
                        style: StrokeStyle(lineWidth: 22, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: palette.primaryAccent.opacity(0.4), radius: 10, x: 0, y: 0)

                VStack(spacing: 4) {
                    Text("CALORIES REMAINING")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .kerning(1.5)
                        .foregroundColor(palette.textSecondary)
                    
                    Text("\(remaining)")
                        .font(.system(size: 46, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("kcal")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(palette.primaryAccent)
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
                .foregroundColor(.white)
        }
    }
}
