import SwiftUI

/// 3.6 Barcode and nutrition label. Live camera with the code outlined, a haptic
/// and auto-capture on lock; the product slides up as a card over the frozen
/// camera with the 3.7 portion controls. A code that isn't in the database offers
/// "Scan the nutrition label instead" (on-device text recognition) or typing it in,
/// rather than the old dead-end prompt.
struct BarcodeCaptureView: View {
    let slot: ExperienceMealSlot
    let apiClient: any APIClient
    let mealTargets: (protein: Double, carbs: Double, fat: Double)
    var onLog: (FoodItem) -> Void
    var onSaveCustom: (FoodItem) -> Void
    var onFavorite: (FoodItem) -> Void

    private enum Stage: Equatable {
        case starting
        case blocked(CameraAccess)
        case scanning
        case typing
        case lookingUp(String)
        case found(String)
        case notFound(String)
        case manual(String?)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var stage: Stage = .starting
    @State private var product: FoodItem?
    /// A product the database knows by name but without nutrition facts.
    @State private var nameOnly: String?
    @State private var torchOn = false
    @State private var typedCode = ""
    @State private var labelFor: String?
    @State private var lockTick = 0
    @State private var cameraReady = false

    var body: some View {
        ZStack {
            LXLight.scrim.ignoresSafeArea()
            if cameraReady {
                BarcodeScannerSurface(isScanning: stage == .scanning, onCode: locked)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            if case .blocked(let access) = stage {
                LXScreenBackground(heroGlow: false).ignoresSafeArea()
                VStack(spacing: 0) {
                    topBar
                    CameraBlockedState(access: access, purpose: "scan barcodes",
                                       alternativeTitle: "Type the number instead", onAlternative: { stage = .typing })
                }
            } else {
                if stage == .scanning { guide }
                VStack(spacing: 0) {
                    topBar
                    Spacer()
                    if stage == .scanning { scanningHint }
                }
                if let panel = panelStage { panelOverlay(panel) }
            }
        }
        .lxHaptic(.scanLocked, trigger: lockTick)
        .lxAnimation(.smooth, value: stage)
        .task { await start() }
        .onDisappear { if torchOn { CameraTorch.set(false) } }
        .sheet(item: Binding(get: { labelFor.map(LabelTarget.init) }, set: { labelFor = $0?.code })) { target in
            LabelScanView(meal: slot.mealType) { foods, _ in
                labelFor = nil
                for var food in foods {
                    food.barcode = target.code
                    onLog(food)
                }
                if !foods.isEmpty { dismiss() }
            }
            .lxSheetStyle(detents: [.large])
        }
    }

    private struct LabelTarget: Identifiable { let code: String; var id: String { code } }

    // MARK: Chrome

    private var topBar: some View {
        HStack {
            CameraControl(systemImage: "xmark", label: "Close") { dismiss() }
            Spacer()
            Text("Scan a barcode").lxFont(.headline).foregroundStyle(LXLight.onScrim)
                .shadow(color: LXLight.scrim.opacity(0.5), radius: 4)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if CameraTorch.isAvailable, cameraReady {
                CameraControl(systemImage: torchOn ? "flashlight.on.fill" : "flashlight.off.fill",
                              label: torchOn ? "Turn torch off" : "Turn torch on", isOn: torchOn) {
                    torchOn.toggle()
                    CameraTorch.set(torchOn)
                }
            } else {
                Color.clear.frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
            }
        }
        .padding(.horizontal, LX.Space.s400)
        .padding(.top, LX.Space.s200)
    }

    /// Corner brackets marking where to hold the code; VisionKit draws the live outline.
    private var guide: some View {
        GeometryReader { geo in
            let w = min(geo.size.width * 0.78, 340), h = w * 0.56
            ViewfinderBrackets()
                .stroke(LXLight.onScrim.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .frame(width: w, height: h)
                .position(x: geo.size.width / 2, y: geo.size.height * 0.42)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var scanningHint: some View {
        VStack(spacing: LX.Space.s300) {
            Text("Hold the barcode inside the frame. It scans by itself.")
                .lxFont(.callout).foregroundStyle(.lx(.textPrimary)).multilineTextAlignment(.center)
            Button { stage = .typing } label: {
                Label("Type the number", systemImage: "keyboard").frame(maxWidth: .infinity)
            }
            .buttonStyle(.lx(.secondary))
        }
        .padding(LX.Space.s400)
        .lxGlass(in: RoundedRectangle(cornerRadius: LX.Radius.card, style: .continuous))
        .padding(.horizontal, LX.Space.s400)
        .padding(.bottom, LX.Space.s400)
    }

    // MARK: Bottom panel (lookup, product, not found, typing, manual)

    private var panelStage: Stage? {
        switch stage {
        case .typing, .lookingUp, .found, .notFound, .manual: return stage
        default: return nil
        }
    }

    private func panelOverlay(_ panel: Stage) -> some View {
        ZStack(alignment: .bottom) {
            LXLight.scrim.opacity(0.45).ignoresSafeArea()
                .onTapGesture { if panel == .typing { stage = .scanning } }
                .accessibilityHidden(true)
            ScrollView {
                VStack(alignment: .leading, spacing: LX.Space.s400) {
                    panelContent(panel)
                }
                .padding(LX.Space.s500)
                .lxCard(radius: LX.Radius.sheet, role: .surfaceRaised)
                .padding(.horizontal, LX.Space.s200)
                .padding(.top, 120)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder private func panelContent(_ panel: Stage) -> some View {
        switch panel {
        case .typing:
            Text("Type the barcode").lxFont(.title3).foregroundStyle(.lx(.textPrimary))
            LXTextField(label: "Number under the bars", text: $typedCode, placeholder: "8901234567890", isNumeric: true)
            HStack(spacing: LX.Space.s300) {
                Button("Back") { stage = cameraReady ? .scanning : .typing }.buttonStyle(.lx(.secondary))
                    .disabled(!cameraReady)
                Button { look(up: typedCode) } label: { Text("Look up").frame(maxWidth: .infinity) }
                    .buttonStyle(.lx(.primary))
                    .disabled(typedDigits.count < 6)
            }

        case .lookingUp(let code):
            HStack(spacing: LX.Space.s300) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Looking it up…").lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                    Text(code).lxFont(.footnote, numeric: true).foregroundStyle(.lx(.textSecondary))
                }
            }
            LXSkeleton(height: 16)
            LXSkeleton(height: 16, width: 180)

        case .found:
            if let product {
                PortionEditor(food: product, servingText: product.servingSize, mealTargets: mealTargets,
                              onLog: { portion in onLog(portion); dismiss() },
                              onFavorite: onFavorite)
                Button("Scan another") { rescan() }.buttonStyle(.lx(.plain)).frame(maxWidth: .infinity)
            }

        case .notFound(let code):
            VStack(alignment: .leading, spacing: LX.Space.s100) {
                Text(nameOnly.map { "\($0) has no nutrition facts yet" } ?? "Not in the food database yet")
                    .lxFont(.title3).foregroundStyle(.lx(.textPrimary))
                Text("Barcode \(code)").lxFont(.footnote, numeric: true).foregroundStyle(.lx(.textSecondary))
            }
            Text("Scan the nutrition table on the pack and LifeOS fills in the numbers for you to check. It's read on this iPhone.")
                .lxFont(.callout).foregroundStyle(.lx(.textSecondary))
            Button { labelFor = code } label: {
                Label("Scan the nutrition label", systemImage: "text.viewfinder").frame(maxWidth: .infinity)
            }
            .buttonStyle(.lx(.primary))
            Button { stage = .manual(code) } label: { Text("Enter it yourself").frame(maxWidth: .infinity) }
                .buttonStyle(.lx(.secondary))
            Button("Scan again") { rescan() }.buttonStyle(.lx(.plain)).frame(maxWidth: .infinity)

        case .manual(let code):
            ManualFoodForm(slot: slot, barcode: code, initialName: nameOnly ?? "",
                           onSave: { food, grams in
                               onSaveCustom(food)
                               if let code, let grams { cache(food, grams: grams, for: code) }
                               onLog(food)
                               dismiss()
                           },
                           onCancel: { stage = code.map(Stage.notFound) ?? .scanning })

        default:
            EmptyView()
        }
    }

    // MARK: Flow

    private var typedDigits: String { typedCode.filter(\.isNumber) }

    private func start() async {
        guard stage == .starting else { return }
        #if DEBUG
        // DEBUG-only fixtures so the product and not-found cards can be reviewed
        // on device without pointing the camera at anything.
        let args = ProcessInfo.processInfo.arguments
        if args.contains("LX_DEBUG_BARCODE_FOUND") {
            product = FoodItem(name: "Masala Oats", calories: 389, protein: 12, carbs: 64, fat: 9,
                               servingSize: "1 pack (38 g)", barcode: "8901058851298", mealType: slot.mealType)
            stage = .found("8901058851298")
            return
        }
        if args.contains("LX_DEBUG_BARCODE_MISSING") {
            stage = .notFound("8901058851298")
            return
        }
        #endif
        let access = await CameraAccess.request()
        if access == .granted {
            cameraReady = true
            stage = .scanning
        } else {
            stage = .blocked(access)
        }
    }

    private func locked(_ code: String) {
        guard stage == .scanning else { return }
        lockTick += 1
        look(up: code)
    }

    private func rescan() {
        product = nil
        nameOnly = nil
        typedCode = ""
        stage = cameraReady ? .scanning : .typing
    }

    private func look(up raw: String) {
        let code = raw.filter(\.isNumber).isEmpty ? raw : raw.filter(\.isNumber)
        guard !code.isEmpty else { return }
        stage = .lookingUp(code)
        nameOnly = nil
        Task { @MainActor in
            let found = try? await BarcodeFoodLookup.lookup(barcode: code, apiClient: apiClient)
            // Ignore a late answer if the person moved on (closed, rescanned).
            guard stage == .lookingUp(code) else { return }
            if var food = found, food.calories + food.protein + food.carbs + food.fat > 0 {
                food.mealType = slot.mealType
                product = food
                stage = .found(code)
            } else {
                // Open Food Facts often knows a product's name before its label.
                nameOnly = found.map(\.name).flatMap { $0 == "Unknown Product" || $0.isEmpty ? nil : $0 }
                stage = .notFound(code)
            }
        }
    }

    /// Remembers a typed-in product per 100 g, so the next scan of `code` is instant.
    private func cache(_ food: FoodItem, grams: Double, for code: String) {
        guard let kcal = PortionMath.per100(food.calories, servingGrams: grams) else { return }
        let per100 = Macros(kcal: kcal,
                            protein: PortionMath.per100(food.protein, servingGrams: grams) ?? 0,
                            carbs: PortionMath.per100(food.carbs, servingGrams: grams) ?? 0,
                            fat: PortionMath.per100(food.fat, servingGrams: grams) ?? 0)
        let product = BarcodeCache.Product(name: food.name, per100g: per100,
                                           servingDescription: "\(PortionEditor.text(grams)) g", cachedAt: Date())
        Task { await BarcodeCache.shared.store(product, for: code) }
    }
}

/// Four rounded corner brackets of a viewfinder.
private struct ViewfinderBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let l = min(rect.width, rect.height) * 0.22
        var p = Path()
        // Top-left, top-right, bottom-right, bottom-left.
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + l)); p.addLine(to: rect.origin); p.addLine(to: CGPoint(x: rect.minX + l, y: rect.minY))
        p.move(to: CGPoint(x: rect.maxX - l, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + l))
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - l)); p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.maxX - l, y: rect.maxY))
        p.move(to: CGPoint(x: rect.minX + l, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY)); p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - l))
        return p
    }
}
