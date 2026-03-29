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
    let moodIndex: Int
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
                    miniCard(.mood).onTapGesture { onCardTap(.mood) }
                }
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 18).fill(palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.blue.opacity(0.6)))
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
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(palette.elevatedSurface))
    }

    func title(for type: MiniCardType) -> String {
        switch type {
        case .todo: return "To‑Do"
        case .weight: return "Weight"
        case .gym: return "Gym Intensity"
        case .mood: return "Mood"
        case .water: return "Water"
        case .food: return "Protein Food"
        }
    }

    func icon(for type: MiniCardType) -> String {
        switch type {
        case .todo: return "checkmark.circle.fill"
        case .weight: return "scalemass.fill"
        case .gym: return "dumbbell.fill"
        case .mood: return "face.smiling.fill"
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
        case .mood: return ["😞", "😐", "😊"][moodIndex]
        case .water: return "\(waterCount)/8"
        case .food: return todayMeals.summary
        }
    }

    func color(for type: MiniCardType) -> Color {
        switch type {
        case .todo: return todayTodosTotal > 0 && todayTodosCompleted == todayTodosTotal ? .green : .orange
        case .water: return waterCount >= 8 ? .green : .orange
        case .mood: return moodIndex == 2 ? .green : .orange
        case .gym:
            let intensityLevel = todayWorkout.intensity(weightKg: currentWeight)
            switch intensityLevel {
            case "High": return .green
            case "Medium": return .blue
            case "Low": return .orange
            default: return .gray
            }
        case .food:
            let count = todayMeals.highProteinCount
            return count == 3 ? .green : (count == 0 ? .orange : .blue)
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
    private var tintColor: Color { displayCount >= 8 ? .green : .orange }

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
        // Tap: +1 glass (only when not dragging)
        .onTapGesture {
            guard !isDragging else { return }
            let newValue = min(12, waterCount + 1)
            onWaterChange(newValue)
        }
        // Long-press then drag: pick an exact count
        .simultaneousGesture(longPressDragGesture)
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
        .padding()
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
        .foregroundColor(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.blue))
    }

    // MARK: - Gesture

    private var longPressDragGesture: some Gesture {
        SequenceGesture(
            LongPressGesture(minimumDuration: 0.4),
            DragGesture(minimumDistance: 0)
        )
        .onChanged { value in
            switch value {
            case .first(true):
                // Long press just recognised — enter drag mode from current count
                if !isDragging {
                    isDragging = true
                    dragStartCount = waterCount
                    dragGlasses = waterCount
                }
            case .second(_, let drag?):
                // Finger is moving — map horizontal translation to glass count
                let delta = Int(drag.translation.width / 20.0)
                dragGlasses = max(0, min(12, dragStartCount + delta))
            default:
                break
            }
        }
        .onEnded { _ in
            // Finger lifted — commit the new count and close the indicator
            if isDragging {
                onWaterChange(dragGlasses)
            }
            withAnimation { isDragging = false }
        }
    }
}

// MARK: - Calories Ring

struct CaloriesRing: View {
    @Environment(\.colorScheme) private var colorScheme
    let consumed: Double
    let limit: Double
    let burned: Double
    var progress: Double { min(consumed / limit, 1.0) }

    private var palette: ThemePalette {
        ThemePalette(colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            Circle().stroke(Color.blue.opacity(0.15), lineWidth: 20)
            Circle().trim(from: 0, to: progress).stroke(Color.blue, style: StrokeStyle(lineWidth: 20, lineCap: .round)).rotationEffect(.degrees(-90))
            VStack(spacing: 6) {
                Text("Calorie Budget").font(.title3).fontWeight(.semibold).foregroundColor(palette.textPrimary)
                Text("\(Int(consumed))").font(.system(size: 36, weight: .bold)).foregroundColor(.blue)
                Text("of \(Int(limit))").font(.subheadline).foregroundColor(palette.textSecondary)

                if burned > 0 {
                    Text("🔥 \(Int(burned)) burned").font(.caption).foregroundColor(.orange)
                }
            }
        }
        .frame(width: 220, height: 220)
    }
}
