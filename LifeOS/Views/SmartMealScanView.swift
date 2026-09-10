import SwiftUI

/// Free, on-device meal scanner. Take or pick a photo, Vision classifies it on
/// device (no key, no cost), you tap the correct food, and it's logged instantly.
struct SmartMealScanView: View {
    @Binding var isPresented: Bool
    let selectedMeal: MealType
    let apiClient: any APIClient
    let onFoodDetected: (FoodItem) -> Void

    @State private var image: UIImage?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var isClassifying = false
    @State private var candidates: [SmartMealScanner.Candidate] = []
    @State private var resolvingLabel: String?
    @State private var loggedFood: FoodItem?
    @State private var showAIScanner = false
    @State private var noMatches = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()

            VStack(spacing: 16) {
                header

                if let loggedFood {
                    loggedCard(loggedFood)
                } else {
                    imageArea
                    if isClassifying {
                        ProgressView("Recognizing…")
                            .tint(.white).foregroundColor(.white)
                    } else if !candidates.isEmpty {
                        candidateList
                    } else if noMatches {
                        noMatchView
                    } else {
                        captureButtons
                    }
                }

                Spacer(minLength: 0)
                footer
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 22).fill(Color(red: 0.1, green: 0.1, blue: 0.12)))
            .padding(.horizontal, 16)
            .padding(.vertical, 44)
        }
        .sheet(isPresented: $showCamera) { ImagePicker(image: $image, sourceType: .camera) }
        .sheet(isPresented: $showLibrary) { ImagePicker(image: $image, sourceType: .photoLibrary) }
        .fullScreenCover(isPresented: $showAIScanner) {
            AIMealScanView(isPresented: $showAIScanner, selectedMeal: selectedMeal,
                           apiClient: apiClient, onFoodDetected: { food in
                onFoodDetected(food)
                isPresented = false
            })
        }
        .onChange(of: image) { _, newImage in
            guard newImage != nil else { return }
            classify()
        }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Smart Scan").font(.title2).fontWeight(.bold).foregroundColor(.white)
                Text("Free · on-device · \(selectedMeal.rawValue)")
                    .font(.caption).foregroundColor(.gray)
            }
            Spacer()
            Button { isPresented = false } label: {
                Image(systemName: "xmark.circle.fill").font(.title2).foregroundColor(.gray)
            }
        }
    }

    private var imageArea: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
                    .frame(height: 190).frame(maxWidth: .infinity).clipped()
                    .cornerRadius(16)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(ThemePalette.accent.opacity(0.5), lineWidth: 1))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 54)).foregroundColor(.gray)
                    Text("Snap or choose a meal photo").foregroundColor(.gray).font(.subheadline)
                }
                .frame(height: 190).frame(maxWidth: .infinity)
                .background(Color(red: 0.15, green: 0.15, blue: 0.17)).cornerRadius(16)
            }
        }
    }

    private var captureButtons: some View {
        HStack(spacing: 12) {
            Button { showCamera = true } label: {
                Label("Camera", systemImage: "camera.fill").frame(maxWidth: .infinity).padding()
                    .background(ThemePalette.accent).foregroundColor(.white).cornerRadius(12)
            }
            Button { showLibrary = true } label: {
                Label("Library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity).padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.22)).foregroundColor(.white).cornerRadius(12)
            }
        }
    }

    private var candidateList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Tap what it is — it'll log instantly")
                .font(.caption).foregroundColor(.gray)
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(candidates) { candidate in
                        Button { pick(candidate) } label: {
                            HStack {
                                Text(candidate.label).foregroundColor(.white).fontWeight(.medium)
                                Spacer()
                                if resolvingLabel == candidate.label {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("\(Int(candidate.confidence * 100))%")
                                        .font(.caption).foregroundColor(ThemePalette.accent)
                                    Image(systemName: "plus.circle.fill").foregroundColor(ThemePalette.accent)
                                }
                            }
                            .padding(.vertical, 12).padding(.horizontal, 14)
                            .background(Color(red: 0.15, green: 0.15, blue: 0.17)).cornerRadius(12)
                        }
                        .disabled(resolvingLabel != nil)
                    }
                }
            }
            .frame(maxHeight: 210)

            Button { retake() } label: {
                Label("Retake photo", systemImage: "arrow.counterclockwise")
                    .font(.footnote).foregroundColor(.gray)
            }
        }
    }

    private var noMatchView: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.circle").font(.system(size: 40)).foregroundColor(.gray)
            Text("Couldn't recognize the food").foregroundColor(.white).font(.subheadline)
            Text("Try a clearer, closer photo — or use AI for tricky/mixed meals.")
                .font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
            Button { retake() } label: {
                Label("Try again", systemImage: "arrow.counterclockwise").frame(maxWidth: .infinity).padding()
                    .background(ThemePalette.accent).foregroundColor(.white).cornerRadius(12)
            }
        }
    }

    private func loggedCard(_ food: FoodItem) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundColor(.green)
            Text("Logged").font(.title3).fontWeight(.bold).foregroundColor(.white)
            VStack(spacing: 6) {
                Text(food.name).font(.headline).foregroundColor(.white)
                Text("\(Int(food.calories)) kcal · \(Int(food.protein))P / \(Int(food.carbs))C / \(Int(food.fat))F")
                    .font(.caption).foregroundColor(.gray)
                Text(food.servingSize).font(.caption2).foregroundColor(.gray)
            }
            .padding().frame(maxWidth: .infinity)
            .background(Color(red: 0.15, green: 0.15, blue: 0.17)).cornerRadius(12)

            HStack(spacing: 12) {
                Button { retake() } label: {
                    Label("Scan another", systemImage: "camera").frame(maxWidth: .infinity).padding()
                        .background(Color(red: 0.2, green: 0.2, blue: 0.22)).foregroundColor(.white).cornerRadius(12)
                }
                Button { isPresented = false } label: {
                    Text("Done").frame(maxWidth: .infinity).padding()
                        .background(ThemePalette.accent).foregroundColor(.white).cornerRadius(12)
                }
            }
        }
    }

    private var footer: some View {
        Button { showAIScanner = true } label: {
            Label("Use AI for mixed meals (needs key)", systemImage: "sparkles")
                .font(.caption).foregroundColor(ThemePalette.accent)
        }
    }

    // MARK: - Actions

    private func classify() {
        guard let image else { return }
        isClassifying = true
        noMatches = false
        candidates = []
        Task {
            let found = await SmartMealScanner.classify(image)
            await MainActor.run {
                candidates = found
                noMatches = found.isEmpty
                isClassifying = false
            }
        }
    }

    private func pick(_ candidate: SmartMealScanner.Candidate) {
        resolvingLabel = candidate.label
        Task {
            let food = await SmartMealScanner.resolveNutrition(for: candidate,
                                                               mealType: selectedMeal,
                                                               apiClient: apiClient)
            await MainActor.run {
                onFoodDetected(food)          // auto-log
                loggedFood = food
                resolvingLabel = nil
            }
        }
    }

    private func retake() {
        image = nil
        candidates = []
        loggedFood = nil
        noMatches = false
    }
}
