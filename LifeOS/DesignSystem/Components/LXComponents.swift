import SwiftUI

// Core components v1 (Phase 2 §7). Numbers in comments refer to that table.

// MARK: 1 · Buttons

enum LXButtonKind: Sendable { case primary, secondary, glass, plain, destructive }

struct LXButtonStyle: ButtonStyle {
    var kind: LXButtonKind = .primary
    var isLoading = false

    func makeBody(configuration: Configuration) -> some View {
        LXButtonBody(configuration: configuration, kind: kind, isLoading: isLoading)
    }
}

private struct LXButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let kind: LXButtonKind
    let isLoading: Bool
    @Environment(\.lxTheme) private var theme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let shape = Capsule()
        configuration.label
            .lxFont(.headline)
            .opacity(isLoading ? 0 : 1)
            .overlay { if isLoading { ProgressView().tint(foreground) } }
            .foregroundStyle(foreground)
            .padding(.horizontal, LX.Space.s500)
            .frame(minHeight: LX.Space.minTouchTarget + 6)
            .background { background(shape) }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .lxAnimation(.snappy, value: configuration.isPressed)
            .contentShape(shape)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return theme.color(.onAccent)
        case .secondary, .glass, .plain: return theme.color(kind == .plain ? .accentPrimary : .textPrimary)
        case .destructive: return theme.color(.statusCritical)
        }
    }

    @ViewBuilder private func background(_ shape: Capsule) -> some View {
        switch kind {
        case .primary: shape.fill(.lx(.accentPrimary))
        case .secondary: shape.fill(.lx(.surfaceRaised)).overlay(shape.stroke(.lx(.separator), lineWidth: 0.5))
        case .glass: Color.clear.lxGlass(in: shape, interactive: true)
        case .plain: Color.clear
        case .destructive: shape.fill(.lx(.statusCritical).opacity(0.12))
        }
    }
}

extension ButtonStyle where Self == LXButtonStyle {
    static func lx(_ kind: LXButtonKind, loading: Bool = false) -> LXButtonStyle { LXButtonStyle(kind: kind, isLoading: loading) }
}

// MARK: 2 · Icon button

struct LXIconButton: View {
    let systemImage: String
    let label: String
    var glass = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(.body, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.lx(.textPrimary))
                .frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
                .modifier(OptionalGlass(enabled: glass))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private struct OptionalGlass: ViewModifier {
        let enabled: Bool
        func body(content: Content) -> some View {
            if enabled { content.lxGlass(in: Circle(), interactive: true) } else { content }
        }
    }
}

// MARK: 5 · Chip

enum LXChipKind: Sendable { case filter(selected: Bool), suggestion, status(LXColorRole), neutral }

struct LXChip: View {
    let title: String
    var systemImage: String? = nil
    var kind: LXChipKind = .neutral
    var trailing: String? = nil

    @Environment(\.lxTheme) private var theme

    var body: some View {
        HStack(spacing: LX.Space.s100 + 2) {
            if let systemImage {
                Image(systemName: systemImage).imageScale(.small).symbolRenderingMode(.hierarchical)
            }
            Text(title).lxFont(.subhead, weight: .medium)
            if let trailing {
                Text(trailing).lxFont(.subhead, numeric: true).foregroundStyle(.lx(.textSecondary))
            }
        }
        .foregroundStyle(foreground)
        .padding(.horizontal, LX.Space.s300)
        .padding(.vertical, LX.Space.s200)
        .frame(minHeight: 36)
        .background(RoundedRectangle(cornerRadius: LX.Radius.chip, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: LX.Radius.chip, style: .continuous).strokeBorder(stroke, lineWidth: 0.5))
    }

    private var foreground: Color {
        switch kind {
        case .filter(let s): return theme.color(s ? .onAccent : .textPrimary)
        case .suggestion: return theme.color(.textPrimary)
        case .status(let role): return theme.color(role)
        case .neutral: return theme.color(.textPrimary)
        }
    }

    private var fill: Color {
        switch kind {
        case .filter(let s): return s ? theme.color(.accentPrimary) : theme.color(.surfaceRaised)
        case .suggestion: return theme.color(.accentPrimary).opacity(0.10)
        case .status(let role): return theme.color(role).opacity(0.12)
        case .neutral: return theme.color(.surfaceRaised)
        }
    }

    private var stroke: Color {
        switch kind {
        case .suggestion: return theme.color(.accentPrimary).opacity(0.35)
        default: return theme.color(.separator)
        }
    }
}

// MARK: 10 · Section header

struct LXSectionHeader: View {
    let title: String
    var action: String? = nil
    var onAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).lxFont(.title3).foregroundStyle(.lx(.textPrimary))
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let action {
                Button(action, action: { onAction?() }).buttonStyle(.plain)
                    .lxFont(.subhead, weight: .medium).foregroundStyle(.lx(.accentPrimary))
            }
        }
    }
}

// MARK: 12 · Metric tile

