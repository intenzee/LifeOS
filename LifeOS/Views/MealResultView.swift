import SwiftUI

/// The AI meal result screen — view, set the **portion**, **correct in plain
/// English**, or fine-tune the numbers, then log.
///
/// This is the human-in-the-loop surface of the learning system:
///  • **Amount** lets the user express the real serving (bowl / cup / plate /
///    grams / pieces …) and the macros scale live.
///  • **"Tell the AI what's off"** sends the photo, the current estimate, and the
///    user's words (e.g. "it's egg fried rice, I added 4 eggs") back to the model,
///    which recomputes the macros — no manual math needed.
///  • **Fix numbers manually** is the fallback for direct edits.
/// Whatever the user changes, the parent records it as a training signal so the
/// scanner gets this dish right next time.
struct MealResultView: View {
    let analysis: MealAnalysis
    let mealType: MealType
    let degradedNote: String?
    /// True while an AI text-correction is in flight.
    let isRefining: Bool
    /// Whether a Groq key is present (AI corrections need one).
    let canRefineWithAI: Bool
    @Binding var isPresented: Bool
    /// Ask the AI to recompute using the user's words.
    let onRefine: (String) -> Void
    /// Log the final food.
    let onLog: (FoodItem) -> Void
    /// Focus the correction box on appear (used by UI screenshot harness).
    var autoFocusFeedback: Bool = false

    // Editable numbers are the base (per the detected amount); the Amount control
    // scales them for display and logging.
    @State private var editing = false
    @State private var name: String
    @State private var baseCalories: Double
    @State private var baseProtein: Double
    @State private var baseCarbs: Double
    @State private var baseFat: Double

    // Portion.
    @State private var quantity: Double
    @State private var baseQuantity: Double
    @State private var unit: String

    // Text correction.
    @State private var feedbackText: String = ""

    @FocusState private var focusedField: Field?
    private enum Field { case name, calories, protein, carbs, fat, feedback }

    private static let units = ["serving", "bowl", "cup", "plate", "piece",
                                "glass", "slice", "handful", "gram", "oz", "tbsp"]

    init(analysis: MealAnalysis,
         mealType: MealType,
         degradedNote: String? = nil,
         isRefining: Bool = false,
         canRefineWithAI: Bool = true,
         isPresented: Binding<Bool>,
         onRefine: @escaping (String) -> Void,
         onLog: @escaping (FoodItem) -> Void,
         autoFocusFeedback: Bool = false) {
        self.analysis = analysis
        self.mealType = mealType
        self.degradedNote = degradedNote
        self.isRefining = isRefining
        self.canRefineWithAI = canRefineWithAI
        self._isPresented = isPresented
        self.onRefine = onRefine
        self.onLog = onLog
        self.autoFocusFeedback = autoFocusFeedback

        _name = State(initialValue: analysis.name)
        _baseCalories = State(initialValue: analysis.calories.rounded())
        _baseProtein = State(initialValue: analysis.protein.rounded())
        _baseCarbs = State(initialValue: analysis.carbs.rounded())
        _baseFat = State(initialValue: analysis.fat.rounded())

        let parsed = Self.parsePortion(analysis.servingSize)
        _quantity = State(initialValue: parsed.quantity)
        _baseQuantity = State(initialValue: parsed.quantity)
        _unit = State(initialValue: parsed.unit)
    }

