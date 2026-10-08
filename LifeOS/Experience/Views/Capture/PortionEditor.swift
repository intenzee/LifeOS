import SwiftUI

/// 3.7 Food detail and portion: serving chips (½, 1, 1½, 2), a grams field and a
/// plate that fills as you slide, so people can estimate without a scale. Calories
/// and macros update live. `food` holds per-100 g values (barcode products).
struct PortionEditor: View {
    let food: FoodItem
    /// The pack's serving text, e.g. "30 g" or "1 bar (45 g)".
    let servingText: String
    let mealTargets: (protein: Double, carbs: Double, fat: Double)
    var onLog: (FoodItem) -> Void
    var onFavorite: ((FoodItem) -> Void)? = nil

    @State private var grams: Double
    @State private var gramsText: String
    @State private var favorited = false
    @State private var chipTick = 0
    @Environment(\.lxTheme) private var theme

    init(food: FoodItem, servingText: String, mealTargets: (protein: Double, carbs: Double, fat: Double),
         onLog: @escaping (FoodItem) -> Void, onFavorite: ((FoodItem) -> Void)? = nil) {
        self.food = food
        self.servingText = servingText
        self.mealTargets = mealTargets
        self.onLog = onLog
        self.onFavorite = onFavorite
        let start = PortionMath.defaultGrams(servingGrams: PortionMath.grams(inServing: servingText))
        _grams = State(initialValue: start)
        _gramsText = State(initialValue: Self.text(start))
    }

    private var servingGrams: Double? { PortionMath.grams(inServing: servingText) }
    private var kcal: Double { PortionMath.scale(per100: food.calories, grams: grams) }

    /// What gets logged: the per-100 g food at the chosen weight.
    private var portion: FoodItem {
        var item = food.scaled(toGrams: grams)
        item.servingSize = "\(Self.text(grams)) g"
        return item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s500) {
            VStack(alignment: .leading, spacing: LX.Space.s100) {
                Text(food.name).lxFont(.title3).foregroundStyle(.lx(.textPrimary)).lineLimit(2)
                Text("\(Int(food.calories.rounded())) kcal per 100 g" + (servingGrams.map { " · serving \(Self.text($0)) g" } ?? ""))
                    .lxFont(.footnote, numeric: true).foregroundStyle(.lx(.textSecondary))
            }

            HStack(alignment: .center, spacing: LX.Space.s500) {
                PlateFill(fill: PortionMath.plateFill(grams: grams, servingGrams: servingGrams))
                    .frame(width: 92, height: 92)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(Int(kcal.rounded()))").lxFont(.displayL, numeric: true).foregroundStyle(.lx(.textPrimary))
                            .lxNumberRoll(kcal.rounded())
                        Text("kcal").lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                    }
                    Text("for \(Self.text(grams)) g").lxFont(.subhead, numeric: true).foregroundStyle(.lx(.textSecondary))
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)

            Slider(value: Binding(get: { grams }, set: { setGrams(($0 / 5).rounded() * 5) }),
                   in: PortionMath.sliderRange(servingGrams: servingGrams))
                .tint(theme.color(.accentPrimary))
                .accessibilityLabel("Amount")
                .accessibilityValue("\(Self.text(grams)) grams")

            HStack(spacing: LX.Space.s200) {
                ForEach(PortionMath.chips(servingGrams: servingGrams), id: \.grams) { chip in
                    Button { setGrams(chip.grams); chipTick += 1 } label: {
                        LXChip(title: chip.label, kind: .filter(selected: abs(grams - chip.grams) < 0.5),
                               trailing: servingGrams == nil ? nil : "\(Self.text(chip.grams)) g")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(servingGrams == nil ? chip.label : "\(chip.label) serving, \(Self.text(chip.grams)) grams")
                }
            }
            .lxHaptic(.selection, trigger: chipTick)

            LXTextField(label: "Weight", text: Binding(get: { gramsText }, set: { typed in
                gramsText = typed
                if let g = Double(typed.replacingOccurrences(of: ",", with: ".")), g > 0, g.isFinite { grams = min(g, 5000) }
            }), placeholder: "100", unit: "g", isNumeric: true)

            LXMacroBar(macros: [
                .init(name: "Protein", grams: PortionMath.scale(per100: food.protein, grams: grams), target: mealTargets.protein, role: .dataProtein),
                .init(name: "Carbs", grams: PortionMath.scale(per100: food.carbs, grams: grams), target: mealTargets.carbs, role: .dataCarbs),
                .init(name: "Fat", grams: PortionMath.scale(per100: food.fat, grams: grams), target: mealTargets.fat, role: .dataFat),
            ])

            VStack(spacing: LX.Space.s300) {
                Button { onLog(portion) } label: {
                    Text("Log \(Int(kcal.rounded())) kcal").frame(maxWidth: .infinity)
                }
                .buttonStyle(.lx(.primary))
                .disabled(grams <= 0)
                if let onFavorite {
                    Button {
                        onFavorite(portion)
                        favorited = true
                    } label: {
                        Label(favorited ? "Saved to favourites" : "Mark as favourite", systemImage: favorited ? "star.fill" : "star")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.lx(.plain))
                    .disabled(favorited)
                    .lxHaptic(.logged, trigger: favorited)
                }
            }
        }
    }

    private func setGrams(_ g: Double) {
        let clamped = min(max(g, 1), 5000)
        grams = clamped
        gramsText = Self.text(clamped)
    }

    static func text(_ g: Double) -> String {
        g.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// A plate seen from above with a mound of food that grows with the portion.
private struct PlateFill: View {
    let fill: Double
    @Environment(\.lxTheme) private var theme

    var body: some View {
        let food = theme.color(.dataEnergy)
        ZStack {
            Circle().fill(.lx(.surfaceRaised))
            Circle().strokeBorder(.lx(.separator), lineWidth: 1)
            Circle().inset(by: 10).strokeBorder(.lx(.separator).opacity(0.6), lineWidth: 0.5)
            Circle()
                .fill(RadialGradient(colors: [food, food.opacity(0.55)],
                                     center: .init(x: 0.42, y: 0.38), startRadius: 0, endRadius: 40))
                // Area grows with the portion, so the radius follows its square root.
                .scaleEffect(max(0.08, sqrt(fill)) * 0.74)
                .lxAnimation(.smooth, value: fill)
        }
        .accessibilityHidden(true)
    }
}
