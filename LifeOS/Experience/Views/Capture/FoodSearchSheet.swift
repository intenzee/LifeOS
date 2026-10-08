import SwiftUI

/// Search your foods (Capture → Search). Replaces the classic search overlay,
/// whose Common / Recent / Favourites tabs did nothing: here the filter works,
/// results rank by how well the name matches, a star keeps a food as a favourite,
/// and a scanned product opens the 3.7 portion controls first.
struct FoodSearchSheet: View {
    @ObservedObject var foods: FoodDatabaseManager
    let initialSlot: ExperienceMealSlot
    let mealTargets: (protein: Double, carbs: Double, fat: Double)
    var onLog: (FoodItem) -> Void
    var onSaveCustom: (FoodItem) -> Void

    private enum Filter: Hashable { case all, recent, favourites, mine }

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var filter: Filter = .all
    @State private var slot: ExperienceMealSlot = .lunch
    @State private var portionFor: FoodItem?
    @State private var addingOwn = false
    @State private var starTick = 0
    @FocusState private var searching: Bool
    @Environment(\.lxTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            LXSheetHeader(title: "Search foods", onClose: { dismiss() })
            VStack(alignment: .leading, spacing: LX.Space.s300) {
                searchField
                LXSegmented(options: [("All", Filter.all), ("Recent", .recent), ("Favourites", .favourites), ("Mine", .mine)],
                            selection: $filter)
                mealChips
            }
            .padding(.horizontal, LX.Space.s400)
            .padding(.top, LX.Space.s300)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: LX.Space.s200) {
                    if addingOwn {
                        ManualFoodForm(slot: slot, initialName: query.trimmingCharacters(in: .whitespacesAndNewlines),
                                       onSave: { food, _ in
                                           onSaveCustom(food)
                                           log(food)
                                       },
                                       onCancel: { addingOwn = false })
                            .lxCard(radius: LX.Radius.hero, padding: LX.Space.s500)
                    } else if results.isEmpty {
                        emptyState
                    } else {
                        ForEach(results) { food in row(food) }
                        Button { addingOwn = true } label: {
                            Label("Enter a food yourself", systemImage: "plus").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.lx(.plain))
                        .padding(.top, LX.Space.s200)
                    }
                }
                .padding(LX.Space.s400)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background { Rectangle().fill(.lx(.background)).ignoresSafeArea() }
        .onAppear {
            slot = initialSlot
            searching = true
        }
        .lxHaptic(.selection, trigger: starTick)
        .sheet(item: $portionFor) { food in
            ScrollView {
                PortionEditor(food: food, servingText: food.servingSize, mealTargets: mealTargets,
                              onLog: { portion in portionFor = nil; log(portion) })
                    .padding(LX.Space.s500)
            }
            .lxSheetStyle(detents: [.large])
        }
    }

    // MARK: Pieces

    private var searchField: some View {
        HStack(spacing: LX.Space.s200) {
            Image(systemName: "magnifyingglass").foregroundStyle(.lx(.textSecondary))
            TextField("Search your foods", text: $query)
                .lxFont(.body)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .tint(theme.color(.accentPrimary))
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.lx(.textTertiary)) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, LX.Space.s400)
        .frame(minHeight: LX.Space.minTouchTarget + 4)
        .background(RoundedRectangle(cornerRadius: LX.Radius.tile, style: .continuous).fill(.lx(.surfaceRaised)))
    }

    private var mealChips: some View {
        ScrollView(.horizontal) {
            HStack(spacing: LX.Space.s200) {
                ForEach(ExperienceMealSlot.allCases, id: \.self) { s in
                    Button { slot = s } label: {
                        LXChip(title: s.title, systemImage: s.systemImage, kind: .filter(selected: s == slot))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(s == slot ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .lxHaptic(.selection, trigger: slot)
    }

    private func row(_ food: FoodItem) -> some View {
        let favourite = foods.isFavorite(food)
        let adjustable = Self.per100(food) != nil
        return HStack(spacing: LX.Space.s300) {
            Button { pick(food) } label: {
                HStack(spacing: LX.Space.s300) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(food.name).lxFont(.headline).foregroundStyle(.lx(.textPrimary)).lineLimit(2)
                        Text("\(Int(food.calories.rounded())) kcal · \(food.servingSize)")
                            .lxFont(.footnote, numeric: true).foregroundStyle(.lx(.textSecondary))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: adjustable ? "scalemass" : "plus.circle.fill")
                        .font(.title3).foregroundStyle(.lx(.accentPrimary))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(adjustable ? "\(food.name), choose amount" : "Log \(food.name), \(Int(food.calories.rounded())) kilocalories")

            Button {
                foods.toggleFavorite(food)
                starTick += 1
            } label: {
                Image(systemName: favourite ? "star.fill" : "star")
                    .foregroundStyle(favourite ? .lx(.accentPrimary) : .lx(.textTertiary))
                    .frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(favourite ? "Remove \(food.name) from favourites" : "Add \(food.name) to favourites")
        }
        .padding(.leading, LX.Space.s400)
        .padding(.trailing, LX.Space.s100)
        .padding(.vertical, LX.Space.s100)
        .lxCard(radius: LX.Radius.tile, padding: 0)
    }

    @ViewBuilder private var emptyState: some View {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        LXEmptyState(systemImage: filter == .favourites ? "star" : "magnifyingglass",
                     message: emptyMessage(typed),
                     actionTitle: "Enter it yourself",
                     action: { addingOwn = true })
            .lxCard()
    }

    private func emptyMessage(_ typed: String) -> String {
        if !typed.isEmpty { return "Nothing called “\(typed)” yet. Add it once and it's here next time." }
        switch filter {
        case .favourites: return "No favourites yet. Tap the star on any food to keep it here."
        case .recent: return "Foods you log show up here."
        case .mine: return "Foods you enter yourself show up here."
        case .all: return "No foods yet."
        }
    }

    // MARK: Data

    private var pool: [FoodItem] {
        switch filter {
        case .all: return foods.allFoods
        case .recent: return Self.unique(foods.recentFoods)
        case .favourites: return Self.unique(foods.favoriteFoods)
        case .mine: return Self.unique(foods.customFoods)
        }
    }

    private var results: [FoodItem] {
        let list = pool
        return FoodSearch.rank(list.map(\.name), query: query).prefix(80).map { list[$0] }
    }

    private func pick(_ food: FoodItem) {
        if var base = Self.per100(food) {
            base.mealType = slot.mealType
            portionFor = base
        } else {
            log(food)
        }
    }

    /// A scanned food as saved in your lists is the portion you logged ("148 kcal,
    /// 38 g"). Rebuilt per 100 g from its weight so the portion controls can scale
    /// it; nil when it isn't a scanned food or has no weight.
    private static func per100(_ food: FoodItem) -> FoodItem? {
        guard food.barcode != nil, let g = PortionMath.grams(inServing: food.servingSize),
              let kcal = PortionMath.per100(food.calories, servingGrams: g) else { return nil }
        var base = food
        base.calories = kcal
        base.protein = PortionMath.per100(food.protein, servingGrams: g) ?? 0
        base.carbs = PortionMath.per100(food.carbs, servingGrams: g) ?? 0
        base.fat = PortionMath.per100(food.fat, servingGrams: g) ?? 0
        base.servingSize = "\(PortionEditor.text(g)) g"
        return base
    }

    private func log(_ food: FoodItem) {
        var item = food
        item.mealType = slot.mealType
        onLog(item)
        dismiss()
    }

    private static func unique(_ list: [FoodItem]) -> [FoodItem] {
        var seen = Set<String>()
        return list.filter { seen.insert($0.name.lowercased()).inserted }
    }
}
