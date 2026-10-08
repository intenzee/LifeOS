import PhotosUI
import SwiftUI

/// 3.5 Camera and meal result. A full-screen viewfinder with a soft circular guide,
/// then the "meal lift" while the estimate runs (copy that moves on, never a bare
/// spinner), then the proposal card with the photo on top and an honest source line.
///
/// All recognition, model fallback and learning stay in `MealScannerEngine` and
/// `MealLearningEngine`; this view only owns presentation and intent. Keys live in
/// AI & privacy, so the camera never asks for one.
struct MealPhotoView: View {
    let slot: ExperienceMealSlot
    let mealTargets: (protein: Double, carbs: Double, fat: Double)
    var onLog: (FoodItem) -> Void
    var onSavePreset: (FoodItem) -> Void

    struct Scan: Equatable {
        var analysis: MealAnalysis
        /// The first estimate, the baseline the learning loop compares against.
        let original: MealAnalysis
        var signature: ImageSignature?
        var degraded: MealScanError?
        var note: String?

        static func == (a: Scan, b: Scan) -> Bool {
            a.analysis == b.analysis && a.original == b.original && a.degraded == b.degraded && a.note == b.note
        }
    }

    private enum Stage: Equatable {
        case starting, blocked(CameraAccess), camera, analyzing, result, failed(String)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lxTheme) private var theme
    @State private var stage: Stage = .starting
    @State private var camera = MealCamera()
    @State private var cameraGranted = false
    @State private var flash = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var scan: Scan?
    @State private var version = 0
    @State private var mealSlot: ExperienceMealSlot = .lunch
    @State private var progressStep = 0
    @State private var work: Task<Void, Never>?
    @State private var refining = false
    @State private var refineError: String?
    @State private var canRefine = false
    @State private var hasCloudKey = false
    @State private var showKeys = false
    @State private var showLearned = false
    @State private var shutterTick = 0

    private let engine = MealScannerEngine()

