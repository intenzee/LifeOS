import SwiftUI

/// Everything the Life Orb shows (Phase 2 §9.1). Pure data, so it can be
/// unit-tested and fed by any screen, widget or the Watch.
struct LifeOrbState: Equatable, Sendable {
    /// Calories eaten ÷ today's budget. 0…1.2 (clamped); above 1 the liquid tints `status.over`.
    var fillLevel: Double
    /// Activity calories earned, normalised 0…1 — drives rim brightness.
    var rimIntensity: Double = 0
    /// Liquid surface agitation 0…1 (touch, a new log).
    var wobble: Double = 0
    /// Data is old ("Updated 2 h ago"): slight desaturation.
    var isStale: Bool = false
    /// Macro shares for the tap-to-split layers; nil hides them.
    var macroLayers: MacroLayers? = nil

    struct MacroLayers: Equatable, Sendable {
        var proteinG: Double, carbsG: Double, fatG: Double

        /// kcal share of each macro (4/4/9 kcal per gram), summing to 1 (or all 0).
        nonisolated var shares: (protein: Double, carbs: Double, fat: Double) {
            let p = max(proteinG, 0) * 4, c = max(carbsG, 0) * 4, f = max(fatG, 0) * 9
            let total = p + c + f
            guard total > 0 else { return (0, 0, 0) }
            return (p / total, c / total, f / total)
        }
    }

    nonisolated init(fillLevel: Double, rimIntensity: Double = 0, wobble: Double = 0, isStale: Bool = false, macroLayers: MacroLayers? = nil) {
        self.fillLevel = fillLevel
        self.rimIntensity = rimIntensity
        self.wobble = wobble
        self.isStale = isStale
        self.macroLayers = macroLayers
    }

    /// Builds a state from budget numbers, guarding the zero-budget case (the old ring went NaN).
    nonisolated static func budget(eaten: Double, budget: Double, earned: Double, earnedForFullRim: Double = 600) -> LifeOrbState {
        let fill = budget > 0 ? eaten / budget : 0
        let rim = earnedForFullRim > 0 ? earned / earnedForFullRim : 0
        return LifeOrbState(fillLevel: fill, rimIntensity: rim)
    }

    nonisolated var clampedFill: Double {
        guard fillLevel.isFinite else { return 0 }
        return min(max(fillLevel, 0), Double(LXTokens.Orb.maxFill))
    }

    nonisolated var clampedRim: Double {
        guard rimIntensity.isFinite else { return 0 }
        return min(max(rimIntensity, 0), 1)
    }

    nonisolated var isOver: Bool { clampedFill > 1 }

    /// Visible liquid height inside the glass, 0…1. Above budget the glass is full
    /// and the overflow is shown by tint and ripple, not height.
    nonisolated var liquidHeight: Double { min(clampedFill, 1) * 0.92 + (clampedFill > 0 ? 0.04 : 0) }
}

/// The signature hero object: a glass sphere that fills like liquid as you eat.
/// 2.5D SwiftUI `Canvas` implementation (iOS 17+). It is the fallback for the
/// RealityKit orb and is cheap enough to be the default.
struct LifeOrb: View {
    var state: LifeOrbState
    var size: CGFloat = LXTokens.Orb.heroSize
    /// Allow idle breathing and liquid motion. Turned off automatically for Reduce Motion,
    /// Low Power Mode and when the view is off screen.
    var animated: Bool = true
    /// A fixed time for deterministic renders (snapshots, mockups).
    var frozenTime: Double? = nil

