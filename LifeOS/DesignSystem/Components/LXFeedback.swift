import SwiftUI

// Phase 2 §7 components 20–24, 27, 28.

// MARK: 20 · Empty state (one sentence, one action)

struct LXEmptyState: View {
    let systemImage: String
    let message: String
    var actionTitle: String? = nil
    var action: () -> Void = {}

    var body: some View {
        VStack(spacing: LX.Space.s300) {
            Image(systemName: systemImage).font(.system(size: 34, weight: .light)).symbolRenderingMode(.hierarchical)
                .foregroundStyle(.lx(.accentPrimary))
                .accessibilityHidden(true)
            Text(message).lxFont(.callout).foregroundStyle(.lx(.textSecondary)).multilineTextAlignment(.center)
            if let actionTitle {
                Button(actionTitle, action: action).buttonStyle(.lx(.secondary))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(LX.Space.s600)
    }
}

// MARK: 21 · Skeleton loader (shimmer that respects Reduce Motion)

struct LXSkeleton: View {
    var height: CGFloat = 16
    var width: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2.5, style: .continuous)
            .fill(.lx(.separator))
            .overlay {
                if !reduceMotion {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.18), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.6)
                            .offset(x: phase * geo.size.width)
                    }
                    .clipped()
                }
            }
            .frame(width: width, height: height)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.3).repeatForever(autoreverses: false)) { phase = 1.4 }
            }
            .accessibilityLabel("Loading")
    }
}

// MARK: 22 · Inline banner (info, attention, error; dismissible)

enum LXBannerKind: Sendable {
    case info, attention, error
    var role: LXColorRole { switch self { case .info: return .statusInfo; case .attention: return .statusAttention; case .error: return .statusCritical } }
    var icon: String { switch self { case .info: return "info.circle"; case .attention: return "exclamationmark.triangle"; case .error: return "xmark.octagon" } }
}

struct LXInlineBanner: View {
    let kind: LXBannerKind
    let message: String
    var actionTitle: String? = nil
    var action: () -> Void = {}
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: LX.Space.s300) {
            Image(systemName: kind.icon).foregroundStyle(.lx(kind.role))
            VStack(alignment: .leading, spacing: LX.Space.s100) {
                Text(message).lxFont(.subhead).foregroundStyle(.lx(.textPrimary)).fixedSize(horizontal: false, vertical: true)
                if let actionTitle {
                    Button(actionTitle, action: action).buttonStyle(.plain)
                        .lxFont(.subhead, weight: .semibold).foregroundStyle(.lx(.accentPrimary))
                }
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) { Image(systemName: "xmark").font(.footnote.weight(.semibold)).foregroundStyle(.lx(.textTertiary)) }
                    .buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
        }
        .padding(LX.Space.s300)
        .background(RoundedRectangle(cornerRadius: LX.Radius.tile, style: .continuous).fill(.lx(kind.role).opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: LX.Radius.tile, style: .continuous).strokeBorder(.lx(kind.role).opacity(0.35), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }
}

// MARK: 23 · Toast ("Logged · Undo", 4 s, swipe to dismiss)

struct LXToastModel: Identifiable, Equatable, Sendable {
    let id = UUID()
    var message: String
    var undoTitle: String? = "Undo"
}

struct LXToast: View {
    let model: LXToastModel
    var onUndo: () -> Void = {}

    var body: some View {
        HStack(spacing: LX.Space.s300) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.lx(.statusOnTrack))
            Text(model.message).lxFont(.subhead, numeric: true).foregroundStyle(.lx(.textPrimary)).lineLimit(2)
            Spacer(minLength: LX.Space.s200)
            if let undo = model.undoTitle {
                Button(undo, action: onUndo).buttonStyle(.plain)
                    .lxFont(.subhead, weight: .semibold).foregroundStyle(.lx(.accentPrimary))
            }
        }
        .padding(.horizontal, LX.Space.s400)
        .frame(minHeight: 52)
        .lxGlass(in: Capsule())
        .padding(.horizontal, LX.Space.s400)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

