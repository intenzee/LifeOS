import SwiftUI

/// UserDefaults key for the owner's chosen direction (until gate D1 locks one).
enum LXDirectionPreference {
    static let key = "lx.direction"
}

/// Applies the stored direction to the whole app. Attached once at the root.
struct LXDirectionRoot: ViewModifier {
    @AppStorage(LXDirectionPreference.key) private var raw = LXDirection.aurora.rawValue

    func body(content: Content) -> some View {
        content.lxDirection(LXDirection(rawValue: raw) ?? .aurora)
    }
}

/// Phase 1 Direction Lab: live with each direction on the iPhone for a day
/// (Phase 1 §6) and try the Life Orb with real gestures, haptics and motion.
struct DirectionLabView: View {
    @AppStorage(LXDirectionPreference.key) private var storedRaw = LXDirection.aurora.rawValue
    @State private var preview: LXDirection = .aurora
    @State private var artefact: LXMockArtefact = .today
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: LX.Space.s600) {
                    Picker("Direction", selection: $preview) {
                        ForEach(LXDirection.allCases) { Text($0.displayName).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    Text(preview.mood).lxFont(.callout).foregroundStyle(.lx(.textSecondary))

                    OrbPlayground()

                    LXSectionHeader(title: "Mockups")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: LX.Space.s200) {
                            ForEach(LXMockArtefact.allCases) { a in
                                Button { artefact = a } label: {
                                    LXChip(title: a.title, kind: .filter(selected: artefact == a))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    MockupFrame(artefact: artefact)

                    Button {
                        storedRaw = preview.rawValue
                    } label: {
                        Text(storedRaw == preview.rawValue ? "In use across the app" : "Use \(preview.displayName) everywhere")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.lx(.primary))
                    .disabled(storedRaw == preview.rawValue)
                    .lxHaptic(.selection, trigger: storedRaw)
                }
                .padding(LX.Space.screenMargin)
            }
            .background(LXScreenBackground(heroGlow: false))
            .navigationTitle("Direction Lab")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .lxDirection(preview)
        .lxAnimation(.smooth, value: preview)
        .onAppear { preview = LXDirection(rawValue: storedRaw) ?? .aurora }
    }
}

/// Scales a 393-pt-wide mockup to the available width.
private struct MockupFrame: View {
    let artefact: LXMockArtefact

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.width / artefact.size.width
            artefact.view
                .frame(width: artefact.size.width, height: artefact.size.height)
                .scaleEffect(scale, anchor: .topLeading)
                .allowsHitTesting(false)
        }
        .aspectRatio(artefact.size.width / artefact.size.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: LX.Radius.card, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(artefact.title) mockup")
    }
}

/// Live orb with the Phase 2 §9.1 behaviours: touch wobbles (rate-limited light
/// haptic), tap splits into macro layers for 3 s, sliders drive the inputs.
private struct OrbPlayground: View {
    @State private var fill = 0.64
    @State private var rim = 0.55
    @State private var wobble = 0.0
    @State private var stale = false
    @State private var showLayers = false
    @State private var touches = 0
    @State private var lastTouch = Date.distantPast

    var body: some View {
        VStack(spacing: LX.Space.s400) {
            LifeOrb(state: LifeOrbState(fillLevel: fill, rimIntensity: rim, wobble: wobble, isStale: stale,
                                        macroLayers: showLayers ? .init(proteinG: 96, carbsG: 150, fatG: 40) : nil),
                    size: LXTokens.Orb.heroSize)
                .frame(maxWidth: .infinity)
                .contentShape(Circle())
                .onTapGesture { touch() }
                .lxHaptic(.orbTouch, trigger: touches)
                .accessibilityElement()
                .accessibilityLabel("Life Orb, \(Int(fill * 100)) percent of budget eaten")
                .accessibilityHint("Shows protein, carbs and fat for three seconds")
                .accessibilityAddTraits(.isButton)

            VStack(spacing: LX.Space.s200) {
                slider("Eaten ÷ budget", value: $fill, range: 0...1.2)
                slider("Activity earned (rim)", value: $rim, range: 0...1)
                Toggle("Stale data", isOn: $stale).lxFont(.subhead).foregroundStyle(.lx(.textPrimary))
            }
            .lxCard()
        }
    }

    private func touch() {
        // Haptic rate-limited to once per 300 ms (Phase 2 §8.4).
        if Date().timeIntervalSince(lastTouch) > 0.3 { touches += 1; lastTouch = Date() }
        wobble = 1
        withAnimation(.spring(duration: 1.2, bounce: 0)) { wobble = 0 }
        showLayers = true
        Task {
            try? await Task.sleep(for: .seconds(3))
            showLayers = false
        }
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title).lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                Spacer()
                Text("\(Int(value.wrappedValue * 100))%").lxFont(.subhead, numeric: true).foregroundStyle(.lx(.textPrimary))
            }
            Slider(value: value, in: range).tint(LXColor(role: .accentPrimary))
        }
    }
}

/// Settings row that opens the lab. Kept here so Settings needs a one-line change.
struct DirectionLabEntryRow: View {
    @State private var showLab = false
    @AppStorage(LXDirectionPreference.key) private var storedRaw = LXDirection.aurora.rawValue

    var body: some View {
        Button { showLab = true } label: {
            HStack(spacing: LX.Space.s300) {
                Image(systemName: "paintpalette").foregroundStyle(.lx(.accentPrimary)).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Direction Lab").lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                    Text("Phase 1 · \(LXDirection(rawValue: storedRaw)?.displayName ?? "Aurora Glass")")
                        .lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(.lx(.textTertiary))
            }
            .lxCard()
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLab) { DirectionLabView() }
    }
}