    var body: some View {
        ZStack {
            switch stage {
            case .starting:
                LXLight.scrim.ignoresSafeArea()
            case .blocked(let access):
                LXScreenBackground(heroGlow: false).ignoresSafeArea()
                VStack(spacing: 0) {
                    bar(title: "Photo", onDark: false)
                    CameraBlockedState(access: access, purpose: "photograph your meals")
                    galleryButton(prominent: true).padding(LX.Space.s500)
                }
            case .camera:
                cameraStage
            case .analyzing:
                analyzingStage
            case .result:
                resultStage
            case .failed(let message):
                failedStage(message)
            }
        }
        .lxHaptic(.scanLocked, trigger: shutterTick)
        .lxAnimation(.smooth, value: stage)
        .task { await start() }
        .onDisappear {
            work?.cancel()
            camera.stop()
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { @MainActor in
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    analyze(image)
                }
            }
        }
        .sheet(isPresented: $showKeys, onDismiss: { Task { await refreshAI() } }) {
            AIPrivacyScreen()
        }
        .fullScreenCover(isPresented: $showLearned) {
            LearnedCorrectionsView(isPresented: $showLearned)
        }
    }

    // MARK: Camera

    private var cameraStage: some View {
        ZStack {
            LXLight.scrim.ignoresSafeArea()
            CameraPreview(session: camera.session).ignoresSafeArea().accessibilityHidden(true)
            GeometryReader { geo in
                let d = min(geo.size.width * 0.8, 360)
                Circle()
                    .stroke(LXLight.onScrim.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [7, 7]))
                    .frame(width: d, height: d)
                    .position(x: geo.size.width / 2, y: geo.size.height * 0.45)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            VStack(spacing: LX.Space.s300) {
                bar(title: "Photo", onDark: true)
                Label("Include your hand or a fork for size", systemImage: "hand.raised")
                    .lxFont(.footnote).foregroundStyle(.lx(.textPrimary))
                    .padding(.horizontal, LX.Space.s300).padding(.vertical, LX.Space.s200)
                    .lxGlass(in: Capsule())
                Spacer()
                HStack {
                    galleryButton(prominent: false)
                    Spacer()
                    shutter
                    Spacer()
                    if camera.hasFlash {
                        CameraControl(systemImage: flash ? "bolt.fill" : "bolt.slash.fill",
                                      label: flash ? "Flash on" : "Flash off", isOn: flash) { flash.toggle() }
                    } else {
                        Color.clear.frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
                    }
                }
                .padding(.horizontal, LX.Space.s700)
                .padding(.bottom, LX.Space.s500)
            }
        }
    }

    private var shutter: some View {
        Button {
            shutterTick += 1
            Task { @MainActor in
                if let image = await camera.capture(flash: flash) { analyze(image) }
                else { stage = .failed("The camera didn't take that photo. Try again.") }
            }
        } label: {
            ZStack {
                Circle().strokeBorder(LXLight.onScrim, lineWidth: 4).frame(width: 78, height: 78)
                Circle().fill(LXLight.onScrim).frame(width: 64, height: 64)
            }
            .contentShape(Circle())
        }
        .buttonStyle(ShutterPressStyle())
        .accessibilityLabel("Take photo")
    }

    @ViewBuilder private func galleryButton(prominent: Bool) -> some View {
        if prominent {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.lx(.primary))
        } else {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Image(systemName: "photo.on.rectangle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.lx(.textPrimary))
                    .frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
                    .lxGlass(in: Circle(), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose a photo")
        }
    }

    private func bar(title: String, onDark: Bool) -> some View {
        HStack {
            CameraControl(systemImage: "xmark", label: "Close") { dismiss() }
            Spacer()
            Text(title).lxFont(.headline)
                .foregroundStyle(onDark ? AnyShapeStyle(LXLight.onScrim) : AnyShapeStyle(.lx(.textPrimary)))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Menu {
                Button { showLearned = true } label: { Label("Learned corrections", systemImage: "graduationcap") }
                Button { showKeys = true } label: { Label("AI and keys", systemImage: "key") }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.lx(.textPrimary))
                    .frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
                    .lxGlass(in: Circle(), interactive: true)
            }
            .accessibilityLabel("More")
        }
        .padding(.horizontal, LX.Space.s400)
        .padding(.top, LX.Space.s200)
    }

    // MARK: Analyzing (meal lift)

    private static let progressCopy = ["Looking at your plate…", "Estimating portions…", "Almost done"]

    private var analyzingStage: some View {
        ZStack {
            LXScreenBackground(heroGlow: true).ignoresSafeArea()
            VStack(spacing: LX.Space.s600) {
                Spacer()
                if let photo {
                    LXPhotoCard(image: Image(uiImage: photo), lifted: true)
                        .frame(height: 340)
                        .padding(.horizontal, LX.Space.s500)
                }
                HStack(spacing: LX.Space.s300) {
                    ProgressView()
                    Text(Self.progressCopy[min(progressStep, Self.progressCopy.count - 1)])
                        .lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                        .contentTransition(.opacity)
                        .id(progressStep)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Button("Cancel") { cancelAnalysis() }.buttonStyle(.lx(.plain)).padding(.bottom, LX.Space.s500)
            }
        }
    }

    // MARK: Result

    @ViewBuilder private var resultStage: some View {
        if let photo, let scan {
            ZStack(alignment: .top) {
                LXScreenBackground(heroGlow: false).ignoresSafeArea()
                VStack(spacing: 0) {
                    LXSheetHeader(title: "Check and log", onClose: { dismiss() })
                    ScrollView {
                        MealPhotoResult(photo: photo, scan: scan, mealSlot: $mealSlot, mealTargets: mealTargets,
                                        canRefine: canRefine, hasCloudKey: hasCloudKey, refining: refining,
                                        refineError: refineError,
                                        onRefine: refine, onLog: log, onSavePreset: onSavePreset,
                                        onRetake: retake, onAddKey: { showKeys = true })
                            .id(version)
                            .padding(LX.Space.s400)
                    }
                    .scrollDismissesKeyboard(.interactively)
                }
            }
        }
    }

    private func failedStage(_ message: String) -> some View {
        ZStack {
            LXScreenBackground(heroGlow: false).ignoresSafeArea()
            VStack(spacing: LX.Space.s500) {
                bar(title: "Photo", onDark: false)
                Spacer()
                if let photo {
                    LXPhotoCard(image: Image(uiImage: photo), lifted: false).frame(height: 220).padding(.horizontal, LX.Space.s500)
                }
                LXInlineBanner(kind: .error, message: message).padding(.horizontal, LX.Space.s400)
                VStack(spacing: LX.Space.s300) {
                    if let photo {
                        Button { analyze(photo) } label: { Text("Try again").frame(maxWidth: .infinity) }
                            .buttonStyle(.lx(.primary))
                    }
                    Button { retake() } label: { Text(cameraGranted ? "Take another photo" : "Choose another photo").frame(maxWidth: .infinity) }
                        .buttonStyle(.lx(.secondary))
                }
                .padding(.horizontal, LX.Space.s400)
                Spacer()
            }
        }
    }

    // MARK: Flow

    private func start() async {
        guard stage == .starting else { return }
        mealSlot = slot
        await refreshAI()
        #if DEBUG
        // DEBUG-only fixture so the result can be reviewed on device without the camera.
        if ProcessInfo.processInfo.arguments.contains("LX_DEBUG_PHOTO_RESULT") {
            let a = MealAnalysis(name: "Chicken biryani with raita", calories: 640, protein: 32, carbs: 78, fat: 21,
                                 servingSize: "1 plate", confidence: 0.62, source: .onDevice,
                                 components: [.init(name: "Chicken biryani", calories: 540, protein: 28, carbs: 70, fat: 18),
                                              .init(name: "Raita", calories: 70, protein: 4, carbs: 6, fat: 3),
                                              .init(name: "Salad", calories: 30, protein: 0, carbs: 2, fat: 0)])
            photo = debugPlate()
            scan = Scan(analysis: a, original: a, signature: nil, degraded: nil)
            version += 1
            stage = .result
            return
        }
        #endif
        let access = await CameraAccess.request()
        cameraGranted = access == .granted
        if cameraGranted {
            camera.start()
            stage = .camera
        } else {
            stage = .blocked(access)
        }
    }

    private func refreshAI() async {
        let credentials = AIServices.shared.credentials
        hasCloudKey = credentials.apiKey(for: .groqBYOK) != nil || credentials.apiKey(for: .geminiBYOK) != nil
        canRefine = await AIServices.shared.gateway.availability(for: .mealPhotoRefine).primary != nil
    }

    private func analyze(_ image: UIImage) {
        work?.cancel()
        photo = image
        refineError = nil
        progressStep = 0
        stage = .analyzing
        camera.stop()
        work = Task { @MainActor in
            let ticker = Task { @MainActor in
                for delay in [2.5, 3.5] {
                    try? await Task.sleep(for: .seconds(delay))
                    guard !Task.isCancelled else { return }
                    progressStep += 1
                }
            }
            defer { ticker.cancel() }
            do {
                let outcome = try await engine.scan(image: image, groqKey: nil)
                guard !Task.isCancelled else { return }
                scan = Scan(analysis: outcome.analysis, original: outcome.analysis,
                            signature: outcome.signature, degraded: outcome.degradedFrom)
                version += 1
                stage = .result
            } catch let error as MealScanError {
                guard !Task.isCancelled, error != .cancelled else { return }
                stage = .failed(error.userMessage)
            } catch {
                guard !Task.isCancelled else { return }
                stage = .failed("Something went wrong. Check your connection and try again.")
            }
        }
    }

    private func cancelAnalysis() {
        work?.cancel()
        work = nil
        retake()
    }

    private func retake() {
        scan = nil
        photo = nil
        refineError = nil
        if cameraGranted {
            camera.start()
            stage = .camera
        } else {
            stage = .blocked(.denied)
        }
    }

    /// Re-reads the same photo with the person's words ("it's egg fried rice, 4 eggs").
    private func refine(_ feedback: String) {
        guard let photo, let current = scan else { return }
        let note = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty else { return }
        refining = true
        refineError = nil
        Task { @MainActor in
            defer { refining = false }
            do {
                let outcome = try await engine.refine(image: photo, previous: current.analysis, feedback: note, groqKey: nil)
                scan?.analysis = outcome.analysis
                if let s = outcome.signature { scan?.signature = s }
                scan?.note = note
                scan?.degraded = nil
                version += 1
            } catch let error as MealScanError {
                refineError = error.userMessage
            } catch {
                refineError = "Couldn't apply that correction. Try again."
            }
        }
    }

    /// Logs and, when the person changed the first estimate (numbers, amount or
    /// words), files it as a correction so this dish scans right next time.
    private func log(_ food: FoodItem) {
        if let scan, let signature = scan.signature {
            let changed = Self.differs(food, from: scan.original) || (scan.note?.isEmpty == false)
            if changed {
                MealLearningEngine.shared.record(signature: signature, original: scan.original, corrected: food, note: scan.note)
            }
        }
        onLog(food)
        dismiss()
    }

    #if DEBUG
    /// A drawn plate standing in for a photo in DEBUG fixtures, in theme colours.
    private func debugPlate() -> UIImage {
        let c = { (role: LXColorRole) in UIColor(theme.color(role)) }
        return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 700)).image { ctx in
            c(.surface).setFill(); ctx.fill(CGRect(x: 0, y: 0, width: 900, height: 700))
            c(.textPrimary).setFill(); UIBezierPath(ovalIn: CGRect(x: 170, y: 70, width: 560, height: 560)).fill()
            c(.dataEnergy).setFill(); UIBezierPath(ovalIn: CGRect(x: 250, y: 160, width: 300, height: 260)).fill()
            c(.textSecondary).setFill(); UIBezierPath(ovalIn: CGRect(x: 500, y: 330, width: 160, height: 140)).fill()
            c(.statusOnTrack).setFill(); UIBezierPath(ovalIn: CGRect(x: 330, y: 430, width: 150, height: 110)).fill()
        }
    }
    #endif

    static func differs(_ food: FoodItem, from analysis: MealAnalysis) -> Bool {
        food.name.caseInsensitiveCompare(analysis.name) != .orderedSame
            || abs(food.calories - analysis.calories) >= 1
            || abs(food.protein - analysis.protein) >= 1
            || abs(food.carbs - analysis.carbs) >= 1
            || abs(food.fat - analysis.fat) >= 1
            || food.servingSize != analysis.servingSize
    }
}

