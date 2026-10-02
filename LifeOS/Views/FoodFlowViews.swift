import SwiftUI
import AVFoundation
import PhotosUI
import AudioToolbox

struct MealDetailView: View {
    @Binding var foodLog: DailyFoodLog
    @Binding var isPresented: Bool
    let selectedDate: Date
    let onDateChange: (Date) -> Void
    let onAddFood: (MealType) -> Void

    var displayDate: String {
        let formatter = DateFormatter()

        if Calendar.current.isDateInToday(selectedDate) {
            return "Today's Meals"
        } else if Calendar.current.isDateInYesterday(selectedDate) {
            return "Yesterday's Meals"
        } else if Calendar.current.isDateInTomorrow(selectedDate) {
            return "Tomorrow's Meals"
        } else {
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: selectedDate) + " Meals"
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        HStack {
                            Button(action: {
                                let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate)!
                                onDateChange(yesterday)
                            }) {
                                Image(systemName: "chevron.left.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(ThemePalette.accent)
                            }

                            Spacer()

                            VStack(spacing: 4) {
                                Text(displayDate)
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)

                                Text("\(Int(foodLog.totalCalories())) calories")
                                    .font(.subheadline)
                                    .foregroundColor(ThemePalette.accent)
                            }

                            Spacer()

                            Button(action: {
                                let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate)!
                                onDateChange(tomorrow)
                            }) {
                                Image(systemName: "chevron.right.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(ThemePalette.accent)
                            }
                        }

                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                                .font(.title2)
                        }
                    }

                    HStack(spacing: 16) {
                        macroCard("Protein", foodLog.totalProtein(), "g", .green)
                        macroCard("Carbs", foodLog.totalCarbs(), "g", .orange)
                        macroCard("Fat", foodLog.totalFat(), "g", .red)
                    }

                    mealSection("Breakfast", .breakfast, foodLog.breakfast)
                    mealSection("Lunch", .lunch, foodLog.lunch)
                    mealSection("Dinner", .dinner, foodLog.dinner)
                    mealSection("Snacks", .snacks, foodLog.snacks)

                    Spacer(minLength: 40)
                }
                .padding(24)
            }
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 60)
        }
    }

    func macroCard(_ label: String, _ value: Double, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(Int(value))\(unit)")
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
        )
    }

    func mealSection(_ title: String, _ mealType: MealType, _ foods: [FoodItem]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)

                Spacer()

                Button(action: { onAddFood(mealType) }) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(ThemePalette.accent)
                }
            }

            if foods.isEmpty {
                Text("No items added")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 8) {
                    ForEach(foods) { food in
                        foodRow(food)
                    }
                }
            }

            Text("\(Int(foods.reduce(0) { $0 + $1.calories })) cal")
                .font(.caption)
                .foregroundColor(ThemePalette.accent)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
        )
    }

    func foodRow(_ food: FoodItem) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name)
                    .font(.subheadline)
                    .foregroundColor(.white)

                Text(food.servingSize)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            Text("\(Int(food.calories)) cal")
                .font(.caption)
                .foregroundColor(ThemePalette.accent)

            Button(action: {
                FoodDatabaseManager.shared.removeFood(food.id)
            }) {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundColor(.red.opacity(0.7))
            }
        }
    }
}

struct FoodSearchView: View {
    @Binding var isPresented: Bool
    let onFoodSelected: (FoodItem) -> Void
    @Environment(\.colorScheme) private var colorScheme

    /// Editable within the view. Seeded from the caller's smart default (time of
    /// day) but the user can switch meals here without leaving the screen.
    @State private var selectedMeal: MealType

    @State private var searchText = ""
    @State private var showingCustomFood = false
    @State private var showPortionSelector = false
    @State private var scannedFood: FoodItem? = nil

    init(isPresented: Binding<Bool>, selectedMeal: MealType, onFoodSelected: @escaping (FoodItem) -> Void) {
        _isPresented = isPresented
        _selectedMeal = State(initialValue: selectedMeal)
        self.onFoodSelected = onFoodSelected
    }

