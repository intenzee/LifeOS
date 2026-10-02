import SwiftUI

// Phase 2 §7 components 6, 7, 8, 18, 29.

// MARK: 6 · Segmented control (2–4 options)

struct LXSegmented<Value: Hashable>: View {
    let options: [(label: String, value: Value)]
    @Binding var selection: Value
    @Namespace private var ns
    @Environment(\.lxDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.value) { option in
                let selected = option.value == selection
                Button {
                    withAnimation(LXMotion.snappy.animation(direction: direction, reduceMotion: reduceMotion)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .lxFont(.subhead, weight: selected ? .semibold : .regular)
                        .foregroundStyle(selected ? .lx(.textPrimary) : .lx(.textSecondary))
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selected {
                                RoundedRectangle(cornerRadius: LX.Radius.chip - 3, style: .continuous)
                                    .fill(.lx(.surface))
                                    .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
                                    .matchedGeometryEffect(id: "seg", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: LX.Radius.chip, style: .continuous).fill(.lx(.surfaceRaised)))
        .lxHaptic(.selection, trigger: selection)
    }
}

// MARK: 7 · Text field (plain, with unit, with voice, error)

struct LXTextField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var unit: String? = nil
    var error: String? = nil
    var isNumeric = false
    var onVoice: (() -> Void)? = nil
    @FocusState private var focused: Bool
    @Environment(\.lxTheme) private var theme
    @Environment(\.lxSnapshotMode) private var snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s100 + 2) {
            Text(label).lxFont(.footnote, weight: .medium).foregroundStyle(.lx(.textSecondary))
            HStack(spacing: LX.Space.s200) {
                if snapshot {
                    // Offscreen renders cannot draw platform text fields.
                    Text(text.isEmpty ? placeholder : text)
                        .lxFont(isNumeric ? .headline : .body, numeric: isNumeric)
                        .foregroundStyle(text.isEmpty ? .lx(.textTertiary) : .lx(.textPrimary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(placeholder, text: $text)
                        .lxFont(isNumeric ? .headline : .body, numeric: isNumeric)
                        .foregroundStyle(.lx(.textPrimary))
                        .focused($focused)
                        #if os(iOS)
                        .keyboardType(isNumeric ? .decimalPad : .default)
                        #endif
                }
                if let unit {
                    Text(unit).lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                }
                if let onVoice {
                    Button(action: onVoice) {
                        Image(systemName: "mic.fill").foregroundStyle(.lx(.accentPrimary))
                            .frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dictate \(label)")
                }
            }
            .padding(.horizontal, LX.Space.s300)
            .frame(minHeight: LX.Space.minTouchTarget + 4)
            .background(RoundedRectangle(cornerRadius: LX.Radius.chip, style: .continuous).fill(.lx(.surfaceRaised)))
            .overlay(RoundedRectangle(cornerRadius: LX.Radius.chip, style: .continuous)
                .strokeBorder(borderColor, lineWidth: focused || error != nil ? 1.5 : 0.5))
            if let error {
                Label(error, systemImage: "exclamationmark.circle")
                    .lxFont(.footnote).foregroundStyle(.lx(.statusCritical))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(error.map { "\(text), error: \($0)" } ?? text)
    }

    private var borderColor: Color {
        if error != nil { return theme.color(.statusCritical) }
        return focused ? theme.color(.accentPrimary) : theme.color(.separator)
    }
}

// MARK: 8 · Search field (with recent and suggested results)

struct LXSearchField: View {
    @Binding var query: String
    var prompt = "Search foods"
    var recents: [String] = []
    var suggestions: [String] = []
    var onPick: (String) -> Void = { _ in }
    @Environment(\.lxSnapshotMode) private var snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            HStack(spacing: LX.Space.s200) {
                Image(systemName: "magnifyingglass").foregroundStyle(.lx(.textSecondary))
                if snapshot {
                    Text(query.isEmpty ? prompt : query).lxFont(.body)
                        .foregroundStyle(query.isEmpty ? .lx(.textTertiary) : .lx(.textPrimary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    TextField(prompt, text: $query).lxFont(.body).foregroundStyle(.lx(.textPrimary))
                }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.lx(.textTertiary)) }
                        .buttonStyle(.plain).accessibilityLabel("Clear search")
                }
            }
            .padding(.horizontal, LX.Space.s300)
            .frame(minHeight: LX.Space.minTouchTarget)
            .background(Capsule().fill(.lx(.surfaceRaised)))
            if query.isEmpty, !recents.isEmpty {
                group("Recent", items: recents, icon: "clock.arrow.circlepath")
            }
            if !suggestions.isEmpty {
                group(query.isEmpty ? "Suggested" : "Results", items: suggestions, icon: "sparkles")
            }
        }
    }

    private func group(_ title: String, items: [String], icon: String) -> some View {
        VStack(alignment: .leading, spacing: LX.Space.s200) {
            Text(title).lxFont(.footnote, weight: .semibold).foregroundStyle(.lx(.textSecondary)).textCase(.uppercase)
            ForEach(items, id: \.self) { item in
                Button { onPick(item) } label: {
                    Label(item, systemImage: icon).lxFont(.body).foregroundStyle(.lx(.textPrimary))
                        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: 18 · Stepper / quick add (haptic per step)

struct LXQuickStepper: View {
    let label: String
    @Binding var value: Int
    var range: ClosedRange<Int> = 0...99
    var unit: String = ""
    var systemImage: String
    var role: LXColorRole

    var body: some View {
        HStack(spacing: LX.Space.s300) {
            Image(systemName: systemImage).foregroundStyle(.lx(role)).font(.title3)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(value)").lxFont(.title2, numeric: true).foregroundStyle(.lx(.textPrimary))
                        .lxNumberRoll(Double(value))
                    Text(unit).lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
                }
            }
            Spacer()
            stepButton("minus", enabled: value > range.lowerBound) { value -= 1 }
                .lxHaptic(.decrease, trigger: value)
                .accessibilityLabel("Decrease \(label)")
            stepButton("plus", enabled: value < range.upperBound) { value += 1 }
                .accessibilityLabel("Increase \(label)")
        }
        .lxAnimation(.snappy, value: value)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(value) \(unit)")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if value < range.upperBound { value += 1 }
            case .decrement: if value > range.lowerBound { value -= 1 }
            @unknown default: break
            }
        }
    }

    private func stepButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.body.weight(.semibold)).foregroundStyle(.lx(.textPrimary))
                .frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
                .background(Circle().fill(.lx(.surfaceRaised)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
    }
}

// MARK: 29 · Toggle row and settings row (with explanation text)

struct LXToggleRow: View {
    let title: String
    var explanation: String? = nil
    var systemImage: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            LXRowLabel(title: title, explanation: explanation, systemImage: systemImage)
        }
        .tint(LXColor(role: .accentPrimary))
        .padding(.vertical, LX.Space.s200)
        .lxHaptic(.selection, trigger: isOn)
    }
}

struct LXSettingsRow: View {
    let title: String
    var explanation: String? = nil
    var systemImage: String? = nil
    var value: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack {
                LXRowLabel(title: title, explanation: explanation, systemImage: systemImage)
                Spacer(minLength: LX.Space.s200)
                if let value { Text(value).lxFont(.body, numeric: true).foregroundStyle(.lx(.textSecondary)) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.lx(.textTertiary))
            }
            .padding(.vertical, LX.Space.s200)
            .frame(minHeight: LX.Space.minTouchTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct LXRowLabel: View {
    let title: String
    var explanation: String?
    var systemImage: String?

    var body: some View {
        HStack(alignment: .top, spacing: LX.Space.s300) {
            if let systemImage {
                Image(systemName: systemImage).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.lx(.accentPrimary)).frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lxFont(.body).foregroundStyle(.lx(.textPrimary))
                if let explanation {
                    Text(explanation).lxFont(.footnote).foregroundStyle(.lx(.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