// MARK: - Result content

/// The proposal for a photographed meal: photo, source line, items, amount,
/// meal, and "tell LifeOS what's off". Re-created (`.id`) after a refinement.
private struct MealPhotoResult: View {
    let photo: UIImage
    let scan: MealPhotoView.Scan
    @Binding var mealSlot: ExperienceMealSlot
    let mealTargets: (protein: Double, carbs: Double, fat: Double)
    let canRefine: Bool
    let hasCloudKey: Bool
    let refining: Bool
    let refineError: String?
    var onRefine: (String) -> Void
    var onLog: (FoodItem) -> Void
    var onSavePreset: (FoodItem) -> Void
    var onRetake: () -> Void
    var onAddKey: () -> Void

    @State private var name: String
    @State private var kcal: Double
    @State private var protein: Double
    @State private var carbs: Double
    @State private var fat: Double
    @State private var quantity: Double
    @State private var baseQuantity: Double
    @State private var unit: String
    @State private var editing = false
    @State private var edited = false
    @State private var draft = Draft()
    @State private var feedback = ""
    @State private var savedPreset = false
    @State private var amountTick = 0

    private struct Draft { var name = "", kcal = "", protein = "", carbs = "", fat = "" }

    init(photo: UIImage, scan: MealPhotoView.Scan, mealSlot: Binding<ExperienceMealSlot>,
         mealTargets: (protein: Double, carbs: Double, fat: Double), canRefine: Bool, hasCloudKey: Bool,
         refining: Bool, refineError: String?, onRefine: @escaping (String) -> Void,
         onLog: @escaping (FoodItem) -> Void, onSavePreset: @escaping (FoodItem) -> Void,
         onRetake: @escaping () -> Void, onAddKey: @escaping () -> Void) {
        self.photo = photo
        self.scan = scan
        _mealSlot = mealSlot
        self.mealTargets = mealTargets
        self.canRefine = canRefine
        self.hasCloudKey = hasCloudKey
        self.refining = refining
        self.refineError = refineError
        self.onRefine = onRefine
        self.onLog = onLog
        self.onSavePreset = onSavePreset
        self.onRetake = onRetake
        self.onAddKey = onAddKey
        let a = scan.analysis
        _name = State(initialValue: a.name)
        _kcal = State(initialValue: a.calories.rounded())
        _protein = State(initialValue: a.protein.rounded())
        _carbs = State(initialValue: a.carbs.rounded())
        _fat = State(initialValue: a.fat.rounded())
        let amount = PortionMath.parseAmount(a.servingSize)
        _quantity = State(initialValue: amount.quantity)
        _baseQuantity = State(initialValue: amount.quantity)
        _unit = State(initialValue: amount.unit)
    }

