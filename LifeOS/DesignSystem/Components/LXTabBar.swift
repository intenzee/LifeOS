import SwiftUI

/// The five-tab information architecture (master plan §5).
enum LXTab: String, CaseIterable, Identifiable, Sendable {
    case today, nutrition, capture, training, you
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: return "Today"
        case .nutrition: return "Nutrition"
        case .capture: return "Capture"
        case .training: return "Training"
        case .you: return "You"
        }
    }

    var systemImage: String {
        switch self {
        case .today: return "circle.circle"
        case .nutrition: return "fork.knife"
        case .capture: return "plus"
        case .training: return "figure.strengthtraining.traditional"
        case .you: return "person.crop.circle"
        }
    }
}

/// Component 4 (tab bar) + 3 (Capture button). Labelled tabs (fixes A23), one
/// floating glass layer, the Capture button raised in the centre.
/// Tap Capture = capture; long-press = assistant.
struct LXTabBar: View {
    @Binding var selection: LXTab
    var onCapture: () -> Void = {}
    var onAssistant: () -> Void = {}

    @State private var captureTicks = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(LXTab.allCases) { tab in
                if tab == .capture {
                    captureButton
                } else {
                    tabButton(tab)
                }
            }
        }
        .padding(.horizontal, LX.Space.s200)
        .padding(.vertical, LX.Space.s100 + 2)
        .lxGlass(in: Capsule())
        .padding(.horizontal, LX.Space.s400)
        .lxHaptic(.selection, trigger: selection)
        .lxHaptic(.orbTouch, trigger: captureTicks)
    }

    private func tabButton(_ tab: LXTab) -> some View {
        let selected = selection == tab
        return Button { selection = tab } label: {
            VStack(spacing: 3) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 19, weight: selected ? .semibold : .regular))
                    .symbolRenderingMode(.hierarchical)
                    .frame(height: 24)
                Text(tab.title).font(.system(size: 11, weight: selected ? .semibold : .medium))
            }
            .foregroundStyle(selected ? .lx(.accentPrimary) : .lx(.textSecondary))
            .frame(maxWidth: .infinity, minHeight: LX.Space.minTouchTarget + 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var captureButton: some View {
        Image(systemName: "plus")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.lx(.onAccent))
            .frame(width: 58, height: 58)
            .background(Circle().fill(.lx(.accentPrimary)))
            .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.25), radius: 10, x: 0, y: 6)
            .offset(y: -10)
            .frame(maxWidth: .infinity)
            .contentShape(Circle())
            .onTapGesture { captureTicks += 1; onCapture() }
            .onLongPressGesture(minimumDuration: 0.35) { captureTicks += 1; onAssistant() }
            .accessibilityElement()
            .accessibilityLabel("Capture")
            .accessibilityHint("Log food, water or weight. Touch and hold to ask the assistant.")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(named: "Ask the assistant") { onAssistant() }
    }
}
