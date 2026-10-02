import SwiftUI

/// Type ramp (Phase 2 §4). Every style scales with Dynamic Type relative to its
/// text style; display styles use the direction's display design (New York serif
/// or SF Pro Rounded). Numbers use monospaced digits so they never jump.
enum LXTextStyle: CaseIterable, Sendable {
    case displayHero, displayL, titleLarge, title1, title2, title3, headline, body, callout, subhead, footnote, caption

    var spec: LXTokens.TypeSpec {
        switch self {
        case .displayHero: return LXTokens.TypeRamp.displayHero
        case .displayL: return LXTokens.TypeRamp.displayL
        case .titleLarge: return LXTokens.TypeRamp.titleLarge
        case .title1: return LXTokens.TypeRamp.title1
        case .title2: return LXTokens.TypeRamp.title2
        case .title3: return LXTokens.TypeRamp.title3
        case .headline: return LXTokens.TypeRamp.headline
        case .body: return LXTokens.TypeRamp.body
        case .callout: return LXTokens.TypeRamp.callout
        case .subhead: return LXTokens.TypeRamp.subhead
        case .footnote: return LXTokens.TypeRamp.footnote
        case .caption: return LXTokens.TypeRamp.caption
        }
    }
}

private struct LXFontModifier: ViewModifier {
    let style: LXTextStyle
    let numeric: Bool
    let weight: Font.Weight?
    @Environment(\.lxDirection) private var direction
    @ScaledMetric private var size: CGFloat

    init(style: LXTextStyle, numeric: Bool, weight: Font.Weight?) {
        self.style = style
        self.numeric = numeric
        self.weight = weight
        _size = ScaledMetric(wrappedValue: style.spec.size, relativeTo: style.spec.relativeTo)
    }

    #if os(macOS)
    // macOS has no Dynamic Type, so @ScaledMetric stays at the base size there. The test
    // harness runs on macOS, so scale from the environment's size with Apple's body-style
    // ratios to make accessibility snapshots real. iOS uses the system scaling above.
    @Environment(\.dynamicTypeSize) private var typeSize
    private var effectiveSize: CGFloat { style.spec.size * Self.bodyRatio(typeSize) }

    static func bodyRatio(_ size: DynamicTypeSize) -> CGFloat {
        let points: [DynamicTypeSize: CGFloat] = [
            .xSmall: 14, .small: 15, .medium: 16, .large: 17, .xLarge: 19, .xxLarge: 21, .xxxLarge: 23,
            .accessibility1: 28, .accessibility2: 33, .accessibility3: 40, .accessibility4: 47, .accessibility5: 53,
        ]
        return (points[size] ?? 17) / 17
    }
    #else
    private var effectiveSize: CGFloat { size }
    #endif

    func body(content: Content) -> some View {
        let spec = style.spec
        let size = effectiveSize
        let design: Font.Design = numeric ? direction.numericDesign : (spec.isDisplay ? direction.displayDesign : .default)
        // Never below 11 pt (Phase 2 §4 rule).
        let font = Font.system(size: max(size, 11), weight: weight ?? spec.weight, design: design)
        let extraLeading = max(0, (spec.lineHeight - spec.size * 1.19) * (size / spec.size))
        return content
            .font(numeric ? font.monospacedDigit() : font)
            .lineSpacing(extraLeading)
            // A number is never broken across lines; it shrinks a little instead.
            .lineLimit(numeric ? 1 : nil)
            .minimumScaleFactor(numeric ? 0.6 : 1)
    }
}

/// HStack at normal sizes, leading-aligned VStack at accessibility text sizes
/// (engineering roadmap 08 §3.8: "layouts switch to vertical stacks").
struct LXAdaptiveStack<Content: View>: View {
    var spacing: CGFloat = LX.Space.s300
    var alignment: VerticalAlignment = .center
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) { content }
        } else {
            HStack(alignment: alignment, spacing: spacing) { content }
        }
    }
}

extension View {
    /// Applies a LifeOS text style. `numeric: true` for any changing number.
    func lxFont(_ style: LXTextStyle, numeric: Bool = false, weight: Font.Weight? = nil) -> some View {
        modifier(LXFontModifier(style: style, numeric: numeric, weight: weight))
    }
}