    private var palette: ThemePalette { ThemePalette(colorScheme: colorScheme) }

    var filteredFoods: [FoodItem] {
        let foods = FoodDatabaseManager.shared.allFoods

        if searchText.isEmpty {
            return foods
        } else {
            return foods.filter {
                $0.name.lowercased().contains(searchText.lowercased())
            }
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 0) {
                VStack(spacing: 12) {
                    HStack {
                        Text("Add Meal")
                            .font(.system(.headline, design: .rounded).weight(.bold))
                            .foregroundColor(.white)

                        Spacer()

                        Button(action: { isPresented = false }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.gray)
                                .frame(width: 32, height: 32)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                    }

                    mealTypeSelector
                }
                .padding()
                .background(Color(red: 0.12, green: 0.12, blue: 0.14))

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)

                    TextField("Search foods...", text: $searchText)
                        .foregroundColor(.white)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding()
                .background(Color(red: 0.15, green: 0.15, blue: 0.17))

                HStack(spacing: 0) {
                    tabButton("Common", true)
                    tabButton("Recent", false)
                    tabButton("Favorites", false)
                }
                .background(Color(red: 0.12, green: 0.12, blue: 0.14))

                Divider().background(Color.gray.opacity(0.3))

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(filteredFoods) { food in
                            foodSearchRow(food)
                        }

                        Button(action: { showingCustomFood = true }) {
                            HStack {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(ThemePalette.accent)
                                Text("Add Custom Food")
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
                            )
                        }
                    }
                    .padding()
                }
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            }
            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            .cornerRadius(20)
            .padding(.horizontal, 20)
            .padding(.vertical, 60)

            if showingCustomFood {
                CustomFoodView(
                    isPresented: $showingCustomFood,
                    mealType: selectedMeal,
                    barcode: nil,
                    onSave: { food in
                        FoodDatabaseManager.shared.addCustomFood(food)
                        onFoodSelected(food)
                        isPresented = false
                    }
                )
            }

            if showPortionSelector, let food = scannedFood {
                PortionSizeSelectorView(
                    isPresented: $showPortionSelector,
                    baseFood: food,
                    onConfirm: { scaledFood in
                        onFoodSelected(scaledFood)
                        isPresented = false
                    }
                )
            }
        }
    }

    /// Pill selector for the meal type, preselected by the caller's time-based default.
    private var mealTypeSelector: some View {
        HStack(spacing: 8) {
            ForEach(MealType.allCases, id: \.self) { meal in
                let isSelected = meal == selectedMeal
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        selectedMeal = meal
                    }
                } label: {
                    Text(meal.rawValue)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundColor(isSelected ? .black : .white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            ZStack {
                                if isSelected {
                                    Capsule().fill(ThemePalette.accent)
                                } else {
                                    Capsule().fill(.ultraThinMaterial)
                                }
                            }
                        )
                }
            }
        }
    }

    func tabButton(_ title: String, _ isSelected: Bool) -> some View {
        Button(action: {}) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(isSelected ? .blue : .gray)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? Color(red: 0.15, green: 0.15, blue: 0.17) : Color.clear)
        }
    }

    func foodSearchRow(_ food: FoodItem) -> some View {
        Button(action: {
            var selectedFood = food
            selectedFood.mealType = selectedMeal

            if food.barcode != nil {
                scannedFood = selectedFood
                showPortionSelector = true
            } else {
                onFoodSelected(selectedFood)
                isPresented = false
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(food.name)
                        .font(.subheadline)
                        .foregroundColor(.white)

                    HStack(spacing: 8) {
                        Text("\(Int(food.calories)) cal")
                            .font(.caption)
                            .foregroundColor(ThemePalette.accent)
                        Text("•")
                            .foregroundColor(.gray)
                        Text(food.servingSize)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .foregroundColor(ThemePalette.accent)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
            )
        }
    }
}

struct CustomFoodView: View {
    @Binding var isPresented: Bool
    let mealType: MealType
    let barcode: String?
    let onSave: (FoodItem) -> Void

    @State private var foodName: String
    @State private var calories: String
    @State private var protein: String
    @State private var carbs: String
    @State private var fat: String
    @State private var servingSize: String

    init(
        isPresented: Binding<Bool>,
        mealType: MealType,
        barcode: String? = nil,
        initialFoodName: String = "",
        initialCalories: String = "",
        initialProtein: String = "",
        initialCarbs: String = "",
        initialFat: String = "",
        initialServingSize: String = "",
        onSave: @escaping (FoodItem) -> Void
    ) {
        self._isPresented = isPresented
        self.mealType = mealType
        self.barcode = barcode
        self.onSave = onSave
        self._foodName = State(initialValue: initialFoodName)
        self._calories = State(initialValue: initialCalories)
        self._protein = State(initialValue: initialProtein)
        self._carbs = State(initialValue: initialCarbs)
        self._fat = State(initialValue: initialFat)
        self._servingSize = State(initialValue: initialServingSize)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Add Custom Food")
                    .font(.headline)
                    .foregroundColor(.white)

                if let barcode {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Detected Barcode")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(barcode)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                            .cornerRadius(10)
                    }
                }

                TextField("Food name", text: $foodName)
                    .padding()
                    .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                    .foregroundColor(.white)
                    .cornerRadius(10)

                HStack(spacing: 12) {
                    TextField("Calories", text: $calories)
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                        .foregroundColor(.white)
                        .cornerRadius(10)

                    TextField("Protein (g)", text: $protein)
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                HStack(spacing: 12) {
                    TextField("Carbs (g)", text: $carbs)
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                        .foregroundColor(.white)
                        .cornerRadius(10)

                    TextField("Fat (g)", text: $fat)
                        .keyboardType(.decimalPad)
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                TextField("Serving size", text: $servingSize)
                    .padding()
                    .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                    .foregroundColor(.white)
                    .cornerRadius(10)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .cornerRadius(10)

                    Button("Save") {
                        let food = FoodItem(
                            name: foodName.isEmpty ? (barcode != nil ? "Unrecognized Item" : "Custom Food") : foodName,
                            calories: Double(calories) ?? 0,
                            protein: Double(protein) ?? 0,
                            carbs: Double(carbs) ?? 0,
                            fat: Double(fat) ?? 0,
                            servingSize: servingSize.isEmpty ? "1 serving" : servingSize,
                            barcode: barcode,
                            mealType: mealType
                        )
                        onSave(food)
                        isPresented = false
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ThemePalette.accent)
                    .cornerRadius(10)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .padding(.horizontal, 40)
        }
    }
}

struct BarcodeUnrecognizedPromptView: View {
    @Binding var isPresented: Bool
    let barcode: String
    let onRetryScan: () -> Void
    let onLogManually: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.85)
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 54))
                    .foregroundColor(.orange)

                Text("Barcode Unrecognized")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(barcode)
                    .font(.caption)
                    .foregroundColor(.gray)

                Text("You can log it manually and save it for future use.")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)

                HStack(spacing: 12) {
                    Button("Retry Scan") {
                        onRetryScan()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .cornerRadius(10)

                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .cornerRadius(10)

                    Button("Log Manually") {
                        onLogManually()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ThemePalette.accent)
                    .cornerRadius(10)
                }
            }
            .padding(28)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .padding(.horizontal, 36)
        }
    }
}

