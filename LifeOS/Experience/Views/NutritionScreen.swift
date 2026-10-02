import SwiftUI

/// 3.8 Nutrition: meals by section, macros against targets, 30-day history, My Meals.
struct NutritionScreen: View {
    @ObservedObject var store: ExperienceStore
    var onCapture: (ExperienceMealSlot) -> Void
    var onLogPreset: (String) -> Void

    @State private var showCalendar = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LX.Space.s500) {
                LXDateScroller(date: Binding(get: { store.day }, set: { store.select(day: $0) }),
                               onCalendar: { showCalendar = true })
                header
                macros
                ForEach(ExperienceMealSlot.allCases, id: \.self) { slot in mealSection(slot) }
                history
                myMeals
            }
            .padding(.horizontal, LX.Space.s400)
            .padding(.top, LX.Space.s200)
            .padding(.bottom, LX.Space.s600)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showCalendar) {
            DatePicker("Day", selection: Binding(get: { store.day }, set: { store.select(day: $0); showCalendar = false }),
                       in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical).padding()
                .presentationDetents([.medium])
        }
    }

    private var header: some View {
        let b = store.budget
        let headline = ExperienceCopy.remainingHeadline(b)
        return HStack(spacing: LX.Space.s500) {
            LifeOrb(state: store.orbState, size: 120)
            VStack(alignment: .leading, spacing: 2) {
                Text(headline.value).lxFont(.displayL, numeric: true)
                    .foregroundStyle(b.isOver ? .lx(.statusOver) : .lx(.textPrimary)).lxNumberRoll(b.remaining)
                Text(headline.label).lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                Text("\(Int(b.eaten).formatted()) eaten of \(Int(b.budget).formatted())")
                    .lxFont(.footnote, numeric: true).foregroundStyle(.lx(.textTertiary))
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: 0)
        }
    }

    private var macros: some View {
        let log = store.log
        let t = store.macroTargets
        let p = log.totalProtein(), c = log.totalCarbs(), f = log.totalFat()
        return HStack(spacing: LX.Space.s500) {
            LXMetricRing(stacked: [
                .init(id: "Protein", value: t.protein > 0 ? p / t.protein : 0, role: .dataProtein),
                .init(id: "Carbs", value: t.carbs > 0 ? c / t.carbs : 0, role: .dataCarbs),
                .init(id: "Fat", value: t.fat > 0 ? f / t.fat : 0, role: .dataFat),
            ])
            .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: LX.Space.s200) {
                macroLine("Protein", p, t.protein, .dataProtein)
                macroLine("Carbs", c, t.carbs, .dataCarbs)
                macroLine("Fat", f, t.fat, .dataFat)
            }
        }
        .lxCard(padding: LX.Space.s400)
    }

    private func macroLine(_ name: String, _ g: Double, _ target: Double, _ role: LXColorRole) -> some View {
        let left = Int((target - g).rounded())
        return HStack(spacing: LX.Space.s200) {
            Circle().fill(.lx(role)).frame(width: 8, height: 8)
            Text(name).lxFont(.subhead).foregroundStyle(.lx(.textPrimary))
            Spacer(minLength: LX.Space.s200)
            Text(left >= 0 ? "\(Int(g.rounded())) g · \(left) left" : "\(Int(g.rounded())) g · \(-left) over")
                .lxFont(.subhead, numeric: true).foregroundStyle(.lx(.textSecondary))
        }
        .accessibilityElement(children: .combine)
    }

    private func mealSection(_ slot: ExperienceMealSlot) -> some View {
        let items = store.items(in: slot.mealType)
        let kcal = Int(items.reduce(0) { $0 + $1.calories }.rounded())
        return VStack(alignment: .leading, spacing: LX.Space.s200) {
            HStack {
                Label(slot.title, systemImage: slot.systemImage).lxFont(.title3).foregroundStyle(.lx(.textPrimary))
                    .accessibilityAddTraits(.isHeader)
                if kcal > 0 { Text("\(kcal) kcal").lxFont(.subhead, numeric: true).foregroundStyle(.lx(.textSecondary)) }
                Spacer()
                LXIconButton(systemImage: "plus", label: "Add to \(slot.title)", glass: false) { onCapture(slot) }
            }
            if items.isEmpty {
                emptyMeal(slot)
            } else {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        LXListRow(title: item.name,
                                  subtitle: "\(item.servingSize) · \(item.timestamp.formatted(date: .omitted, time: .shortened))",
                                  value: "\(Int(item.calories.rounded()))", valueCaption: "kcal",
                                  source: store.source(of: item) == .manual ? nil : store.source(of: item).lxSource)
                            .contextMenu {
                                Button(store.dependencies.foodDatabase.isFavorite(item) ? "Remove from My Meals" : "Add to My Meals",
                                       systemImage: "star") { store.toggleFavorite(item) }
                                Button("Delete", systemImage: "trash", role: .destructive) { store.remove([item.id]) }
                            }
                            .accessibilityAction(named: "Delete") { store.remove([item.id]) }
                        if item.id != items.last?.id { Rectangle().fill(.lx(.separator)).frame(height: 0.5) }
                    }
                }
                .lxCard(padding: LX.Space.s300)
            }
        }
    }

    /// Audit A7: an empty meal suggests the usual instead of "No items added".
    @ViewBuilder private func emptyMeal(_ slot: ExperienceMealSlot) -> some View {
        if store.isToday, let usual = store.presets(for: slot, limit: 1).first {
            Button { onLogPreset(usual.id) } label: {
                HStack {
                    Text("Usual \(slot.title.lowercased())? ").foregroundStyle(.lx(.textSecondary))
                        + Text("\(usual.nutrient.name) · \(Int(usual.nutrient.kcal)) kcal").foregroundStyle(.lx(.textPrimary))
                    Spacer()
                    Text("Log").lxFont(.subhead, weight: .semibold).foregroundStyle(.lx(.accentPrimary))
                }
                .lxFont(.subhead)
                .lineLimit(2)
                .lxCard(padding: LX.Space.s400)
            }
            .buttonStyle(.plain)
        } else {
            Text(store.isToday ? "Nothing yet. Tap + to log." : "Nothing logged.")
                .lxFont(.subhead).foregroundStyle(.lx(.textTertiary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .lxCard(padding: LX.Space.s400)
        }
    }

    // MARK: History (30-day heat map)

    private var history: some View {
        let days: [(date: Date, summary: DailySummary?)] = (0..<30).reversed().compactMap { offset in
            guard let d = Calendar.current.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
            return (d, store.dependencies.streakManager.summaries[store.dependencies.streakManager.dateKey(for: d)])
        }
        return VStack(alignment: .leading, spacing: LX.Space.s300) {
            LXSectionHeader(title: "Last 30 days")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10), spacing: 6) {
                ForEach(days, id: \.date) { day in
                    let s = day.summary
                    let ratio = s.map { $0.calorieLimit > 0 ? $0.caloriesConsumed / $0.calorieLimit : 0 } ?? 0
                    Button { store.select(day: day.date) } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(ratio > 1.05 ? AnyShapeStyle(.lx(.statusOver)) : AnyShapeStyle(.lx(.dataEnergy).opacity(s == nil ? 0.08 : 0.2 + min(ratio, 1) * 0.8)))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if Calendar.current.isDate(day.date, inSameDayAs: store.day) {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.lx(.textPrimary), lineWidth: 1.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(day.date.formatted(.dateTime.weekday(.wide).day().month())): \(s.map { "\(Int($0.caloriesConsumed)) of \(Int($0.calorieLimit)) kilocalories" } ?? "nothing logged")")
                }
            }
            HStack(spacing: LX.Space.s300) {
                legend(.lx(.dataEnergy).opacity(0.3), "Under")
                legend(.lx(.dataEnergy), "On budget")
                legend(.lx(.statusOver), "Over")
            }
        }
        .lxCard(padding: LX.Space.s400)
    }

    private func legend(_ style: some ShapeStyle, _ label: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3).fill(style).frame(width: 12, height: 12)
            Text(label).lxFont(.caption).foregroundStyle(.lx(.textSecondary))
        }
    }

    // MARK: My Meals

    @ViewBuilder private var myMeals: some View {
        let favourites = store.presets(limit: 20).filter(\.isFavorite)
        VStack(alignment: .leading, spacing: LX.Space.s200) {
            LXSectionHeader(title: "My Meals")
            if favourites.isEmpty {
                Text("Save a meal from the Check and log card, or long-press a food here and choose Add to My Meals.")
                    .lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                    .lxCard(padding: LX.Space.s400)
            } else {
                VStack(spacing: 0) {
                    ForEach(favourites) { p in
                        HStack {
                            LXListRow(title: p.nutrient.name, subtitle: p.nutrient.serving, value: "\(Int(p.nutrient.kcal))", valueCaption: "kcal",
                                      systemImage: "star.fill", iconRole: .dataEnergy)
                            Button("Log") { onLogPreset(p.id) }.buttonStyle(.lx(.secondary)).disabled(!store.isToday)
                        }
                        if p.id != favourites.last?.id { Rectangle().fill(.lx(.separator)).frame(height: 0.5) }
                    }
                }
                .lxCard(padding: LX.Space.s300)
            }
        }
    }
}
