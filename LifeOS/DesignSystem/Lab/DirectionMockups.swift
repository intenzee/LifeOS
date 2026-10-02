import SwiftUI

// Phase 1 §5 "Each direction is shown on": the six artefacts, built from the real
// design-system components so the comparison is honest and the winner carries
// straight into Phase 2/3. Static compositions (no ScrollView) so they render
// headlessly for the decision board as well as live in the Direction Lab.

/// Sample day used by every mockup (numbers from the UI/UX plan).
enum LXSampleDay {
    static let dateTitle = "Saturday, 3 Oct"
    static let base = 1_571
    static let earned = 222
    static let eaten = 1_153
    static var budget: Int { base + earned }
    static var remaining: Int { budget - eaten }
    static let orb = LifeOrbState(fillLevel: Double(eaten) / Double(base + earned), rimIntensity: 0.55)
}

enum LXMockArtefact: String, CaseIterable, Identifiable, Sendable {
    case today, capture, mealResult, workoutSynced, appIcon, watch
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: return "Today"
        case .capture: return "Capture sheet"
        case .mealResult: return "Meal result"
        case .workoutSynced: return "Workout synced"
        case .appIcon: return "App icon"
        case .watch: return "Apple Watch"
        }
    }
    /// Canvas size in points.
    var size: CGSize {
        switch self {
        case .appIcon: return CGSize(width: 393, height: 300)
        case .watch: return CGSize(width: 393, height: 300)
        default: return CGSize(width: 393, height: 852)
        }
    }

    @ViewBuilder var view: some View {
        switch self {
        case .today: MockTodayScreen()
        case .capture: MockCaptureScreen()
        case .mealResult: MockMealResultScreen()
        case .workoutSynced: MockTodayScreen(workoutJustArrived: true)
        case .appIcon: MockAppIconBoard()
        case .watch: MockWatchBoard()
        }
    }
}

// MARK: - Phone chrome

struct MockPhone<Content: View>: View {
    var showTabBar = true
    @ViewBuilder var content: Content
    @State private var tab: LXTab = .today

    var body: some View {
        ZStack(alignment: .bottom) {
            LXScreenBackground()
            VStack(spacing: 0) {
                HStack {
                    Text("9:41").font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Image(systemName: "battery.75percent").font(.system(size: 15))
                }
                .foregroundStyle(.lx(.textPrimary))
                .padding(.horizontal, 32).padding(.top, 16).frame(height: 54)
                content
                Spacer(minLength: 0)
            }
            if showTabBar {
                LXTabBar(selection: $tab).padding(.bottom, 22)
            }
        }
        .frame(width: 393, height: 852)
        .clipped()
    }
}

// MARK: - 1 · Today

struct MockTodayScreen: View {
    var workoutJustArrived = false

    var body: some View {
        MockPhone {
            VStack(alignment: .leading, spacing: LX.Space.s300) {
                header
                hero
                if workoutJustArrived {
                    MockWorkoutCard(highlight: true)
                } else {
                    nextUp
                }
                metrics
                timeline
            }
            .padding(.horizontal, LX.Space.screenMargin)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today").lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.textSecondary)).textCase(.uppercase)
                Spacer()
                LXChip(title: "Ask", systemImage: "sparkles", kind: .suggestion)
                Circle().fill(.lx(.surfaceRaised)).frame(width: 36, height: 36)
                    .overlay(Text("T").lxFont(.headline).foregroundStyle(.lx(.textPrimary)))
                    .accessibilityLabel("Profile")
            }
            Text(LXSampleDay.dateTitle).lxFont(.titleLarge).foregroundStyle(.lx(.textPrimary))
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var hero: some View {
        let orb = workoutJustArrived ? LifeOrbState(fillLevel: LXSampleDay.orb.fillLevel, rimIntensity: 0.95, wobble: 0.6) : LXSampleDay.orb
        // The number sits below the orb, never on the liquid: its contrast must not
        // depend on the fill level (Phase 2 §3.1, text ≥ 7:1 on background).
        return VStack(spacing: LX.Space.s200) {
            LifeOrb(state: orb, size: 196, frozenTime: 1.2)
                .frame(height: 188)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(LXSampleDay.remaining)").lxFont(.displayHero, numeric: true).foregroundStyle(.lx(.textPrimary))
                Text("kcal left").lxFont(.headline).foregroundStyle(.lx(.textSecondary))
            }
            LXBudgetChip(base: LXSampleDay.base, earned: LXSampleDay.earned)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Remaining calories, \(LXSampleDay.remaining). Budget \(LXSampleDay.budget.formatted()), including \(LXSampleDay.earned) earned from activity.")
    }

    private var nextUp: some View {
        HStack(spacing: LX.Space.s300) {
            Image(systemName: "sun.max").font(.title3).foregroundStyle(.lx(.dataEnergy)).frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text("Next up").lxFont(.caption).foregroundStyle(.lx(.textSecondary))
                Text("Dinner usually around 8 pm").lxFont(.headline).foregroundStyle(.lx(.textPrimary))
            }
            Spacer()
            Button("Log usual") {}.buttonStyle(.lx(.secondary))
        }
        .lxCard(padding: LX.Space.s300 + 2)
    }

