import SwiftUI
import UIKit
import Vision

/// Nutrition-label scanning (F04 §4.4): Vision text recognition + a
/// deterministic table parser. Fully on-device, no key, no network — works on
/// every iPhone.
struct LabelScanView: View {
    @Environment(\.dismiss) private var dismiss
    let meal: MealType
    let onLog: ([FoodItem], String) -> Void

    @State private var image: UIImage?
    @State private var showPicker = false
    @State private var pickerSource: UIImagePickerController.SourceType = .camera
    @State private var isReading = false
    @State private var facts: NutritionFacts?
    @State private var productName = ""
    @State private var byGrams = false
    @State private var servings = 1.0
    @State private var grams = 30.0
    @State private var saveAsCustom = true

    var body: some View {
        VStack(spacing: 0) {
            LXSheetHeader(title: "Scan a label", onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: LX.Space.s400) {
                    if isReading {
                        ProgressView("Reading the label on this iPhone…").frame(maxWidth: .infinity).padding(LX.Space.s600)
                    } else if let facts, facts.isUsable {
                        result(facts)
                    } else {
                        if facts != nil {
                            LXInlineBanner(kind: .attention,
                                           message: "Couldn't read the nutrition table. Try a straight, well-lit photo of just the panel.")
                        }
                        capture
                    }
                }
                .padding(LX.Space.s400)
            }
        }
        .background(.lx(.surfaceRaised), ignoresSafeAreaEdges: .all)
        .sheet(isPresented: $showPicker) {
            ImagePicker(image: $image, sourceType: pickerSource)
        }
        .onChange(of: image) { _, newImage in
            guard let newImage else { return }
            Task { await read(newImage) }
        }
    }

    private var capture: some View {
        VStack(spacing: LX.Space.s300) {
            LXEmptyState(systemImage: "text.viewfinder",
                         message: "Photograph the nutrition table on the pack. Everything is read on this iPhone.")
            HStack(spacing: LX.Space.s300) {
                Button {
                    pickerSource = .photoLibrary
                    showPicker = true
                } label: { Label("Library", systemImage: "photo").frame(maxWidth: .infinity) }
                    .buttonStyle(.lx(.secondary))
                Button {
                    pickerSource = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
                    showPicker = true
                } label: { Label("Camera", systemImage: "camera.fill").frame(maxWidth: .infinity) }
                    .buttonStyle(.lx(.primary))
            }
        }
    }

    private func result(_ facts: NutritionFacts) -> some View {
        let macros = amountMacros(facts) ?? .zero
        return VStack(alignment: .leading, spacing: LX.Space.s400) {
            LXTextField(label: "Product", text: $productName, placeholder: "e.g. Masala Munch")
            VStack(alignment: .leading, spacing: LX.Space.s100) {
                if let perServing = facts.perServing {
                    Text("Per serving\(facts.servingGrams.map { " (\(Int($0)) g)" } ?? ""): \(Int(perServing.kcal.rounded())) kcal")
                        .lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                }
                if let per100 = facts.per100g {
                    Text("Per 100 g: \(Int(per100.kcal.rounded())) kcal").lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                }
            }
            if facts.per100g != nil && facts.perServing != nil {
                LXSegmented(options: [(label: "Servings", value: false), (label: "Grams", value: true)], selection: $byGrams)
            }
            amountStepper(facts)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(Int(macros.kcal.rounded()))").lxFont(.displayL, numeric: true).foregroundStyle(.lx(.textPrimary))
                Text("kcal").lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                Spacer()
                LXConfidenceDot(confidence: facts.confidence >= 0.75 ? .high : facts.confidence >= 0.55 ? .medium : .low)
            }
            LXMacroBar(macros: [
                .init(name: "Protein", grams: macros.protein, target: 120, role: .dataProtein),
                .init(name: "Carbs", grams: macros.carbs, target: 250, role: .dataCarbs),
                .init(name: "Fat", grams: macros.fat, target: 70, role: .dataFat),
            ])
            if facts.confidence < 0.6 {
                LXInlineBanner(kind: .attention, message: "Some values may be misread. Check them against the pack.")
            }
            LXToggleRow(title: "Save to my foods", explanation: "So “1 packet of \(productName.isEmpty ? "it" : productName)” logs instantly next time",
                        isOn: $saveAsCustom)
            Button { log(facts, macros: macros) } label: {
                Text("Log \(Int(macros.kcal.rounded())) kcal").frame(maxWidth: .infinity)
            }
            .buttonStyle(.lx(.primary))
            Button("Scan another") { reset() }.buttonStyle(.lx(.plain)).frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func amountStepper(_ facts: NutritionFacts) -> some View {
        let usesGrams = byGrams || facts.perServing == nil && facts.servingGrams == nil
        HStack {
            Text(usesGrams ? "\(Int(grams)) g" : "\(servings.formatted()) serving\(servings == 1 ? "" : "s")")
                .lxFont(.title2, numeric: true)
            Spacer()
            Stepper("", onIncrement: {
                if usesGrams { grams += 10 } else { servings += 0.5 }
            }, onDecrement: {
                if usesGrams { grams = max(5, grams - 10) } else { servings = max(0.5, servings - 0.5) }
            })
            .labelsHidden()
        }
        .lxCard()
    }

    private func amountMacros(_ facts: NutritionFacts) -> Macros? {
        let usesGrams = byGrams || facts.perServing == nil && facts.servingGrams == nil
        return usesGrams ? facts.macros(grams: grams) : facts.macros(servings: servings)
    }

    private func read(_ image: UIImage) async {
        isReading = true
        defer { isReading = false }
        let lines = await Self.recognizeLines(in: image)
        let parsed = NutritionLabelParser.parse(lines: lines)
        facts = parsed
        productName = parsed.productName ?? ""
        grams = parsed.servingGrams ?? 30
        servings = 1
        byGrams = parsed.perServing == nil && parsed.servingGrams == nil
    }

    private func log(_ facts: NutritionFacts, macros: Macros) {
        let name = productName.trimmingCharacters(in: .whitespaces).isEmpty ? "Packaged food" : productName
        let usesGrams = byGrams || facts.perServing == nil && facts.servingGrams == nil
        let serving = usesGrams ? "\(Int(grams)) g" : "\(servings.formatted()) serving\(servings == 1 ? "" : "s")"
        let food = FoodItem(name: name, calories: macros.kcal.rounded(), protein: macros.protein, carbs: macros.carbs,
                            fat: macros.fat, servingSize: serving, mealType: meal, source: .photoAI,
                            aiConfidence: facts.confidence)
        if saveAsCustom, let perServing = facts.perServing ?? facts.per100g {
            let basis = facts.perServing != nil ? "1 serving\(facts.servingGrams.map { " (\(Int($0)) g)" } ?? "")" : "100 g"
            FoodDatabaseManager.shared.addCustomFood(FoodItem(name: name, calories: perServing.kcal.rounded(),
                                                              protein: perServing.protein, carbs: perServing.carbs,
                                                              fat: perServing.fat, servingSize: basis, mealType: meal))
        }
        onLog([food], "Logged \(name) · \(Int(macros.kcal.rounded())) kcal")
        dismiss()
    }

    private func reset() {
        facts = nil
        image = nil
        productName = ""
    }

    /// Vision OCR → reading-order lines.
    static func recognizeLines(in image: UIImage) async -> [String] {
        guard let cgImage = MealImageProcessor.uprightCGImage(image) else { return [] }
        return await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false     // numbers matter more than words
            request.recognitionLanguages = ["en-US", "en-IN"]
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            try? handler.perform([request])
            let fragments = (request.results ?? []).compactMap { observation -> OCRLineAssembler.Fragment? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                let box = observation.boundingBox
                return OCRLineAssembler.Fragment(text: text, minX: box.minX, midY: box.midY, height: box.height)
            }
            return OCRLineAssembler.lines(from: fragments)
        }.value
    }
}