struct LXMetricTile: View {
    let label: String
    let value: String
    var unit: String? = nil
    let systemImage: String
    let dataRole: LXColorRole
    /// 0…1 progress hint; nil hides the bar.
    var progress: Double? = nil
    var caption: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s200) {
            HStack(spacing: LX.Space.s100 + 2) {
                Image(systemName: systemImage).symbolRenderingMode(.hierarchical).foregroundStyle(.lx(dataRole))
                Text(label).lxFont(.footnote, weight: .medium).foregroundStyle(.lx(.textSecondary))
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).lxFont(.title2, numeric: true).foregroundStyle(.lx(.textPrimary))
                if let unit { Text(unit).lxFont(.footnote).foregroundStyle(.lx(.textSecondary)) }
            }
            if let progress { LXProgressBar(value: progress, role: dataRole) }
            if let caption { Text(caption).lxFont(.caption).foregroundStyle(.lx(.textSecondary)).lineLimit(1) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lxCard(radius: LX.Radius.tile, padding: LX.Space.s300 + 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)\(unit.map { " \($0)" } ?? "")\(caption.map { ". \($0)" } ?? "")")
    }
}

// MARK: Progress bar (used by tiles and macro bar)

struct LXProgressBar: View {
    var value: Double
    var role: LXColorRole
    var height: CGFloat = 6

    var body: some View {
        let v = value.isFinite ? min(max(value, 0), 1) : 0
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.lx(.separator))
                Capsule().fill(.lx(role)).frame(width: max(height, geo.size.width * v))
                    .opacity(v > 0 ? 1 : 0)
            }
        }
        .frame(height: height)
        .lxAnimation(.gentle, value: v)
        .accessibilityHidden(true)
    }
}

// MARK: 14 · Macro bar

struct LXMacroBar: View {
    struct Macro: Identifiable, Sendable {
        let name: String, grams: Double, target: Double, role: LXColorRole
        var id: String { name }
    }
    let macros: [Macro]

    var body: some View {
        HStack(spacing: LX.Space.s400) {
            ForEach(macros) { m in
                VStack(alignment: .leading, spacing: LX.Space.s100 + 2) {
                    HStack(spacing: 4) {
                        Circle().fill(.lx(m.role)).frame(width: 7, height: 7)
                        Text(m.name).lxFont(.caption).foregroundStyle(.lx(.textSecondary))
                    }
                    Text("\(Int(m.grams.rounded())) g").lxFont(.headline, numeric: true).foregroundStyle(.lx(.textPrimary))
                    LXProgressBar(value: m.target > 0 ? m.grams / m.target : 0, role: m.role, height: 4)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(m.name), \(Int(m.grams.rounded())) grams of \(Int(m.target)) target")
            }
        }
    }
}

// MARK: 26 · Source badge

enum LXSource: String, Sendable {
    case onDevice = "On device", watch = "Apple Watch", photo = "Photo", voice = "Voice", preset = "Preset", groq = "Groq", gemini = "Gemini", manual = "Logged in LifeOS"

    var systemImage: String {
        switch self {
        case .onDevice: return "sparkles"
        case .watch: return "applewatch"
        case .photo: return "camera.fill"
        case .voice: return "waveform"
        case .preset: return "star.square.on.square"
        case .groq, .gemini: return "cloud"
        case .manual: return "square.and.pencil"
        }
    }
}

struct LXSourceBadge: View {
    let source: LXSource

    var body: some View {
        Label(source.rawValue, systemImage: source.systemImage)
            .labelStyle(.titleAndIcon)
            .lxFont(.caption)
            .foregroundStyle(.lx(.textSecondary))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(.lx(.surfaceRaised)))
            .overlay(Capsule().strokeBorder(.lx(.separator), lineWidth: 0.5))
            .accessibilityLabel("Source: \(source.rawValue)")
    }
}

// MARK: 25 · Confidence indicator

enum LXConfidence: Sendable {
    case high, medium, low
    var role: LXColorRole { switch self { case .high: return .statusOnTrack; case .medium: return .statusAttention; case .low: return .statusOver } }
    var words: String { switch self { case .high: return "Confident"; case .medium: return "Likely"; case .low: return "Check portion" } }
}

struct LXConfidenceDot: View {
    let confidence: LXConfidence
    var body: some View {
        Circle().fill(.lx(confidence.role)).frame(width: 8, height: 8)
            .accessibilityLabel(confidence.words)
    }
}

// MARK: 17 · Budget explainer chip

struct LXBudgetChip: View {
    let base: Int
    let earned: Int

    var body: some View {
        HStack(spacing: 6) {
            Text("\(base.formatted()) base").foregroundStyle(.lx(.textSecondary))
            Text("+").foregroundStyle(.lx(.textTertiary))
            Image(systemName: "flame.fill").imageScale(.small).foregroundStyle(.lx(.dataActivity))
            Text("\(earned) earned").foregroundStyle(.lx(.textPrimary))
            Image(systemName: "chevron.right").imageScale(.small).foregroundStyle(.lx(.textTertiary))
        }
        .lxFont(.subhead, numeric: true)
        .padding(.horizontal, LX.Space.s300)
        .padding(.vertical, LX.Space.s200)
        .lxGlass()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Budget: \(base) base plus \(earned) earned from activity")
        .accessibilityHint("Shows how your budget is calculated")
    }
}
