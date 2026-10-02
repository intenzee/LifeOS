import SwiftUI
#if canImport(RealityKit)
import RealityKit
#endif

/// Render tiers for 3D work (engineering roadmap 08 §3.7, UI-21).
enum LXRenderQuality: Sendable, Equatable {
    /// RealityKit orb (iOS 18+).
    case high
    /// Animated 2.5D Canvas orb.
    case medium
    /// Static 2.5D orb: Reduce Motion, Low Power Mode, serious thermal state.
    case low

    static func current(reduceMotion: Bool, prefersRealityKit: Bool = false) -> LXRenderQuality {
        let info = ProcessInfo.processInfo
        if reduceMotion || info.isLowPowerModeEnabled || info.thermalState == .serious || info.thermalState == .critical {
            return .low
        }
        if prefersRealityKit, #available(iOS 18.0, macOS 15.0, *) { return .high }
        return .medium
    }
}

/// Picks the right orb for the device and accessibility state. Feature code
/// uses this, never `LifeOrb`/`LifeOrbRealityView` directly.
struct AdaptiveLifeOrb: View {
    var state: LifeOrbState
    var size: CGFloat = LXTokens.Orb.heroSize
    /// The RealityKit path stays opt-in until the Reality Composer Pro material
    /// exists and passes the on-device frame-time check (Phase 2 §9.1).
    var prefersRealityKit = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch LXRenderQuality.current(reduceMotion: reduceMotion, prefersRealityKit: prefersRealityKit) {
        case .high:
            if #available(iOS 18.0, macOS 15.0, *) {
                LifeOrbRealityView(state: state, size: size)
            } else {
                LifeOrb(state: state, size: size)
            }
        case .medium:
            LifeOrb(state: state, size: size)
        case .low:
            LifeOrb(state: state, size: size, animated: false)
        }
    }
}

#if canImport(RealityKit)
/// Phase 1 feasibility spike: the orb in RealityKit with procedural meshes.
///
/// What it proves: a `RealityView` can host the hero, SwiftUI state updates
/// entity parameters without rebuilding the scene, and the scene tears down off
/// screen. What it does not do yet: the liquid surface. That needs the Reality
/// Composer Pro shader-graph material with `fillLevel`, `rimIntensity`, `tint` and
/// `wobble` inputs (Phase 2 §9.1), which requires Xcode. Until then the liquid
/// is a sphere scaled vertically, a placeholder only.
@available(iOS 18.0, macOS 15.0, *)
struct LifeOrbRealityView: View {
    var state: LifeOrbState
    var size: CGFloat = LXTokens.Orb.heroSize
    @Environment(\.lxTheme) private var theme

    var body: some View {
        RealityView { content in
            let root = Entity()
            root.name = "orb"

            var glass = PhysicallyBasedMaterial()
            glass.baseColor = .init(tint: .white.withAlphaComponent(0.15))
            glass.roughness = 0.05
            glass.metallic = 0.0
            glass.clearcoat = 1.0
            glass.blending = .transparent(opacity: 0.25)
            let shell = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [glass])
            shell.name = "shell"

            var liquidMaterial = PhysicallyBasedMaterial()
            liquidMaterial.baseColor = .init(tint: Self.platformColor(theme.orb.liquidTop))
            liquidMaterial.roughness = 0.2
            let liquid = ModelEntity(mesh: .generateSphere(radius: 0.46), materials: [liquidMaterial])
            liquid.name = "liquid"

            root.addChild(liquid)
            root.addChild(shell)
            content.add(root)
            Self.apply(state, to: root)
        } update: { content in
            if let root = content.entities.first(where: { $0.name == "orb" }) {
                Self.apply(state, to: root)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    /// Maps orb state onto entity transforms. Placeholder until the shader graph lands.
    static func apply(_ state: LifeOrbState, to root: Entity) {
        guard let liquid = root.findEntity(named: "liquid") else { return }
        let h = Float(max(state.liquidHeight, 0.001))
        liquid.scale = [1, h, 1]
        liquid.position = [0, -0.46 * (1 - h), 0]
    }

    #if canImport(UIKit)
    static func platformColor(_ hex: UInt32) -> UIColor {
        let c = LXRGB(hex: hex)
        return UIColor(red: c.r, green: c.g, blue: c.b, alpha: 1)
    }
    #else
    static func platformColor(_ hex: UInt32) -> NSColor {
        let c = LXRGB(hex: hex)
        return NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1)
    }
    #endif
}
#endif