struct BarcodeScannerView: View {
    @Binding var isPresented: Bool
    let selectedMeal: MealType
    let onBarcodeScanned: (String) -> Void

    var body: some View {
        ZStack {
            BarcodeScannerRepresentable(onBarcodeScanned: { barcode in
                onBarcodeScanned(barcode)
                isPresented = false
            })
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                            .padding()
                    }
                }

                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "barcode.viewfinder")
                        .font(.system(size: 60))
                        .foregroundColor(.white)

                    Text("Scan Barcode")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("Align barcode within the frame")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(30)
                .background(
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.black.opacity(0.7))
                )
                .padding(.bottom, 100)
            }
        }
    }
}

struct BarcodeScannerRepresentable: UIViewControllerRepresentable {
    let onBarcodeScanned: (String) -> Void

    func makeUIViewController(context: Context) -> BarcodeScannerViewController {
        let controller = BarcodeScannerViewController()
        controller.onBarcodeScanned = onBarcodeScanned
        return controller
    }

    func updateUIViewController(_ uiViewController: BarcodeScannerViewController, context: Context) {}
}

class BarcodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession?
    var previewLayer: AVCaptureVideoPreviewLayer?
    var onBarcodeScanned: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupCamera()
    }

    func setupCamera() {
        captureSession = AVCaptureSession()

        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if (captureSession?.canAddInput(videoInput) ?? false) {
            captureSession?.addInput(videoInput)
        } else {
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if (captureSession?.canAddOutput(metadataOutput) ?? false) {
            captureSession?.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.ean8, .ean13, .pdf417, .upce, .code128, .code39]
        } else {
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession!)
        previewLayer?.frame = view.layer.bounds
        previewLayer?.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer!)

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession?.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if (captureSession?.isRunning == true) {
            DispatchQueue.global(qos: .userInitiated).async {
                self.captureSession?.stopRunning()
            }
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }

            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onBarcodeScanned?(stringValue)
        }
    }
}

