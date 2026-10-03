import SwiftUI

/// Edit a logged food (Nutrition rows and Today's timeline): name, serving,
/// meal, time, amount and nutrition. Saves under the same id.
struct FoodEditSheet: View {
    let original: FoodItem
    /// The edited item and the Amount factor (the v2 amounts scale by it).
    var onSave: (FoodItem, Double) -> Void
    var onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var serving: String
    @State private var slot: ExperienceMealSlot
    @State private var time: Date
    /// Multiplies every number below. Edits to a number are kept per 1×.
    @State private var amount: Double = 1
    @State private var kcal: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var confirmDelete = false

    init(item: FoodItem, onSave: @escaping (FoodItem, Double) -> Void, onDelete: @escaping () -> Void) {
        original = item
        self.onSave = onSave
        self.onDelete = onDelete
        _name = State(initialValue: item.name)
        _serving = State(initialValue: item.servingSize)
        _slot = State(initialValue: ExperienceMealSlot(item.mealType))
        _time = State(initialValue: item.timestamp)
        _kcal = State(initialValue: item.calories)
        _protein = State(initialValue: item.protein)
        _carbs = State(initialValue: item.carbs)
        _fat = State(initialValue: item.fat)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Food", text: $name)
                    TextField("Serving, e.g. 1 katori", text: $serving)
                }
                Section {
                    Picker("Meal", selection: $slot) {
                        ForEach(ExperienceMealSlot.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
                Section {
                    Stepper(value: $amount, in: 0.25...10, step: 0.25) {
                        HStack {
                            Text("Amount")
                            Spacer()
                            Text("\(Self.amountText(amount))×").monospacedDigit().foregroundStyle(.lx(.textSecondary))
                        }
                    }
                    .accessibilityValue("\(Self.amountText(amount)) times")
                } footer: {
                    Text("Scales the calories and macros together.")
                }
                Section("Nutrition") {
                    numberRow("Calories", unit: "kcal", value: scaled($kcal))
                    numberRow("Protein", unit: "g", value: scaled($protein))
                    numberRow("Carbs", unit: "g", value: scaled($carbs))
                    numberRow("Fat", unit: "g", value: scaled($fat))
                }
                Section {
                    Button("Delete this food", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle("Edit food")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(edited, amount); dismiss() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
            .confirmationDialog("Delete \(original.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { onDelete(); dismiss() }
            }
        }
    }

    private func numberRow(_ label: String, unit: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 120)
            Text(unit).foregroundStyle(.lx(.textSecondary)).frame(width: 32, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(unit)")
    }

    /// Shows `base × amount`; typing a number stores it back per 1×.
    private func scaled(_ base: Binding<Double>) -> Binding<Double> {
        Binding(get: { base.wrappedValue * amount },
                set: { base.wrappedValue = max(0, $0) / amount })
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && [kcal, protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 }
    }

    private var edited: FoodItem {
        var item = original
        item.name = name.trimmingCharacters(in: .whitespaces)
        let servingText = serving.trimmingCharacters(in: .whitespaces)
        item.servingSize = amount == 1 || servingText.isEmpty
            ? (servingText.isEmpty ? original.servingSize : servingText)
            : "\(Self.amountText(amount)) × \(servingText)"
        item.mealType = slot.mealType
        item.timestamp = Self.time(time, onDayOf: original.timestamp)
        item.calories = kcal * amount
        item.protein = protein * amount
        item.carbs = carbs * amount
        item.fat = fat * amount
        return item
    }

    /// Keeps the entry on its own day; only the clock time changes.
    static func time(_ clock: Date, onDayOf day: Date, calendar: Calendar = .current) -> Date {
        let c = calendar.dateComponents([.hour, .minute], from: clock)
        return calendar.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0, second: 0, of: day) ?? day
    }

    static func amountText(_ a: Double) -> String {
        a.formatted(.number.precision(.fractionLength(0...2)))
    }
}
