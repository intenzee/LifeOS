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
    let selectedMeal: MealType
    let onFoodSelected: (FoodItem) -> Void

    @State private var searchText = ""
    @State private var showingCustomFood = false
    @State private var showPortionSelector = false
    @State private var scannedFood: FoodItem? = nil

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
                HStack {
                    Text("Add to \(selectedMeal.rawValue)")
                        .font(.headline)
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title2)
                    }
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

struct AIMealScanView: View {
    @Binding var isPresented: Bool
    let selectedMeal: MealType
    let apiClient: any APIClient
    let onFoodDetected: (FoodItem) -> Void

    @State private var selectedImage: UIImage?
    @State private var showImagePicker = false
    @State private var isAnalyzing = false
    @State private var detectedFood: FoodItem?
    @State private var showConfirmation = false
    @State private var apiKey = ""
    @State private var selectedAI: AIProvider = .chatgpt
    @State private var errorMessage: String? = nil

    enum AIProvider: String, CaseIterable {
        case chatgpt = "ChatGPT"
        case perplexity = "Perplexity"
    }

    private enum AIMealScanError: Error {
        case missingAPIKey
        case imageEncodingFailed
        case emptyResponse
        case invalidJSON
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            let message: Message
        }

        struct Message: Decodable {
            let content: String
        }