/// AI Meal Scanner.
///
/// Rebuilt on top of `MealScannerEngine`: the view owns only presentation and
/// user intent, while all recognition, networking, model-fallback, retry and
/// graceful degradation live in the engine. The old design hardcoded a single
/// Groq model that has since been decommissioned and dead-ended on any failure;
/// this one always produces a loggable result — full macros from Groq when a
/// free key is present, or an on-device estimate otherwise — so a scan can never
/// simply "not work".
struct AIMealScanView: View {
    @Binding var isPresented: Bool
    let selectedMeal: MealType
    /// Retained for source-compatibility with existing call sites. The scanner
    /// now uses its own `MealScannerEngine` for all networking.
    let apiClient: any APIClient
    let onFoodDetected: (FoodItem) -> Void

    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var imageSource: UIImagePickerController.SourceType = .camera
    @State private var isAnalyzing = false
    /// The current analysis to show/edit/log (updated by AI text refinements),
    /// the untouched first estimate (used as the learning baseline), and the
    /// photo fingerprint so a correction can be filed against this exact image.
    @State private var lastAnalysis: MealAnalysis?
    @State private var originalAnalysis: MealAnalysis?
    @State private var lastSignature: ImageSignature?
    @State private var lastFeedbackNote: String?
    /// Bumped whenever `lastAnalysis` is replaced so the result view re-seeds.
    @State private var analysisVersion = 0
    @State private var isRefining = false
    @State private var degradedNote: String?
    @State private var showConfirmation = false
    @State private var apiKey = ""
    @State private var errorMessage: String? = nil
    /// A saved key exists for the provider (entered once, kept in Keychain).
    @State private var hasStoredKey = false
    /// Force-show the key field even when a key is saved (user tapped "Change").
    @State private var editingKey = false
    /// One-time, persistent "how to get a free key" card.
    @State private var showInstructions = false
    @State private var showLearnedCorrections = false
    @FocusState private var keyFieldFocused: Bool