    private var metrics: some View {
        HStack(spacing: LX.Space.cardGap - 4) {
            MiniMetric(icon: "fork.knife", label: "Protein", value: "96", unit: "g", progress: 0.8, role: .dataProtein)
            MiniMetric(icon: "drop.fill", label: "Water", value: "5", unit: "/8", progress: 0.62, role: .dataWater)
            MiniMetric(icon: "flame.fill", label: "Active", value: "443", unit: "kcal", progress: 0.74, role: .dataActivity)
            MiniMetric(icon: "moon.fill", label: "Sleep", value: "7.2", unit: "h", progress: 0.9, role: .dataSleep)
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            TimelineRow(time: "1:10 pm", title: "Dal, 2 rotis, salad", detail: "520 kcal · 24 g protein", source: .voice, icon: "fork.knife", role: .dataEnergy)
            Divider().overlay(Color.clear).background(.lx(.separator))
            TimelineRow(time: "8:05 am", title: "Usual breakfast", detail: "420 kcal · 31 g protein", source: .preset, icon: "fork.knife", role: .dataEnergy)
        }
        .lxCard(padding: LX.Space.s300)
    }
}

private struct MiniMetric: View {
    let icon: String, label: String, value: String, unit: String
    let progress: Double
    let role: LXColorRole

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).symbolRenderingMode(.hierarchical).foregroundStyle(.lx(role)).font(.footnote)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).lxFont(.headline, numeric: true).foregroundStyle(.lx(.textPrimary))
                Text(unit).lxFont(.caption).foregroundStyle(.lx(.textSecondary))
            }
            .lineLimit(1).minimumScaleFactor(0.8)
            LXProgressBar(value: progress, role: role, height: 4)
            Text(label).lxFont(.caption).foregroundStyle(.lx(.textSecondary))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lxCard(radius: LX.Radius.tile, padding: 10)
    }
}

private struct TimelineRow: View {
    let time: String, title: String, detail: String
    let source: LXSource
    let icon: String
    let role: LXColorRole

    var body: some View {
        HStack(spacing: LX.Space.s300) {
            Image(systemName: icon).foregroundStyle(.lx(role)).frame(width: 32, height: 32)
                .background(Circle().fill(.lx(role).opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lxFont(.headline).foregroundStyle(.lx(.textPrimary)).lineLimit(1)
                Text(detail).lxFont(.footnote, numeric: true).foregroundStyle(.lx(.textSecondary))
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 4) {
                Text(time).lxFont(.caption, numeric: true).foregroundStyle(.lx(.textTertiary))
                LXSourceBadge(source: source)
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 4 · Workout synced card (component 28)

struct MockWorkoutCard: View {
    var highlight = false
    @Environment(\.lxTheme) private var theme

    var body: some View {
        HStack(spacing: LX.Space.s300) {
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.title3).foregroundStyle(.lx(.dataActivity))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: LX.Radius.chip, style: .continuous).fill(.lx(.dataActivity).opacity(0.14)))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Strength, 48 min").lxFont(.headline).foregroundStyle(.lx(.textPrimary)).lineLimit(1)
                    Spacer(minLength: 6)
                    LXSourceBadge(source: .watch)
                }
                HStack(spacing: 6) {
                    Text("+222 kcal earned").lxFont(.subhead, numeric: true, weight: .semibold).foregroundStyle(.lx(.dataActivity))
                    Text("· 6:40 pm").lxFont(.subhead, numeric: true).foregroundStyle(.lx(.textSecondary))
                }
                .lineLimit(1)
            }
        }
        .lxCard(padding: LX.Space.s300 + 2)
        .overlay {
            if highlight {
                RoundedRectangle(cornerRadius: LX.Radius.card, style: .continuous)
                    .strokeBorder(theme.color(.dataActivity).opacity(0.55), lineWidth: 1)
            }
        }
    }
}

