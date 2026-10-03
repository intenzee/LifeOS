import SwiftUI

/// The watch side of the LifeOS design system (UI/UX Phase 5 §2).
///
/// The watch is always dark, so these are the dark values of the phone's tokens
/// (`LifeOS/DesignSystem/Tokens/LXTokens.generated.swift`). The data colours
/// are the same in every direction; the accent is Aurora's, the app default.
/// Keep them in step when the tokens change.
enum WatchTheme {
    static let accent = Color(hex: 0x70EDC6)       // accentPrimary (Aurora)
    static let energy = Color(hex: 0xF2A65A)       // dataEnergy
    static let activity = Color(hex: 0x5FD6C2)     // dataActivity
    static let protein = Color(hex: 0xF08A8A)      // dataProtein
    static let water = Color(hex: 0x8BD6EE)        // dataWater
    static let weight = Color(hex: 0xB4AEA7)       // dataWeight
    static let onTrack = Color(hex: 0x8CC9A8)      // statusOnTrack
    static let over = Color(hex: 0xD98C5F)         // statusOver
    static let secondary = Color(hex: 0x9AA3B5)    // textSecondary (Aurora)
    static let card = Color.white.opacity(0.08)

    /// Legacy names used by the workout screens.
    static let burn = energy

    /// Large numerals: SF Pro Rounded, monospaced digits so numbers don't jump.
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

/// A thin circular progress ring with a centred label.
struct RingView<Label: View>: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 8
    @ViewBuilder var label: () -> Label
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.2), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0, min(progress, 1)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.4), value: progress)
            label()
        }
    }
}

/// The 2D Life Orb glyph: a glass sphere whose fill rises with what's eaten and
/// whose rim brightens with activity. Same idea as the phone's orb, no 3D.
struct WatchOrbGlyph: View {
    var fill: Double
    var activity: Double
    var over: Bool

    var body: some View {
        let level = max(0, min(fill, 1))
        ZStack {
            Circle().fill(RadialGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.02)],
                                         center: .init(x: 0.35, y: 0.3), startRadius: 1, endRadius: 80))
            GeometryReader { geo in
                Rectangle()
                    .fill(LinearGradient(colors: [(over ? WatchTheme.over : WatchTheme.energy).opacity(0.9),
                                                  (over ? WatchTheme.over : WatchTheme.energy).opacity(0.45)],
                                         startPoint: .bottom, endPoint: .top))
                    .frame(height: geo.size.height * level)
                    .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .clipShape(Circle())
            Circle().strokeBorder(WatchTheme.activity.opacity(0.35 + 0.6 * max(0, min(activity, 1))), lineWidth: 3)
            Circle().fill(LinearGradient(colors: [Color.white.opacity(0.25), .clear], startPoint: .top, endPoint: .center))
                .padding(10).blendMode(.plusLighter).opacity(0.5)
        }
        .accessibilityHidden(true)
    }
}