    private let providerName = "Groq"
    private let engine = MealScannerEngine()

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.35).ignoresSafeArea())

            ScrollView {
              VStack(spacing: 20) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [ThemePalette.accent, ThemePalette.accentSecondary],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 42, height: 42)
                        Image(systemName: "sparkles")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.black.opacity(0.8))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AI Meal Scanner")
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(.white)
                        Text("Full macros with Groq · free · always logs")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    Button(action: { showLearnedCorrections = true }) {
                        Image(systemName: "graduationcap.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(ThemePalette.accent)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(.gray)
                            .frame(width: 34, height: 34)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }

                if showInstructions {
                    instructionsCard
                }

                keySection

                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(ThemePalette.accent, lineWidth: 2)
                        )
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)

                        Text("No image selected")
                            .foregroundColor(.gray)
                    }
                    .frame(height: 250)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                    .cornerRadius(16)
                }

                HStack(spacing: 12) {
                    Button {
                        imageSource = .camera
                        showImagePicker = true
                    } label: {
                        Label("Take Photo", systemImage: "camera.fill")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(ThemePalette.accent.opacity(0.9))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }

                    Button {
                        imageSource = .photoLibrary
                        showImagePicker = true
                    } label: {
                        Label("Choose Photo", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                    }
                }

                Button(action: { analyzeImage() }) {
                    if isAnalyzing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Label("Analyze", systemImage: "sparkles")
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(canAnalyze ? ThemePalette.accent : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
                .disabled(!canAnalyze || isAnalyzing)

                if !hasStoredKey && apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No key? Analyze still works with a free on-device estimate.")
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
              }
              .padding(22)
              .glassCard(cornerRadius: 28, elevation: 1.1)
              .padding(.horizontal, 18)
              .padding(.vertical, 50)
            }

            if showConfirmation, let analysis = lastAnalysis {
                MealResultView(
                    analysis: analysis,
                    mealType: selectedMeal,
                    degradedNote: degradedNote,
                    isRefining: isRefining,
                    canRefineWithAI: hasAIKey,
                    isPresented: $showConfirmation,
                    onRefine: { feedback in refine(with: feedback) },
                    onLog: { food in logResult(food) }
                )
                .id(analysisVersion)
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage, sourceType: imageSource)
        }
        .fullScreenCover(isPresented: $showLearnedCorrections) {
            LearnedCorrectionsView(isPresented: $showLearnedCorrections)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { keyFieldFocused = false }
                    .fontWeight(.semibold)
            }
        }
        .onAppear {
            showInstructions = !AIKeyStore.shared.hasSeenInstructions
            loadStoredKey()
        }
        .alert("Meal Scan Failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    // MARK: - Derived UI state

    /// An image is all that's required — with a key we use Groq, without one we
    /// fall back to a free on-device estimate, so Analyze is never blocked by a
    /// missing key.
    private var canAnalyze: Bool {
        selectedImage != nil
    }

    private var providerSite: String { "console.groq.com/keys" }

    // MARK: - Key & instructions UI

    /// One-time, persistent card explaining how to get a free Groq key. Dismissed
    /// state is remembered in `AIKeyStore`, so it never nags after the first view.
    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Set up free AI scanning (once)", systemImage: "info.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ThemePalette.accent)
                Spacer()
                Button {
                    AIKeyStore.shared.hasSeenInstructions = true
                    withAnimation { showInstructions = false }
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.gray)
                }
            }
            Text("""
            1. Go to console.groq.com and sign in (Google/GitHub works).
            2. Open "API Keys" → "Create API Key".
            3. Copy the key (starts with "gsk_") and paste it below.
            4. It's free, and you only do this once — we save it securely on this device.
            """)
            .font(.caption2)
            .foregroundColor(.gray)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(ThemePalette.accent.opacity(0.12))
        )
    }

    @ViewBuilder
    private var keySection: some View {
        if hasStoredKey && !editingKey {
            HStack {
                Image(systemName: "checkmark.seal.fill").foregroundColor(.green)
                Text("\(providerName) key saved")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Button("Change") { editingKey = true }
                    .font(.caption.weight(.semibold))
                    .foregroundColor(ThemePalette.accent)
            }
            .padding()
            .background(Color(red: 0.15, green: 0.15, blue: 0.17))
            .cornerRadius(10)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(providerName) API Key (optional)")
                    .font(.caption)
                    .foregroundColor(.gray)

                SecureField("Paste your key (gsk_…)", text: $apiKey)
                    .focused($keyFieldFocused)
                    .submitLabel(.done)
                    .onSubmit { keyFieldFocused = false }
                    .padding()
                    .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                    .foregroundColor(.white)
                    .cornerRadius(10)

                Text("Get a free key at \(providerSite) for full-plate macros — saved once, securely on this device.")
                    .font(.caption2)
                    .foregroundColor(ThemePalette.accent)
            }
        }
    }

    private func loadStoredKey() {
        if let saved = AIKeyStore.shared.load(provider: providerName) {
            apiKey = saved
            hasStoredKey = true
            editingKey = false
        } else {
            apiKey = ""
            hasStoredKey = false
            editingKey = true
        }
    }

    // MARK: - Analysis

    private func analyzeImage() {
        guard let image = selectedImage else { return }
        isAnalyzing = true
        errorMessage = nil
        degradedNote = nil

        let typedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let outcome = try await engine.scan(image: image, groqKey: typedKey)
                await MainActor.run {
                    applyOutcome(outcome, typedKey: typedKey)
                    isAnalyzing = false
                }
            } catch let error as MealScanError {
                await MainActor.run {
                    isAnalyzing = false
                    errorMessage = error.userMessage
                    if error == .authFailed { forgetKey() }
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    errorMessage = "Something went wrong. Please check your connection and try again."
                }
            }
        }
    }

    private func applyOutcome(_ outcome: MealScanOutcome, typedKey: String) {
        // If Groq actually produced the result, the key is valid — persist it so
        // it's a one-time entry, and retire the instructions card for good.
        if outcome.analysis.source == .groq, !typedKey.isEmpty {
            AIKeyStore.shared.save(typedKey, provider: providerName)
            AIKeyStore.shared.hasSeenInstructions = true
            hasStoredKey = true
            editingKey = false
            showInstructions = false
        }

        lastAnalysis = outcome.analysis
        originalAnalysis = outcome.analysis   // learning baseline for this scan
        lastSignature = outcome.signature
        lastFeedbackNote = nil
        analysisVersion += 1
        degradedNote = nil

        if let degraded = outcome.degradedFrom {
            degradedNote = degraded.userMessage
            // A rejected key shouldn't stay saved — prompt a fresh entry.
            if degraded == .authFailed { forgetKey() }
        }

        showConfirmation = true
    }

    /// A Groq key is available (typed or stored) — required for AI text refine.
    private var hasAIKey: Bool {
        hasStoredKey || !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Re-analyses the same photo with the user's natural-language correction,
    /// then swaps in the corrected estimate (the result view re-seeds via `.id`).
    private func refine(with feedback: String) {
        guard let image = selectedImage,
              let previous = lastAnalysis else { return }
        let note = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }

        isRefining = true
        Task {
            do {
                let outcome = try await engine.refine(image: image,
                                                      previous: previous,
                                                      feedback: note,
                                                      groqKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                await MainActor.run {
                    lastAnalysis = outcome.analysis
                    if outcome.signature != nil { lastSignature = outcome.signature }
                    lastFeedbackNote = note
                    analysisVersion += 1
                    isRefining = false
                }
            } catch let error as MealScanError {
                await MainActor.run {
                    isRefining = false
                    errorMessage = error.userMessage
                    if error == .authFailed { forgetKey() }
                }
            } catch {
                await MainActor.run {
                    isRefining = false
                    errorMessage = "Couldn't apply that correction. Please try again."
                }
            }
        }
    }

    /// Logs the final food and, when it differs from the first estimate (a manual
    /// edit, a portion change, or an AI text refinement), records it as a learned
    /// correction so future scans of this dish improve.
    private func logResult(_ food: FoodItem) {
        if let baseline = originalAnalysis, let signature = lastSignature {
            let changed = foodDiffers(food, from: baseline) || (lastFeedbackNote?.isEmpty == false)
            if changed {
                MealLearningEngine.shared.record(signature: signature,
                                                 original: baseline,
                                                 corrected: food,
                                                 note: lastFeedbackNote)
            }
        }
        onFoodDetected(food)
        isPresented = false
    }

    private func foodDiffers(_ food: FoodItem, from analysis: MealAnalysis) -> Bool {
        food.name.caseInsensitiveCompare(analysis.name) != .orderedSame
            || abs(food.calories - analysis.calories) >= 1
            || abs(food.protein - analysis.protein) >= 1
            || abs(food.carbs - analysis.carbs) >= 1
            || abs(food.fat - analysis.fat) >= 1
            || food.servingSize != analysis.servingSize
    }

    /// Drops any stored key and reopens the key field for re-entry.
    private func forgetKey() {
        AIKeyStore.shared.delete(provider: providerName)
        hasStoredKey = false
        editingKey = true
        apiKey = ""
    }
}


struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    var sourceType: UIImagePickerController.SourceType = .photoLibrary
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        // Fall back to the library if the requested source (e.g. camera) is unavailable.
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(sourceType) ? sourceType : .photoLibrary
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.image = image
            }
            parent.dismiss()
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

struct PortionSizeSelectorView: View {
    @Binding var isPresented: Bool
    let baseFood: FoodItem
    let onConfirm: (FoodItem) -> Void

    @State private var portionGrams: Double = 100
    @State private var customInput: String = "100"
    @FocusState private var isInputFocused: Bool

    let commonPortions: [(String, Double)] = [
        ("50g", 50),
        ("100g", 100),
        ("150g", 150),
        ("200g", 200),
        ("250g", 250),
        ("500g", 500)
    ]

    var scaledFood: FoodItem {
        baseFood.scaled(toGrams: portionGrams)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()
                .onTapGesture {
                    hideKeyboard()
                }

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("Set Portion Size")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Text(baseFood.name)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Quick Select")
                        .font(.caption)
                        .foregroundColor(.gray)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(commonPortions, id: \.0) { portion in
                            Button(action: {
                                portionGrams = portion.1
                                customInput = String(Int(portion.1))
                                hideKeyboard()
                            }) {
                                Text(portion.0)
                                    .font(.subheadline)
                                    .fontWeight(portionGrams == portion.1 ? .bold : .regular)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 10)
                                            .fill(portionGrams == portion.1 ? ThemePalette.accent : Color(red: 0.2, green: 0.2, blue: 0.22))
                                    )
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Custom Amount (grams)")
                        .font(.caption)
                        .foregroundColor(.gray)

                    HStack {
                        TextField("Grams", text: $customInput)
                            .keyboardType(.numberPad)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                            .cornerRadius(10)
                            .focused($isInputFocused)
                            .onChange(of: customInput) { _, newValue in
                                if let grams = Double(newValue), grams > 0 {
                                    portionGrams = grams
                                }
                            }
                            .toolbar {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") {
                                        hideKeyboard()
                                    }
                                    .foregroundColor(ThemePalette.accent)
                                }
                            }

                        Text("g")
                            .foregroundColor(.gray)
                            .padding(.trailing, 8)
                    }
                }

                VStack(spacing: 12) {
                    Text("Nutrition for \(Int(portionGrams))g")
                        .font(.headline)
                        .foregroundColor(.white)

                    HStack(spacing: 16) {
                        nutrientBadge("Calories", Int(scaledFood.calories), "kcal", .orange)
                        nutrientBadge("Protein", Int(scaledFood.protein), "g", .green)
                    }

                    HStack(spacing: 16) {
                        nutrientBadge("Carbs", Int(scaledFood.carbs), "g", .blue)
                        nutrientBadge("Fat", Int(scaledFood.fat), "g", .red)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(red: 0.15, green: 0.15, blue: 0.17))
                )

                HStack(spacing: 12) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .cornerRadius(10)

                    Button("Add Food") {
                        hideKeyboard()
                        onConfirm(scaledFood)
                        isPresented = false
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(ThemePalette.accent)
                    .cornerRadius(10)
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .padding(.horizontal, 40)
        }
    }

    func nutrientBadge(_ label: String, _ value: Int, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(value)\(unit)")
                .font(.headline)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.14))
        )
    }
}