// MARK: - 2 · Capture sheet

struct MockCaptureScreen: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            MockTodayScreen()
            Rectangle().fill(.black.opacity(0.35)).frame(width: 393, height: 852)
            CaptureSheetContent()
                .frame(width: 393, height: 560, alignment: .top)
                .background(UnevenRoundedRectangle(topLeadingRadius: LX.Radius.sheet, topTrailingRadius: LX.Radius.sheet, style: .continuous).fill(.lx(.surfaceRaised)))
        }
        .frame(width: 393, height: 852)
    }
}

struct CaptureSheetContent: View {
    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s400) {
            Capsule().fill(.lx(.textTertiary)).frame(width: 36, height: 5).frame(maxWidth: .infinity).padding(.top, 6)
            HStack {
                LXChip(title: "Dinner", systemImage: "moon.stars", kind: .neutral, trailing: "8:12 pm")
                Spacer()
                LXIconButton(systemImage: "xmark", label: "Close", glass: false) {}
            }
            HStack(alignment: .top, spacing: LX.Space.s300) {
                VoiceGlyph().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listening…").lxFont(.footnote, weight: .medium).foregroundStyle(.lx(.accentPrimary))
                    Text("2 rotis, dal and a cup of chai").lxFont(.title2).foregroundStyle(.lx(.textPrimary))
                }
            }
            HStack(spacing: LX.Space.s200) {
                ModeButton(icon: "keyboard", title: "Type")
                ModeButton(icon: "camera", title: "Photo")
                ModeButton(icon: "barcode.viewfinder", title: "Scan")
                ModeButton(icon: "sparkles", title: "Ask")
            }
            LXSectionHeader(title: "Usual at this time")
            VStack(alignment: .leading, spacing: LX.Space.s200) {
                HStack(spacing: LX.Space.s200) {
                    LXChip(title: "Usual dinner", systemImage: "star.square.on.square", trailing: "610")
                    LXChip(title: "Chai", systemImage: "cup.and.saucer", trailing: "90")
                }
                HStack(spacing: LX.Space.s200) {
                    LXChip(title: "Paneer bowl", systemImage: "star.square.on.square", trailing: "540")
                    LXChip(title: "Greek yogurt", systemImage: "star.square.on.square", trailing: "150")
                }
            }
            HStack(spacing: LX.Space.s200) {
                Button { } label: { Label("+1 glass", systemImage: "drop.fill") }.buttonStyle(.lx(.secondary))
                Button { } label: { Label("Weight", systemImage: "scalemass") }.buttonStyle(.lx(.secondary))
            }
        }
        .padding(.horizontal, LX.Space.screenMargin)
    }
}

