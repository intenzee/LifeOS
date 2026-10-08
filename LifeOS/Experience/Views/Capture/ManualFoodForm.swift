import SwiftUI

/// 3.7 "Enter it yourself": a food typed from the pack, per serving. When the
/// serving weight is given and the food came from a barcode, the caller can
/// cache it per 100 g so the next scan of that code resolves instantly.
struct ManualFoodForm: View {
    let slot: ExperienceMealSlot
    var barcode: String? = nil
    var initialName = ""
    var onSave: (_ food: FoodItem, _ servingGrams: Double?) -> Void
    var onCancel: () -> Void

    @State private var name = ""
    @State private var serving = "1 serving"
    @State private var gramsText = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var carbsText = ""
    @State private var fatText = ""
    @State private var tried = false

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s400) {
            VStack(alignment: .leading, spacing: LX.Space.s100) {
                Text("Enter it yourself").lxFont(.title3).foregroundStyle(.lx(.textPrimary))
                Text(barcode == nil ? "From the pack, for one serving." : "From the pack, for one serving. Next time this barcode is known.")
                    .lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
            }
            LXTextField(label: "Name", text: $name, placeholder: "e.g. Masala oats",
                        error: tried && trimmedName.isEmpty ? "Add a name." : nil)
            LXTileRow {
                LXTextField(label: "Serving", text: $serving, placeholder: "1 pack")
                LXTextField(label: "Weight", text: $gramsText, placeholder: "Optional", unit: "g", isNumeric: true)
            }
            LXTextField(label: "Calories", text: $kcalText, placeholder: "0", unit: "kcal",
                        error: tried && kcal == nil ? "Add the calories." : nil, isNumeric: true)
            LXTileRow {
                LXTextField(label: "Protein", text: $proteinText, placeholder: "0", unit: "g", isNumeric: true)
                LXTextField(label: "Carbs", text: $carbsText, placeholder: "0", unit: "g", isNumeric: true)
                LXTextField(label: "Fat", text: $fatText, placeholder: "0", unit: "g", isNumeric: true)
            }
            HStack(spacing: LX.Space.s300) {
                Button("Cancel", action: onCancel).buttonStyle(.lx(.secondary))
                Button { save() } label: {
                    Text(kcal.map { "Save and log \(Int($0.rounded())) kcal" } ?? "Save and log").frame(maxWidth: .infinity)
                }
                .buttonStyle(.lx(.primary))
            }
        }
        .onAppear { if name.isEmpty { name = initialName } }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var kcal: Double? { Self.number(kcalText) }

    private func save() {
        tried = true
        guard !trimmedName.isEmpty, let kcal else { return }
        let grams = Self.number(gramsText).flatMap { $0 > 0 ? $0 : nil }
        let servingText = serving.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = servingText.isEmpty ? "1 serving" : servingText
        let food = FoodItem(name: String(trimmedName.prefix(80)), calories: kcal,
                            protein: Self.number(proteinText) ?? 0, carbs: Self.number(carbsText) ?? 0,
                            fat: Self.number(fatText) ?? 0,
                            servingSize: grams.map { "\(label) (\(PortionEditor.text($0)) g)" } ?? label,
                            barcode: barcode, mealType: slot.mealType)
        onSave(food, grams)
    }

    /// A non-negative number typed with either decimal separator.
    static func number(_ text: String) -> Double? {
        guard let v = Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")),
              v.isFinite, v >= 0 else { return nil }
        return v
    }
}