    @Environment(\.lxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @State private var isVisible = false

    private var isLive: Bool {
        animated && frozenTime == nil && isVisible && !reduceMotion && !ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 120.0, paused: !isLive)) { context in
            let t = frozenTime ?? (isLive ? context.date.timeIntervalSinceReferenceDate : 0)
            let breath = isLive ? 1 + (Double(LXTokens.Orb.breathScale) - 1) * (0.5 + 0.5 * sin(t * 2 * .pi / Double(LXTokens.Orb.breathPeriod))) : 1
            Canvas(rendersAsynchronously: false) { ctx, canvasSize in
                LifeOrbRenderer(state: state, theme: theme, time: t, solidShell: reduceTransparency).draw(in: &ctx, size: canvasSize)
            }
            // The canvas overflows the layout frame so the rim-glow halo fades out
            // completely instead of being clipped into a visible square.
            .frame(width: size * LifeOrbRenderer.canvasScale, height: size * LifeOrbRenderer.canvasScale)
            .scaleEffect(breath)
        }
        .frame(width: size, height: size)
        .saturation(state.isStale ? 0.55 : 1)
        .opacity(state.isStale ? 0.85 : 1)
        .overlay { if let layers = state.macroLayers { MacroLayerOverlay(layers: layers, size: size) } }
        .animation(LXMotion.gentle.animation(direction: theme.direction, reduceMotion: reduceMotion), value: state)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
        .accessibilityHidden(true) // The screen supplies the spoken equivalent.
    }
}

/// Stateless drawing so it can be timed and snapshot-tested on its own.
struct LifeOrbRenderer {
    let state: LifeOrbState
    let theme: LXTheme
    let time: Double
    var solidShell = false

    /// Canvas size ÷ layout size. Leaves room for the glow (≈0.22 d beyond the glass).
    static let canvasScale: CGFloat = 1.4