private struct ModeButton: View {
    let icon: String, title: String
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title3).symbolRenderingMode(.hierarchical)
            Text(title).lxFont(.caption)
        }
        .foregroundStyle(.lx(.textPrimary))
        .frame(maxWidth: .infinity, minHeight: 64)
        .background(RoundedRectangle(cornerRadius: LX.Radius.tile, style: .continuous).fill(.lx(.surface)))
        .overlay(RoundedRectangle(cornerRadius: LX.Radius.tile, style: .continuous).strokeBorder(.lx(.separator), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

/// Assistant/voice orb glyph (static frame of the voice-reactive version).
struct VoiceGlyph: View {
    @Environment(\.lxTheme) private var theme
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [Color(lxHex: theme.orb.liquidTop), Color(lxHex: theme.orb.liquidBottom)], center: .topLeading, startRadius: 2, endRadius: 50))
            ForEach(0..<3) { i in
                Circle().stroke(Color(lxHex: theme.orb.rim).opacity(0.5 - Double(i) * 0.15), lineWidth: 1.5)
                    .scaleEffect(1 + CGFloat(i) * 0.18)
            }
            Image(systemName: "waveform").font(.title3.weight(.semibold)).foregroundStyle(.white)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - 3 · Meal result / AI proposal card (component 24)

struct MockMealResultScreen: View {
    var body: some View {
        MockPhone(showTabBar: false) {
            VStack(alignment: .leading, spacing: LX.Space.s400) {
                HStack {
                    LXIconButton(systemImage: "chevron.left", label: "Back") {}
                    Spacer()
                    Text("Meal result").lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                    Spacer()
                    LXIconButton(systemImage: "ellipsis", label: "More") {}
                }
                MockPlatePhoto().frame(height: 230)
                HStack(spacing: 6) {
                    LXChip(title: "Lunch", systemImage: "sun.max", trailing: "1:10 pm")
                    Spacer()
                    LXSourceBadge(source: .onDevice)
                }
                VStack(spacing: 0) {
                    ItemRow(name: "Rice", amount: "1 bowl · 180 g", kcal: 234, confidence: .low)
                    Divider().background(.lx(.separator))
                    ItemRow(name: "Dal tadka", amount: "1 katori · 150 g", kcal: 180, confidence: .high)
                    Divider().background(.lx(.separator))
                    ItemRow(name: "Roti", amount: "2 pieces", kcal: 206, confidence: .high)
                }
                .lxCard(padding: LX.Space.s300)
                HStack(alignment: .firstTextBaseline) {
                    Text("620").lxFont(.displayL, numeric: true).foregroundStyle(.lx(.textPrimary))
                    Text("kcal").lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                    Spacer()
                    Text("Check the rice portion.").lxFont(.footnote).foregroundStyle(.lx(.statusAttention))
                }
                LXMacroBar(macros: [
                    .init(name: "Protein", grams: 24, target: 120, role: .dataProtein),
                    .init(name: "Carbs", grams: 104, target: 220, role: .dataCarbs),
                    .init(name: "Fat", grams: 12, target: 60, role: .dataFat),
                ])
                HStack(spacing: LX.Space.s300) {
                    Button("Edit") {}.buttonStyle(.lx(.secondary))
                    Button { } label: { Text("Log 620 kcal").frame(maxWidth: .infinity) }.buttonStyle(.lx(.primary))
                }
            }
            .padding(.horizontal, LX.Space.screenMargin)
        }
    }
}

private struct ItemRow: View {
    let name: String, amount: String
    let kcal: Int
    let confidence: LXConfidence

    var body: some View {
        HStack(spacing: LX.Space.s300) {
            LXConfidenceDot(confidence: confidence)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                Text(amount).lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
            }
            Spacer()
            Text("\(kcal)").lxFont(.headline, numeric: true).foregroundStyle(.lx(.textPrimary))
            Text("kcal").lxFont(.caption).foregroundStyle(.lx(.textSecondary))
        }
        .padding(.vertical, 8)
    }
}

/// Illustrated plate standing in for a meal photo, with the Phase 2 §9.3 "meal lift".
struct MockPlatePhoto: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: LX.Radius.hero, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.20), Color(red: 0.20, green: 0.15, blue: 0.11)], startPoint: .top, endPoint: .bottom))
                .overlay(Color.black.opacity(0.35).clipShape(RoundedRectangle(cornerRadius: LX.Radius.hero, style: .continuous)))
            ZStack {
                Circle().fill(Color(white: 0.96)).frame(width: 190)
                Circle().fill(Color(white: 0.90)).frame(width: 150)
                Ellipse().fill(Color(red: 0.97, green: 0.95, blue: 0.88)).frame(width: 80, height: 62).offset(x: -26, y: -12)
                Circle().fill(Color(red: 0.86, green: 0.62, blue: 0.22)).frame(width: 58).offset(x: 34, y: -4)
                Ellipse().fill(Color(red: 0.80, green: 0.62, blue: 0.40)).frame(width: 74, height: 30).rotationEffect(.degrees(-18)).offset(x: 6, y: 44)
            }
            .scaleEffect(1.04)
            .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 14)
            PlateLabel(text: "Rice").offset(x: -78, y: -54)
            PlateLabel(text: "Dal").offset(x: 92, y: -30)
            PlateLabel(text: "Roti ×2").offset(x: 70, y: 76)
        }
        .clipShape(RoundedRectangle(cornerRadius: LX.Radius.hero, style: .continuous))
        .accessibilityLabel("Photo of your meal: rice, dal and two rotis")
    }
}

