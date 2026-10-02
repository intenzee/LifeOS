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

    func body(content: Content) -> some View {
        let spec = style.spec
        let design: Font.Design = numeric ? direction.numericDesign : (spec.isDisplay ? direction.displayDesign : .default)
        // Never below 11 pt (Phase 2 §4 rule).
        let font = Font.system(size: max(size, 11), weight: weight ?? spec.weight, design: design)
        let extraLeading = max(0, (spec.lineHeight - spec.size * 1.19) * (size / spec.size))
        return content
            .font(numeric ? font.monospacedDigit() : font)
            .lineSpacing(extraLeading)
    }
}

extension View {
    /// Applies a LifeOS text style. `numeric: true` for any changing number.
    func lxFont(_ style: LXTextStyle, numeric: Bool = false, weight: Font.Weight? = nil) -> some View {
        modifier(LXFontModifier(style: style, numeric: numeric, weight: weight))
    }
}