    private var scale: Double { baseQuantity > 0 ? quantity / baseQuantity : 1 }
    private var totalKcal: Int { Int(max(0, kcal * scale).rounded()) }
    private var amountText: String { PortionMath.amountLabel(quantity: quantity, unit: unit) }

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s400) {
            LXPhotoCard(image: Image(uiImage: photo), lifted: false)
                .frame(height: 210)
            sourceLine
            banners
            if editing { editor } else {
                LXProposalCard(mealTitle: mealSlot.title,
                               time: Date().formatted(date: .omitted, time: .shortened),
                               source: lxSource,
                               items: items,
                               macros: [
                                   .init(name: "Protein", grams: protein * scale, target: mealTargets.protein, role: .dataProtein),
                                   .init(name: "Carbs", grams: carbs * scale, target: mealTargets.carbs, role: .dataCarbs),
                                   .init(name: "Fat", grams: fat * scale, target: mealTargets.fat, role: .dataFat),
                               ],
                               note: confidence == .low ? "Check the amount." : nil,
                               onLog: { onLog(food) },
                               onEdit: beginEditing,
                               onSavePreset: savedPreset ? nil : { onSavePreset(food); savedPreset = true })
                if savedPreset {
                    Label("Saved as a preset", systemImage: "star.fill")
                        .lxFont(.footnote).foregroundStyle(.lx(.textSecondary)).frame(maxWidth: .infinity)
                }
                amountRow
                mealRow
                correction
            }
            Button("Retake", action: onRetake).buttonStyle(.lx(.plain)).frame(maxWidth: .infinity)
        }
        .lxHaptic(.selection, trigger: amountTick)
        .lxHaptic(.logged, trigger: savedPreset)
    }

    // MARK: Pieces

    private var sourceLine: some View {
        Label(sourceText, systemImage: sourceIcon)
            .lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
            .accessibilityLabel("Source: \(sourceText)")
    }

    @ViewBuilder private var banners: some View {
        if let degraded = scan.degraded {
            LXInlineBanner(kind: .attention, message: "Quick estimate. Check the portions. \(degraded.userMessage)",
                           actionTitle: degraded == .authFailed ? "Check key" : nil, action: onAddKey)
        } else if scan.analysis.source == .onDevice && !hasCloudKey {
            LXInlineBanner(kind: .info, message: "Estimated on this iPhone. Add a free Groq or Gemini key for full macros.",
                           actionTitle: "Add key", action: onAddKey)
        }
        if let refineError {
            LXInlineBanner(kind: .error, message: refineError)
        }
    }

    private var amountRow: some View {
        HStack(spacing: LX.Space.s300) {
            Text("Amount").lxFont(.subhead).foregroundStyle(.lx(.textSecondary)).fixedSize()
            Spacer(minLength: 0)
            LXIconButton(systemImage: "minus", label: "Less", glass: false) { step(-1) }
                .disabled(quantity <= PortionMath.amountStep(unit: unit))
            Text(amountText).lxFont(.headline, numeric: true).foregroundStyle(.lx(.textPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(minWidth: 72)
                .accessibilityLabel("Amount, \(amountText)")
            LXIconButton(systemImage: "plus", label: "More", glass: false) { step(1) }
            Menu {
                ForEach(PortionMath.mealUnits, id: \.self) { u in
                    Button(u.capitalized) { unit = u; amountTick += 1 }
                }
            } label: {
                Image(systemName: "chevron.up.chevron.down").foregroundStyle(.lx(.accentPrimary))
                    .frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
            }
            .accessibilityLabel("Unit, \(unit)")
        }
        .padding(.horizontal, LX.Space.s300)
        .lxCard(padding: LX.Space.s200)
    }

    private var mealRow: some View {
        HStack {
            Text("Meal").lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
            Spacer()
            Menu {
                ForEach(ExperienceMealSlot.allCases, id: \.self) { s in
                    Button(s.title) { mealSlot = s }
                }
            } label: {
                LXChip(title: mealSlot.title, systemImage: mealSlot.systemImage, kind: .neutral, trailing: "Change")
            }
        }
    }

    private var correction: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            Text("Tell LifeOS what's off").lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.textSecondary))
            TextField("e.g. It's egg fried rice, I added 4 eggs", text: $feedback, axis: .vertical)
                .lxFont(.body)
                .lineLimit(1...3)
                .submitLabel(.done)
                .padding(.horizontal, LX.Space.s400)
                .padding(.vertical, LX.Space.s300)
                .background(RoundedRectangle(cornerRadius: LX.Radius.tile, style: .continuous).fill(.lx(.surfaceRaised)))
                .disabled(!canRefine)
            if canRefine {
                Button { onRefine(feedback) } label: {
                    Label(refining ? "Applying…" : "Apply", systemImage: "wand.and.stars").frame(maxWidth: .infinity)
                }
                .buttonStyle(.lx(.secondary, loading: refining))
                .disabled(refining || feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                HStack(alignment: .firstTextBaseline) {
                    Text("Corrections in words need a free Groq or Gemini key. You can still edit the numbers.")
                        .lxFont(.footnote).foregroundStyle(.lx(.textTertiary))
                    Button("Add key", action: onAddKey).buttonStyle(.lx(.plain))
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: LX.Space.s400) {
            Text("Fix the numbers").lxFont(.title3).foregroundStyle(.lx(.textPrimary))
            Text("For \(amountText).").lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
            LXTextField(label: "What is it?", text: $draft.name, placeholder: "Meal name")
            LXTextField(label: "Calories", text: $draft.kcal, placeholder: "0", unit: "kcal", isNumeric: true)
            LXTileRow {
                LXTextField(label: "Protein", text: $draft.protein, placeholder: "0", unit: "g", isNumeric: true)
                LXTextField(label: "Carbs", text: $draft.carbs, placeholder: "0", unit: "g", isNumeric: true)
                LXTextField(label: "Fat", text: $draft.fat, placeholder: "0", unit: "g", isNumeric: true)
            }
            HStack(spacing: LX.Space.s300) {
                Button("Cancel") { editing = false }.buttonStyle(.lx(.secondary))
                Button { finishEditing() } label: { Text("Done").frame(maxWidth: .infinity) }
                    .buttonStyle(.lx(.primary))
                    .disabled(ManualFoodForm.number(draft.kcal) == nil)
            }
        }
        .lxCard(radius: LX.Radius.hero, padding: LX.Space.s500)
    }

    // MARK: Model

    /// What gets logged, at the chosen amount.
    private var food: FoodItem {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return FoodItem(name: clean.isEmpty ? "Meal" : clean,
                        calories: Double(totalKcal),
                        protein: max(0, protein * scale).rounded(),
                        carbs: max(0, carbs * scale).rounded(),
                        fat: max(0, fat * scale).rounded(),
                        servingSize: amountText,
                        mealType: mealSlot.mealType,
                        aiConfidence: scan.analysis.confidence)
    }

    /// The plate's parts when the estimate has them, scaled to add up to the
    /// total exactly (the card's "Log N kcal" must match what's logged).
    private var items: [LXProposalItem] {
        let parts = scan.analysis.components
        let sum = parts.reduce(0) { $0 + $1.calories }
        guard parts.count > 1, sum > 0, !edited else {
            return [LXProposalItem(id: "meal", name: name, amount: amountText, kcal: totalKcal, confidence: confidence)]
        }
        let k = Double(totalKcal) / sum
        var rows = parts.enumerated().map { i, part in
            LXProposalItem(id: "\(i)", name: part.name, amount: "", kcal: Int((part.calories * k).rounded()), confidence: confidence)
        }
        let drift = totalKcal - rows.reduce(0) { $0 + $1.kcal }
        rows[rows.count - 1].kcal += drift
        return rows
    }

    private var confidence: LXConfidence {
        let c = scan.analysis.confidence
        switch scan.analysis.source {
        case .learned: return .high
        case .onDevice: return c >= 0.45 ? .medium : .low
        default: return c >= 0.75 ? .high : (c >= 0.45 ? .medium : .low)
        }
    }

    private var lxSource: LXSource {
        switch scan.analysis.source {
        case .groq: return .groq
        case .gemini: return .gemini
        case .appleOnDevice, .onDevice: return .onDevice
        case .appleCloud, .learned: return .photo
        }
    }

    private var sourceText: String {
        switch scan.analysis.source {
        case .groq: return "Estimated with Groq, your free key"
        case .gemini: return "Estimated with Gemini, your free key"
        case .appleOnDevice: return "Estimated on this iPhone by Apple Intelligence"
        case .appleCloud: return "Estimated with Apple Private Cloud Compute"
        case .onDevice: return "Estimated on this iPhone"
        case .learned: return "Matched your earlier correction"
        }
    }

    private var sourceIcon: String {
        switch scan.analysis.source {
        case .groq, .gemini: return "cloud"
        case .appleOnDevice: return "apple.intelligence"
        case .appleCloud: return "lock.icloud"
        case .onDevice: return "iphone"
        case .learned: return "graduationcap"
        }
    }

    private func step(_ direction: Double) {
        let s = PortionMath.amountStep(unit: unit)
        quantity = max(s, ((quantity + direction * s) * 100).rounded() / 100)
        amountTick += 1
    }

    /// Edits apply to the amount on screen, so fold the current scale in first.
    private func beginEditing() {
        kcal *= scale; protein *= scale; carbs *= scale; fat *= scale
        baseQuantity = quantity
        draft = Draft(name: name, kcal: Self.text(kcal), protein: Self.text(protein), carbs: Self.text(carbs), fat: Self.text(fat))
        editing = true
    }

    private func finishEditing() {
        let clean = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !clean.isEmpty { name = clean }
        kcal = ManualFoodForm.number(draft.kcal) ?? kcal
        protein = ManualFoodForm.number(draft.protein) ?? protein
        carbs = ManualFoodForm.number(draft.carbs) ?? carbs
        fat = ManualFoodForm.number(draft.fat) ?? fat
        edited = true
        editing = false
    }

    private static func text(_ v: Double) -> String { String(Int(v.rounded())) }
}

/// The shutter shrinks a little under the finger.
private struct ShutterPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