private struct PlateLabel: View {
    let text: String
    var body: some View {
        Text(text).lxFont(.caption, weight: .semibold).foregroundStyle(.lx(.textPrimary))
            .padding(.horizontal, 8).padding(.vertical, 4).lxGlass()
    }
}

// MARK: - 5 · App icon + wordmark

struct MockAppIcon: View {
    var size: CGFloat
    @Environment(\.lxTheme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).fill(.lx(.background))
            RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous)
                .fill(RadialGradient(colors: [theme.color(.heroGlowA), .clear], center: .top, startRadius: 0, endRadius: size))
            LifeOrb(state: LifeOrbState(fillLevel: 0.62, rimIntensity: 0.6), size: size * 0.86, frozenTime: 0.7)
        }
        .frame(width: size, height: size)
        .overlay(RoundedRectangle(cornerRadius: size * 0.2237, style: .continuous).strokeBorder(.lx(.separator), lineWidth: 0.5))
    }
}

struct MockAppIconBoard: View {
    @Environment(\.lxTheme) private var theme
    var body: some View {
        ZStack {
            Rectangle().fill(.lx(.surface))
            VStack(spacing: LX.Space.s600) {
                HStack(alignment: .bottom, spacing: LX.Space.s700) {
                    VStack { MockAppIcon(size: 120); caption("120 pt") }
                    VStack { MockAppIcon(size: 60); caption("60 pt") }
                    VStack { MockAppIcon(size: 29); caption("29 pt") }
                }
                HStack(spacing: 10) {
                    MockAppIcon(size: 30)
                    Text("LifeOS").font(.system(size: 30, weight: .semibold, design: theme.direction.displayDesign))
                        .tracking(theme.direction == .obsidian ? 2 : 0.5)
                        .foregroundStyle(.lx(.textPrimary))
                }
            }
        }
        .frame(width: 393, height: 300)
    }

    private func caption(_ s: String) -> some View { Text(s).lxFont(.caption).foregroundStyle(.lx(.textSecondary)) }
}

// MARK: - 6 · Apple Watch dashboard + complication

struct MockWatchBoard: View {
    var body: some View {
        ZStack {
            Rectangle().fill(.lx(.surface))
            HStack(spacing: LX.Space.s700) {
                // 45 mm face: 198 × 242 pt. Watch is always dark.
                WatchFace().environment(\.colorScheme, .dark)
                VStack(spacing: LX.Space.s300) {
                    WatchComplication().environment(\.colorScheme, .dark)
                    Text("Circular\ncomplication").multilineTextAlignment(.center).lxFont(.caption).foregroundStyle(.lx(.textSecondary))
                }
            }
        }
        .frame(width: 393, height: 300)
    }
}

private struct WatchFace: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("LifeOS").font(.system(size: 13, weight: .semibold)).foregroundStyle(.lx(.accentPrimary))
                Spacer()
                Text("9:41").font(.system(size: 13, weight: .semibold)).foregroundStyle(.lx(.textPrimary))
            }
            LifeOrb(state: LXSampleDay.orb, size: 96, frozenTime: 1.2).frame(height: 88)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(LXSampleDay.remaining)").lxFont(.title2, numeric: true).foregroundStyle(.lx(.textPrimary))
                Text("left").font(.system(size: 12)).foregroundStyle(.lx(.textSecondary))
            }
            HStack(spacing: 12) {
                stat("drop.fill", "5/8", .dataWater)
                stat("flame.fill", "+222", .dataActivity)
            }
        }
        .padding(12)
        .frame(width: 198, height: 242)
        .background(RoundedRectangle(cornerRadius: 46, style: .continuous).fill(Color.black))
        .overlay(RoundedRectangle(cornerRadius: 46, style: .continuous).strokeBorder(Color(white: 0.25), lineWidth: 6))
    }

    private func stat(_ icon: String, _ value: String, _ role: LXColorRole) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 11)).foregroundStyle(.lx(role))
            Text(value).font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit().foregroundStyle(.lx(.textPrimary))
        }
    }
}

private struct WatchComplication: View {
    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.08))
            VStack(spacing: -2) {
                LifeOrb(state: LXSampleDay.orb, size: 38, frozenTime: 1.2)
                Text("\(LXSampleDay.remaining)").font(.system(size: 12, weight: .bold, design: .rounded)).monospacedDigit().foregroundStyle(.white)
            }
        }
        .frame(width: 64, height: 64)
    }
}
