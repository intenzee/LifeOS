import SwiftUI

// Phase 2 §7 components 9, 11, 30.

// MARK: 11 · Card (hero, standard, compact)

enum LXCardSize: Sendable { case hero, standard, compact
    var radius: CGFloat { self == .compact ? LX.Radius.tile : (self == .hero ? LX.Radius.hero : LX.Radius.card) }
    var padding: CGFloat { switch self { case .hero: return LX.Space.s600; case .standard: return LX.Space.s400; case .compact: return LX.Space.s300 } }
}

/// Card container. Pass `zoomID` + `namespace` to source an iOS 18 zoom transition
/// to its detail screen (master plan §5).
struct LXCard<Content: View>: View {
    var size: LXCardSize = .standard
    var title: String? = nil
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: LX.Space.s300) {
            if title != nil || subtitle != nil {
                VStack(alignment: .leading, spacing: 2) {
                    if let title { Text(title).lxFont(size == .hero ? .title2 : .headline).foregroundStyle(.lx(.textPrimary)) }
                    if let subtitle { Text(subtitle).lxFont(.footnote).foregroundStyle(.lx(.textSecondary)) }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .lxCard(radius: size.radius, padding: size.padding)
    }
}

extension View {
    /// Marks a card as the source of a zoom transition (iOS 18+); no-op before.
    @ViewBuilder
    func lxZoomSource(id: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
        #else
        self
        #endif
    }

    /// The destination side of `lxZoomSource`.
    @ViewBuilder
    func lxZoomDestination(id: some Hashable, in namespace: Namespace.ID) -> some View {
        #if os(iOS)
        if #available(iOS 18.0, *) {
            navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
        #else
        self
        #endif
    }
}

// MARK: 9 · List row (title, subtitle, value, icon, accessory, swipe actions)

struct LXListRow: View {
    let title: String
    var subtitle: String? = nil
    var value: String? = nil
    var valueCaption: String? = nil
    var systemImage: String? = nil
    var iconRole: LXColorRole = .accentPrimary
    var source: LXSource? = nil
    var showsChevron = false

    var body: some View {
        HStack(spacing: LX.Space.s300) {
            if let systemImage {
                Image(systemName: systemImage).symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.lx(iconRole))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(.lx(iconRole).opacity(0.12)))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).lxFont(.headline).foregroundStyle(.lx(.textPrimary)).lineLimit(2)
                if let subtitle { Text(subtitle).lxFont(.footnote, numeric: true).foregroundStyle(.lx(.textSecondary)) }
            }
            Spacer(minLength: LX.Space.s200)
            VStack(alignment: .trailing, spacing: 3) {
                if let value { Text(value).lxFont(.headline, numeric: true).foregroundStyle(.lx(.textPrimary)) }
                if let valueCaption { Text(valueCaption).lxFont(.caption, numeric: true).foregroundStyle(.lx(.textTertiary)) }
                if let source { LXSourceBadge(source: source) }
            }
            if showsChevron {
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.lx(.textTertiary))
            }
        }
        .padding(.vertical, LX.Space.s200)
        .frame(minHeight: LX.Space.minTouchTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension View {
    /// Standard destructive swipe: delete is followed by an Undo toast (audit A15),
    /// never a confirmation dialog for single, reversible items.
    func lxDeleteSwipe(_ onDelete: @escaping () -> Void) -> some View {
        swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) { Label("Delete", systemImage: "trash") }
        }
    }
}

// MARK: 30 · Sheet header (title, close, primary action, grabber)

struct LXSheetHeader: View {
    let title: String
    var primaryTitle: String? = nil
    var primaryEnabled = true
    var onClose: () -> Void
    var onPrimary: () -> Void = {}

    var body: some View {
        HStack {
            LXIconButton(systemImage: "xmark", label: "Close", glass: false, action: onClose)
            Spacer()
            Text(title).lxFont(.title3).foregroundStyle(.lx(.textPrimary)).accessibilityAddTraits(.isHeader)
            Spacer()
            if let primaryTitle {
                Button(primaryTitle, action: onPrimary)
                    .buttonStyle(.lx(.plain))
                    .disabled(!primaryEnabled)
            } else {
                Color.clear.frame(width: LX.Space.minTouchTarget, height: LX.Space.minTouchTarget)
            }
        }
        .padding(.horizontal, LX.Space.s300)
        .padding(.top, LX.Space.s200)
    }
}

extension View {
    /// Native sheet presentation with LifeOS defaults: detents, grabber, sheet radius (fixes A5).
    func lxSheetStyle(detents: Set<PresentationDetent> = [.medium, .large]) -> some View {
        presentationDetents(detents)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(LX.Radius.sheet)
            .presentationBackground(LXColor(role: .surfaceRaised))
    }
}