        let choices: [Choice]
    }

    private struct MealScanPayload: Decodable {
        let name: String?
        let calories: Double?
        let protein: Double?
        let carbs: Double?
        let fat: Double?
        let servingSize: String?
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                HStack {
                    Text("AI Meal Scanner")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)

                    Spacer()

                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title2)
                    }
                }

                Picker("AI Provider", selection: $selectedAI) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.rawValue).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 8) {
                    Text("\(selectedAI.rawValue) API Key")
                        .font(.caption)
                        .foregroundColor(.gray)

                    SecureField("Enter your API key", text: $apiKey)
                        .padding()
                        .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }

                Text("Get your API key from \(selectedAI == .chatgpt ? "platform.openai.com" : "perplexity.ai")")
                    .font(.caption)
                    .foregroundColor(ThemePalette.accent)

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
                    Button(action: { showImagePicker = true }) {
                        Label("Select Photo", systemImage: "photo")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                            .foregroundColor(.white)
                            .cornerRadius(12)
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
                    .background(selectedImage != nil && !apiKey.isEmpty ? ThemePalette.accent : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .disabled(selectedImage == nil || apiKey.isEmpty || isAnalyzing)
                }

                Spacer()
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(red: 0.1, green: 0.1, blue: 0.12))
            )
            .padding(.horizontal, 20)
            .padding(.vertical, 60)

            if showConfirmation, let food = detectedFood {
                FoodConfirmationView(
                    food: food,
                    isPresented: $showConfirmation,
                    onConfirm: {
                        onFoodDetected(food)
                        isPresented = false
                    }
                )
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(image: $selectedImage)
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

    private func analyzeImage() {
        guard let image = selectedImage else { return }
        isAnalyzing = true
        errorMessage = nil

        Task {
            do {
                let food = try await scanMeal(image: image)
                await MainActor.run {
                    detectedFood = food
                    showConfirmation = true
                    isAnalyzing = false
                }
            } catch {
                await MainActor.run {
                    isAnalyzing = false
                    errorMessage = message(for: error)
                }
            }
        }
    }

    private func scanMeal(image: UIImage) async throws -> FoodItem {
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            throw AIMealScanError.missingAPIKey
        }

        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw AIMealScanError.imageEncodingFailed
        }

        let base64Image = imageData.base64EncodedString()
        let prompt = """
        Analyze this food image and return ONLY a JSON object with this exact format (no markdown, no explanation):
        {
          "name": "Food name",
          "calories": 250,
          "protein": 20,
          "carbs": 30,
          "fat": 10,
          "servingSize": "1 cup"
        }
        """

        let content = try await requestChatCompletion(prompt: prompt, base64Image: base64Image)
        let payload = try parseFoodPayload(from: content)

        return FoodItem(
            name: payload.name ?? "Unknown Food",
            calories: payload.calories ?? 0,
            protein: payload.protein ?? 0,
            carbs: payload.carbs ?? 0,
            fat: payload.fat ?? 0,
            servingSize: payload.servingSize ?? "1 serving",
            mealType: selectedMeal
        )
    }

    private func requestChatCompletion(prompt: String, base64Image: String) async throws -> String {
        switch selectedAI {
        case .chatgpt:
            let url = URL(string: "https://api.openai.com/v1/chat/completions")!
            let body = try makeOpenAIRequestBody(prompt: prompt, base64Image: base64Image)
            let request = APIRequest<ChatCompletionResponse>(
                url: url,
                method: .post,
                headers: [
                    "Authorization": "Bearer \(apiKey)",
                    "Content-Type": "application/json"
                ],
                body: body
            )

            let response = try await apiClient.send(request)
            guard let content = response.choices.first?.message.content else {
                throw AIMealScanError.emptyResponse
            }
            return content

        case .perplexity:
            let url = URL(string: "https://api.perplexity.ai/chat/completions")!
            let body = try makePerplexityRequestBody(prompt: prompt)
            let request = APIRequest<ChatCompletionResponse>(
                url: url,
                method: .post,
                headers: [
                    "Authorization": "Bearer \(apiKey)",
                    "Content-Type": "application/json"
                ],
                body: body
            )

            let response = try await apiClient.send(request)
            guard let content = response.choices.first?.message.content else {
                throw AIMealScanError.emptyResponse
            }
            return content
        }
    }

    private func makeOpenAIRequestBody(prompt: String, base64Image: String) throws -> Data {
        let payload: [String: Any] = [
            "model": "gpt-4o",
            "messages": [
                [
                    "role": "user",
                    "content": [
                        ["type": "text", "text": prompt],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(base64Image)"]]
                    ]
                ]
            ],
            "max_tokens": 300
        ]

        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func makePerplexityRequestBody(prompt: String) throws -> Data {
        let payload: [String: Any] = [
            "model": "llama-3.1-sonar-large-128k-online",
            "messages": [
                ["role": "user", "content": prompt]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: payload)
    }

    private func parseFoodPayload(from response: String) throws -> MealScanPayload {
        let cleaned = extractJSONPayload(from: response)
        guard let data = cleaned.data(using: .utf8) else {
            throw AIMealScanError.invalidJSON
        }

        if let payload = try? JSONDecoder().decode(MealScanPayload.self, from: data) {
            return payload
        }

        if let payloads = try? JSONDecoder().decode([MealScanPayload].self, from: data),
           let first = payloads.first {
            return first
        }

        throw AIMealScanError.invalidJSON
    }

    private func extractJSONPayload(from text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("```") {
            let lines = trimmed.split(separator: "\n", omittingEmptySubsequences: false)
            var contentLines = lines
            if let first = contentLines.first, first.hasPrefix("```") {
                contentLines.removeFirst()
            }
            if let last = contentLines.last, last.hasPrefix("```") {
                contentLines.removeLast()
            }
            return contentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let start = trimmed.firstIndex(of: "["), let end = trimmed.lastIndex(of: "]") {
            return String(trimmed[start...end])
        }

        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            return String(trimmed[start...end])
        }

        return trimmed
    }

    private func message(for error: Error) -> String {
        if let error = error as? AIMealScanError {
            switch error {
            case .missingAPIKey:
                return "Please enter a valid API key."
            case .imageEncodingFailed:
                return "Could not process the selected image."
            case .emptyResponse:
                return "The AI service returned an empty response."
            case .invalidJSON:
                return "The AI response could not be parsed."
            }
        }

        return "Something went wrong. Please try again."
    }
}

struct FoodConfirmationView: View {
    let food: FoodItem
    @Binding var isPresented: Bool
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)

                Text("Food Detected!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                VStack(alignment: .leading, spacing: 12) {
                    infoRow("Name", food.name)
                    infoRow("Calories", "\(Int(food.calories)) kcal")
                    infoRow("Protein", "\(Int(food.protein))g")
                    infoRow("Carbs", "\(Int(food.carbs))g")
                    infoRow("Fat", "\(Int(food.fat))g")
                    infoRow("Serving", food.servingSize)
                }
                .padding()
                .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                .cornerRadius(12)

                HStack(spacing: 12) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(red: 0.2, green: 0.2, blue: 0.22))
                    .cornerRadius(10)

                    Button("Add to Log") {
                        onConfirm()
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .cornerRadius(10)
                }
            }
            .padding(30)
            .background(Color(red: 0.1, green: 0.1, blue: 0.12))
            .cornerRadius(20)
            .padding(.horizontal, 40)
        }
    }

    func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.gray)
            Spacer()
            Text(value)
                .foregroundColor(.white)
                .fontWeight(.semibold)
        }
    }
}

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = .photoLibrary
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
