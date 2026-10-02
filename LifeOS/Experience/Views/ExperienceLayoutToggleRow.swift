import SwiftUI

/// Settings row (classic UI) that switches the Phase 3 layout back on.
struct ExperienceLayoutToggleRow: View {
    @AppStorage("lx.newExperience") private var newExperience = true
    @Environment(\.lxTheme) private var theme

    var body: some View {
        Toggle(isOn: $newExperience) {
            HStack(spacing: LX.Space.s300) {
                Image(systemName: "sparkles.rectangle.stack").foregroundStyle(.lx(.accentPrimary)).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New layout").lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                    Text("Phase 3 · Today, Capture, Nutrition, Training, You").lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
                }
            }
        }
        .tint(theme.color(.accentPrimary))
        .lxCard()
    }
}
