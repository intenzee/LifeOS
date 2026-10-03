import SwiftUI

// Phase 5 §7: "Works at the largest accessibility text size without truncating
// key numbers (layouts switch to vertical stacks)."

extension DynamicTypeSize {
    /// Columns for a tile grid that normally has `regular` columns.
    func lxColumns(_ regular: Int, accessibility: Int = 1) -> [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: LX.Space.s300), count: isAccessibilitySize ? accessibility : regular)
    }
}

/// A row of tiles or buttons that becomes a column at accessibility text sizes.
struct LXTileRow<Content: View>: View {
    var spacing: CGFloat = LX.Space.s300
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}