private struct LXToastHost: ViewModifier {
    @Binding var toast: LXToastModel?
    var onUndo: () -> Void
    @Environment(\.lxDirection) private var direction
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let t = toast {
                LXToast(model: t) { onUndo(); toast = nil }
                    .padding(.bottom, 96) // above the tab bar
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .gesture(DragGesture().onEnded { if $0.translation.height > 20 { toast = nil } })
                    .task(id: t.id) {
                        try? await Task.sleep(for: .seconds(4))
                        if toast?.id == t.id { toast = nil }
                    }
            }
        }
        .animation(LXMotion.smooth.animation(direction: direction, reduceMotion: reduceMotion), value: toast)
    }
}

extension View {
    /// Presents `LXToast` for 4 s; swipe down to dismiss.
    func lxToast(_ toast: Binding<LXToastModel?>, onUndo: @escaping () -> Void = {}) -> some View {
        modifier(LXToastHost(toast: toast, onUndo: onUndo))
    }
}

// MARK: 24 · AI proposal card

struct LXProposalItem: Identifiable, Equatable, Sendable {
    let id: String
    var name: String
    var amount: String
    var kcal: Int
    var confidence: LXConfidence
}

/// What the AI understood, with editable items, Log / Edit and confidence.
/// Low-confidence items are listed first with "Check portion" (Phase 3 §3.3).
struct LXProposalCard: View {
    var mealTitle: String
    var time: String
    var source: LXSource
    var items: [LXProposalItem]
    var macros: [LXMacroBar.Macro]
    var note: String? = nil
    var onLog: () -> Void = {}
    var onEdit: () -> Void = {}
    var onSavePreset: (() -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize

    private var sorted: [LXProposalItem] {
        items.sorted { rank($0.confidence) < rank($1.confidence) }
    }
    private var total: Int { items.reduce(0) { $0 + $1.kcal } }

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s400) {
            LXAdaptiveStack(spacing: LX.Space.s200) {
                LXChip(title: mealTitle, trailing: time)
                Spacer(minLength: 0)
                LXSourceBadge(source: source)
            }
            VStack(spacing: 0) {
                ForEach(sorted) { item in
                    HStack(spacing: LX.Space.s300) {
                        LXConfidenceDot(confidence: item.confidence)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).lxFont(.headline).foregroundStyle(.lx(.textPrimary))
                            if item.confidence == .low || !item.amount.isEmpty {
                                Text(item.confidence == .low ? (item.amount.isEmpty ? "Check portion" : "\(item.amount) · Check portion") : item.amount)
                                    .lxFont(.footnote).foregroundStyle(item.confidence == .low ? .lx(.statusAttention) : .lx(.textSecondary))
                            }
                        }
                        Spacer()
                        Text("\(item.kcal)").lxFont(.headline, numeric: true).foregroundStyle(.lx(.textPrimary))
                            .lxNumberRoll(Double(item.kcal))
                    }
                    .padding(.vertical, LX.Space.s200)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(item.name), \(item.amount), \(item.kcal) kilocalories, \(item.confidence.words)")
                }
            }
            LXAdaptiveStack(spacing: LX.Space.s200, alignment: .firstTextBaseline) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(total)").lxFont(.displayL, numeric: true).foregroundStyle(.lx(.textPrimary)).lxNumberRoll(Double(total))
                    Text("kcal").lxFont(.subhead).foregroundStyle(.lx(.textSecondary))
                }
                Spacer(minLength: 0)
                if let note { Text(note).lxFont(.footnote).foregroundStyle(.lx(.statusAttention)) }
            }
            LXMacroBar(macros: macros)
            if typeSize.isAccessibilitySize {
                // Primary action first and full width when stacked.
                VStack(spacing: LX.Space.s300) {
                    Button(action: onLog) { Text("Log \(total) kcal").frame(maxWidth: .infinity) }.buttonStyle(.lx(.primary))
                    Button(action: onEdit) { Text("Edit").frame(maxWidth: .infinity) }.buttonStyle(.lx(.secondary))
                }
            } else {
                HStack(spacing: LX.Space.s300) {
                    Button("Edit", action: onEdit).buttonStyle(.lx(.secondary))
                    Button(action: onLog) { Text("Log \(total) kcal").frame(maxWidth: .infinity) }.buttonStyle(.lx(.primary))
                }
            }
            if let onSavePreset {
                Button("Save as preset", action: onSavePreset).buttonStyle(.lx(.plain)).frame(maxWidth: .infinity)
            }
        }
        .lxCard(radius: LX.Radius.hero, padding: LX.Space.s500)
    }

    private func rank(_ c: LXConfidence) -> Int { switch c { case .low: return 0; case .medium: return 1; case .high: return 2 } }
}