    /// `size` is the canvas size; the orb occupies the central 1/canvasScale of it.
    func draw(in ctx: inout GraphicsContext, size: CGSize) {
        let d = min(size.width, size.height) / Self.canvasScale
        let pad = d * 0.08 // room for the rim glow
        let rect = CGRect(x: (size.width - d) / 2 + pad, y: (size.height - d) / 2 + pad, width: d - pad * 2, height: d - pad * 2)
        let sphere = Path(ellipseIn: rect)
        let orb = theme.orb
        let dark = theme.colorScheme == .dark
        let rim = Color(lxHex: orb.rim)

        // 1. Rim glow (activity earned): blurred ring outside the glass.
        if state.clampedRim > 0.01 {
            var glow = ctx
            glow.addFilter(.blur(radius: d * 0.045))
            glow.stroke(sphere, with: .color(rim.opacity(0.25 + 0.55 * state.clampedRim)), lineWidth: d * (0.02 + 0.03 * state.clampedRim))
        }

        // 2. Contact shadow under the sphere.
        var shadow = ctx
        shadow.addFilter(.blur(radius: d * 0.04))
        shadow.fill(Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.18, y: rect.maxY - rect.height * 0.02, width: rect.width * 0.64, height: rect.height * 0.07)),
                    with: .color(.black.opacity(dark ? 0.55 : 0.18)))

        // 3. Glass body (back face).
        let shellTop: Color, shellBottom: Color
        switch orb.shell {
        case "smoked": shellTop = Color(white: dark ? 0.20 : 0.92, opacity: dark ? 0.55 : 0.85); shellBottom = Color(white: dark ? 0.06 : 0.62, opacity: dark ? 0.70 : 0.55)
        case "frosted": shellTop = Color(white: 1, opacity: dark ? 0.16 : 0.85); shellBottom = Color(white: dark ? 0.55 : 0.90, opacity: dark ? 0.10 : 0.65)
        default: shellTop = Color(white: 1, opacity: dark ? 0.10 : 0.55); shellBottom = Color(white: 1, opacity: dark ? 0.03 : 0.25)
        }
        if solidShell {
            ctx.fill(sphere, with: .color(theme.color(.surfaceRaised)))
        } else {
            ctx.fill(sphere, with: .radialGradient(Gradient(colors: [shellTop, shellBottom]),
                                                   center: CGPoint(x: rect.midX - rect.width * 0.15, y: rect.minY + rect.height * 0.3),
                                                   startRadius: 0, endRadius: rect.width * 0.75))
        }

        // 4. Liquid, clipped to the inside of the glass.
        let inner = rect.insetBy(dx: d * 0.035, dy: d * 0.035)

        // 4a. "Ready" state: when the glass is empty (or nearly so) a bare dark
        // sphere reads as broken, so we fill the void with a soft accent glow and
        // a faint pooled base. Both fade out as real liquid rises, so a fed day
        // looks exactly as before.
        let emptiness = max(0, 1 - state.clampedFill / 0.22)
        if emptiness > 0.01 {
            let rimC = Color(lxHex: orb.rim)
            let liquidC = Color(lxHex: orb.liquidTop)
            // Gentle breathing glow nested in the lower-centre of the glass, so an
            // empty vessel looks charged and ready rather than switched off.
            let pulse = 0.82 + 0.18 * sin(time * 2 * .pi / 3.2)
            var glow = ctx
            glow.clip(to: Path(ellipseIn: inner))
            glow.addFilter(.blur(radius: d * 0.11))
            let glowCenter = CGPoint(x: inner.midX, y: inner.minY + inner.height * 0.60)
            glow.fill(Path(ellipseIn: inner),
                      with: .radialGradient(
                        Gradient(colors: [liquidC.opacity((dark ? 0.38 : 0.24) * emptiness * pulse),
                                          liquidC.opacity((dark ? 0.16 : 0.10) * emptiness),
                                          .clear]),
                        center: glowCenter, startRadius: 0, endRadius: inner.width * 0.66))
            // A shallow resting pool so there's always a liquid surface to read.
            var pool = ctx
            pool.clip(to: Path(ellipseIn: inner))
            let poolLevel = inner.maxY - inner.height * 0.07
            let poolAmp = inner.height * 0.012
            let poolBody = wave(in: inner, level: poolLevel, amplitude: poolAmp, phase: time * 1.2, frequency: 1.1)
            pool.fill(poolBody, with: .linearGradient(
                Gradient(colors: [liquidC.opacity(0.42 * emptiness), liquidC.opacity(0.18 * emptiness)]),
                startPoint: CGPoint(x: inner.midX, y: poolLevel), endPoint: CGPoint(x: inner.midX, y: inner.maxY)))
            // Meniscus highlight on the resting pool — the detail that makes it glass.
            pool.stroke(surfaceLine(in: inner, level: poolLevel, amplitude: poolAmp, phase: time * 1.2, frequency: 1.1),
                        with: .color(rimC.opacity(0.55 * emptiness)), lineWidth: max(1, d * 0.005))
            // Lift the rim so the empty silhouette is crisply defined.
            ctx.stroke(sphere, with: .color(rimC.opacity(0.14 * emptiness)), lineWidth: max(1, d * 0.01))
        }

        if state.clampedFill > 0 {
            var liquid = ctx
            liquid.clip(to: Path(ellipseIn: inner))
            let level = inner.maxY - inner.height * state.liquidHeight
            let amp = inner.height * (0.012 + 0.03 * min(max(state.wobble, 0), 1) + (state.isOver ? 0.012 : 0))
            let top = Color(lxHex: orb.liquidTop), bottom = Color(lxHex: orb.liquidBottom)
            let over = theme.color(.statusOver)
            let back = wave(in: inner, level: level - amp * 0.6, amplitude: amp * 0.8, phase: time * 1.3 + 1.7, frequency: 1.6)
            liquid.fill(back, with: .color((state.isOver ? over : top).opacity(0.45)))
            let front = wave(in: inner, level: level, amplitude: amp, phase: time * 1.9, frequency: 1.15)
            liquid.fill(front, with: .linearGradient(
                Gradient(colors: state.isOver ? [over, over.opacity(0.85)] : [top, bottom]),
                startPoint: CGPoint(x: inner.midX, y: level), endPoint: CGPoint(x: inner.midX, y: inner.maxY)))
            // Meniscus: a thin bright line on the liquid surface.
            liquid.stroke(surfaceLine(in: inner, level: level, amplitude: amp, phase: time * 1.9, frequency: 1.15),
                          with: .color(.white.opacity(dark ? 0.55 : 0.7)), lineWidth: max(1, d * 0.006))
            // Inner depth: darken the bottom of the liquid.
            liquid.fill(Path(inner), with: .radialGradient(Gradient(colors: [.clear, .black.opacity(dark ? 0.35 : 0.18)]),
                                                           center: CGPoint(x: inner.midX, y: inner.minY + inner.height * 0.35),
                                                           startRadius: inner.width * 0.35, endRadius: inner.width * 0.7))
        }

        // 5. Glass front: edge refraction and specular highlight.
        ctx.stroke(sphere, with: .linearGradient(Gradient(colors: [.white.opacity(dark ? 0.55 : 0.9), .white.opacity(0.05), rim.opacity(0.35 + 0.4 * state.clampedRim)]),
                                                 startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)),
                   lineWidth: max(1, d * 0.008))
        var spec = ctx
        spec.addFilter(.blur(radius: d * 0.012))
        spec.fill(Path(ellipseIn: CGRect(x: rect.minX + rect.width * 0.2, y: rect.minY + rect.height * 0.07, width: rect.width * 0.34, height: rect.height * 0.16)),
                  with: .linearGradient(Gradient(colors: [.white.opacity(0.75), .white.opacity(0)]),
                                        startPoint: CGPoint(x: rect.midX, y: rect.minY), endPoint: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.25)))
    }

    private func wave(in r: CGRect, level: CGFloat, amplitude: CGFloat, phase: Double, frequency: Double) -> Path {
        var p = surfaceLine(in: r, level: level, amplitude: amplitude, phase: phase, frequency: frequency)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }

    private func surfaceLine(in r: CGRect, level: CGFloat, amplitude: CGFloat, phase: Double, frequency: Double) -> Path {
        var p = Path()
        let steps = 48
        for i in 0...steps {
            let x = r.minX + r.width * CGFloat(i) / CGFloat(steps)
            let u = Double(i) / Double(steps)
            let y = level + amplitude * CGFloat(sin(u * 2 * .pi * frequency + phase))
            i == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
        }
        return p
    }
}