    // Live-scaled values.
    private var scale: Double { baseQuantity > 0 ? quantity / baseQuantity : 1 }
    private var calories: Double { baseCalories * scale }
    private var protein: Double { baseProtein * scale }
    private var carbs: Double { baseCarbs * scale }
    private var fat: Double { baseFat * scale }

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.45).ignoresSafeArea())
                .onTapGesture { focusedField = nil }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 18) {
                        header
                        if editing {
                            editForm.id("editForm")
                        } else {
                            summary
                            amountControl
                            aiCorrectionBox.id("aiBox")
                        }
                        actionButtons
                        // Bottom spacer so the last field can scroll clear of the keyboard.
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(24)
                    .glassCard(cornerRadius: 28, elevation: 1.3)
                    .padding(.horizontal, 20)
                    .padding(.top, 36)
                    .padding(.bottom, 12)
                }
                .scrollDismissesKeyboard(.interactively)
                .onAppear {
                    guard autoFocusFeedback else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focusedField = .feedback }
                }
                .onChange(of: focusedField) { _, field in
                    guard let field else { return }
                    // Wait for the keyboard to raise, then reveal the active field.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(field == .feedback ? "aiBox" : "bottom", anchor: .bottom)
                        }
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focusedField = nil }
                    .fontWeight(.semibold)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [ThemePalette.accent, ThemePalette.accentSecondary],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 54, height: 54)
                    .shadow(color: ThemePalette.accent.opacity(0.5), radius: 12, y: 6)
                Image(systemName: editing ? "pencil" : "checkmark")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black.opacity(0.85))
            }

            Label(sourceLabel, systemImage: sourceIcon)
                .font(.caption2.weight(.semibold))
                .foregroundColor(ThemePalette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(ThemePalette.accent.opacity(0.14), in: Capsule(style: .continuous))

            if let degradedNote {
                Text(degradedNote)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Summary (read-only)

    private var summary: some View {
        VStack(spacing: 14) {
            Text(name)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            if !analysis.components.isEmpty {
                Text(analysis.components.map(\.name).joined(separator: " · "))
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 2) {
                Text("\(Int(calories.rounded()))")
                    .font(.system(size: 44, weight: .heavy, design: .rounded))
                    .foregroundColor(ThemePalette.accent)
                Text("kcal")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.gray)
            }

            HStack(spacing: 10) {
                macroTile("Protein", protein, Color(red: 0.44, green: 0.93, blue: 0.78))
                macroTile("Carbs", carbs, Color(red: 1.0, green: 0.78, blue: 0.35))
                macroTile("Fat", fat, Color(red: 0.55, green: 0.60, blue: 0.98))
            }
        }
    }

    // MARK: - Amount / portion

    private var amountControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Amount")
                .font(.caption.weight(.semibold))
                .foregroundColor(.gray)

            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    stepButton("minus") { setQuantity(quantity - stepSize) }
                    Text(formatted(quantity))
                        .font(.system(.body, design: .rounded).weight(.semibold))
                        .foregroundColor(.white)
                        .frame(minWidth: 44)
                    stepButton("plus") { setQuantity(quantity + stepSize) }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                Menu {
                    ForEach(Self.units, id: \.self) { u in
                        Button(u.capitalized) { unit = u }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(unit.capitalized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    // MARK: - AI text correction

    private var aiCorrectionBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tell the AI what's off", systemImage: "text.bubble.fill")
                .font(.caption.weight(.semibold))
                .foregroundColor(ThemePalette.accent)

            TextField("e.g. It's egg fried rice, I added 4 eggs", text: $feedbackText, axis: .vertical)
                .lineLimit(1...3)
                .focused($focusedField, equals: .feedback)
                .padding(12)
                .background(fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.white)

            Button {
                focusedField = nil
                onRefine(feedbackText)
            } label: {
                HStack {
                    if isRefining {
                        ProgressView().tint(.black.opacity(0.8))
                    } else {
                        Image(systemName: "wand.and.stars")
                    }
                    Text(isRefining ? "Applying…" : "Apply with AI")
                }
                .font(.subheadline.weight(.bold))
                .foregroundColor(.black.opacity(0.85))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    (canApplyAI ? AnyShapeStyle(LinearGradient(colors: [ThemePalette.accent, ThemePalette.accentSecondary],
                                                               startPoint: .leading, endPoint: .trailing))
                                : AnyShapeStyle(Color.gray)),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
            }
            .disabled(!canApplyAI)

            if !canRefineWithAI {
                Text("Add a free Groq key on the scan screen to use AI corrections. You can still edit the numbers manually below.")
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 2)
    }

    private var canApplyAI: Bool {
        canRefineWithAI && !isRefining &&
        !feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Manual edit form

    private var editForm: some View {
        VStack(spacing: 14) {
            fieldLabel("What is it, really?")
            TextField("Meal name", text: $name)
                .focused($focusedField, equals: .name)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.white)

            numberField("Calories (kcal)", value: $baseCalories, field: .calories)
            HStack(spacing: 10) {
                numberField("Protein (g)", value: $baseProtein, field: .protein)
                numberField("Carbs (g)", value: $baseCarbs, field: .carbs)
                numberField("Fat (g)", value: $baseFat, field: .fat)
            }

            amountControl

            Text("Tip: for ingredient changes like \"added 4 eggs\", the AI text box does the math for you.")
                .font(.caption2)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: 10) {
            if !editing {
                Button {
                    focusedField = nil
                    withAnimation { editing = true }
                } label: {
                    Label("Fix numbers manually", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(ThemePalette.accent)
                }
            }

            HStack(spacing: 12) {
                Button(editing ? "Back" : "Cancel") {
                    if editing { withAnimation { editing = false } } else { isPresented = false }
                }
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Button(editing ? "Save & Log" : "Add to Log") { log() }
                    .font(.subheadline.weight(.bold))
                    .foregroundColor(.black.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        LinearGradient(colors: [ThemePalette.accent, ThemePalette.accentSecondary],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }
        }
    }

    private func log() {
        focusedField = nil
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let food = FoodItem(
            name: cleanedName.isEmpty ? "Meal" : cleanedName,
            calories: max(0, calories.rounded()),
            protein: max(0, protein.rounded()),
            carbs: max(0, carbs.rounded()),
            fat: max(0, fat.rounded()),
            servingSize: servingLabel,
            mealType: mealType
        )
        onLog(food)
    }

    // MARK: - Small views & helpers

    private var stepSize: Double { unit == "gram" ? 25 : (unit == "oz" ? 1 : 0.5) }

    private func setQuantity(_ value: Double) {
        quantity = max(stepSize, (value * 100).rounded() / 100)
    }

    private var servingLabel: String {
        let q = formatted(quantity)
        let plural = (quantity != 1 && !["oz", "gram"].contains(unit)) ? "\(unit)s" : unit
        return unit == "gram" ? "\(q) g" : "\(q) \(plural)"
    }

    private func stepButton(_ system: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 26, height: 26)
                .background(ThemePalette.accent.opacity(0.85), in: Circle())
        }
    }

    private func macroTile(_ label: String, _ grams: Double, _ tint: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(grams.rounded()))g")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(tint)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(tint.opacity(0.3), lineWidth: 1)
        )
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(.gray)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numberField(_ label: String, value: Binding<Double>, field: Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .padding(12)
                .background(fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .foregroundColor(.white)
        }
    }

    private let fieldFill = Color(red: 0.15, green: 0.15, blue: 0.17)

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    /// Parses a serving string like "1 plate" / "2 cups" / "250 g" into a
    /// starting quantity and unit for the Amount control.
    static func parsePortion(_ serving: String) -> (quantity: Double, unit: String) {
        let lower = serving.lowercased()
        let number = lower
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .first(where: { !$0.isEmpty })
            .flatMap(Double.init) ?? 1
        let matched = units.first(where: { lower.contains($0) })
            ?? (lower.contains("g") ? "gram" : "serving")
        return (max(0.5, number), matched)
    }

    private var sourceLabel: String {
        switch analysis.source {
        case .groq: return "AI · full macros"
        case .gemini: return "AI · Gemini (your key)"
        case .appleOnDevice: return "Apple Intelligence · on-device"
        case .appleCloud: return "Apple Intelligence · Private Cloud"
        case .onDevice: return "On-device estimate"
        case .learned: return "Learned from your corrections"
        }
    }

    private var sourceIcon: String {
        switch analysis.source {
        case .groq, .gemini: return "sparkles"
        case .appleOnDevice: return "apple.intelligence"
        case .appleCloud: return "lock.icloud"
        case .onDevice: return "iphone"
        case .learned: return "graduationcap.fill"
        }
    }
}