// MARK: 27 · Photo card (meal photo with lift effect and items overlay)

struct LXPhotoCard: View {
    let image: Image
    var labels: [(text: String, at: UnitPoint)] = []
    var lifted = true

    var body: some View {
        // The photo fills whatever frame the caller gives; a scaled-to-fill image
        // must not size the card itself, or a wide photo overflows its frame.
        Color.clear.overlay {
            ZStack {
                image.resizable().scaledToFill()
                    .blur(radius: lifted ? 6 : 0)
                    .overlay(Color.black.opacity(lifted ? 0.35 : 0))
                if lifted {
                    image.resizable().scaledToFit()
                        .scaleEffect(1.04)
                        .shadow(color: .black.opacity(0.45), radius: 18, y: 14)
                }
                GeometryReader { geo in
                    ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                        Text(label.text).lxFont(.caption, weight: .semibold).foregroundStyle(.lx(.textPrimary))
                            .padding(.horizontal, 8).padding(.vertical, 4).lxGlass()
                            .position(x: geo.size.width * label.at.x, y: geo.size.height * label.at.y)
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: LX.Radius.hero, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Meal photo" + (labels.isEmpty ? "" : ": " + labels.map(\.text).joined(separator: ", ")))
    }
}

// MARK: 28 · Workout card

struct LXWorkoutCard: View {
    let title: String
    let durationMinutes: Int
    let earnedKcal: Int
    let time: String
    var systemImage: String = "figure.strengthtraining.traditional"
    var source: LXSource = .watch
    var isPlanned = false
    var highlight = false

    var body: some View {
        HStack(spacing: LX.Space.s300) {
            Image(systemName: systemImage)
                .font(.title3).foregroundStyle(.lx(.dataActivity))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: LX.Radius.chip, style: .continuous).fill(.lx(.dataActivity).opacity(isPlanned ? 0 : 0.14)))
                .overlay(RoundedRectangle(cornerRadius: LX.Radius.chip, style: .continuous).strokeBorder(.lx(.dataActivity).opacity(isPlanned ? 0.6 : 0), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(title), \(durationMinutes) min").lxFont(.headline).foregroundStyle(.lx(.textPrimary)).lineLimit(1)
                    Spacer(minLength: 6)
                    if isPlanned { LXChip(title: "Planned", kind: .neutral) } else { LXSourceBadge(source: source) }
                }
                if !isPlanned {
                    HStack(spacing: 6) {
                        // "+0 kcal earned" reads as a failure; with no credit the card just shows when.
                        if earnedKcal > 0 {
                            Text("+\(earnedKcal) kcal earned").lxFont(.subhead, numeric: true, weight: .semibold).foregroundStyle(.lx(.dataActivity))
                        }
                        Text(earnedKcal > 0 ? "· \(time)" : time).lxFont(.subhead, numeric: true).foregroundStyle(.lx(.textSecondary))
                    }
                    .lineLimit(1)
                }
            }
        }
        .lxCard(padding: LX.Space.s300 + 2)
        .overlay {
            if highlight {
                RoundedRectangle(cornerRadius: LX.Radius.card, style: .continuous).strokeBorder(.lx(.dataActivity).opacity(0.55), lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isPlanned ? "Planned \(title), \(durationMinutes) minutes" : "\(title), \(durationMinutes) minutes, \(earnedKcal > 0 ? "\(earnedKcal) kilocalories earned, " : "")at \(time), from \(source.rawValue)")
    }
}