/// Tap-to-split: three stacked translucent bands labelled with grams.
private struct MacroLayerOverlay: View {
    let layers: LifeOrbState.MacroLayers
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let s = layers.shares
        let bands: [(String, Double, Double, LXColorRole)] = [
            ("Fat", layers.fatG, s.fat, .dataFat),
            ("Carbs", layers.carbsG, s.carbs, .dataCarbs),
            ("Protein", layers.proteinG, s.protein, .dataProtein),
        ]
        let inner = size * 0.77 // matches the renderer's glass interior
        let showLabels = size >= 150
        VStack(spacing: 1.5) {
            ForEach(bands, id: \.0) { name, grams, share, role in
                ZStack {
                    Rectangle().fill(.lx(role))
                    if showLabels {
                        HStack(spacing: 4) {
                            Text(name).lxFont(.caption, weight: .semibold)
                            Text("\(Int(grams.rounded())) g").lxFont(.caption, numeric: true)
                        }
                        .lineLimit(1)
                        .fixedSize()
                        // Data colours are ≥ 4.5:1 against the scheme's extreme (light-mode
                        // data colours are dark, dark-mode ones light), so the label uses it.
                        .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
                    }
                }
                .frame(height: max(4, inner * share))
            }
        }
        .frame(width: inner, height: inner)
        .clipShape(Circle())
        .frame(width: size, height: size)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Protein \(Int(layers.proteinG)) grams, carbs \(Int(layers.carbsG)) grams, fat \(Int(layers.fatG)) grams")
    }
}
