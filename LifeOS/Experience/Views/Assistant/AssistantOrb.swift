import SwiftUI

/// The assistant orb (Phase 4 §4.1): Life Orb material tinted with the accent.
/// 32 pt in the input bar, 120 pt in an empty conversation. Inputs: audio level
/// (listening) and phase. Reduce Motion: static orb with a small indicator.
struct AssistantOrb: View {
    enum Phase: Equatable { case idle, listening, thinking, speaking }

    var phase: Phase = .idle
    var level: Double = 0
    var size: CGFloat = 32

    @Environment(\.lxTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                orb(time: 0)
                    .overlay(alignment: .bottomTrailing) {
                        if phase == .thinking || phase == .listening {
                            ProgressView().controlSize(.mini).offset(x: 4, y: 4)
                        }
                    }
            } else {
                TimelineView(.animation(minimumInterval: 1 / 60, paused: phase == .idle)) { ctx in
                    orb(time: ctx.date.timeIntervalSinceReferenceDate)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func orb(time t: Double) -> some View {
        let accent = theme.color(.accentPrimary)
        let glow = theme.color(.heroGlowB)
        let breath: Double = {
            switch phase {
            case .idle: return 1
            case .thinking: return 1 + 0.05 * sin(t * 2 * .pi / 1.6)
            case .speaking: return 1 + 0.03 * sin(t * 2 * .pi / 0.7)
            case .listening: return 1 + 0.18 * level
            }
        }()
        return Canvas { ctx, sz in
            let r = min(sz.width, sz.height) / 2
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
            ctx.fill(Path(ellipseIn: rect), with: .radialGradient(Gradient(colors: [accent.opacity(0.95), accent.opacity(0.55), glow.opacity(0.35)]),
                                                                  center: CGPoint(x: c.x - r * 0.25, y: c.y - r * 0.3), startRadius: 0, endRadius: r * 1.2))
            // Two drifting light blobs inside the glass.
            for k in 0..<2 {
                let a = t * (0.6 + Double(k) * 0.35) + Double(k) * 2.1
                let p = CGPoint(x: c.x + cos(a) * r * 0.35, y: c.y + sin(a * 1.3) * r * 0.3)
                let br = r * (0.55 - Double(k) * 0.15)
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - br, y: p.y - br, width: 2 * br, height: 2 * br)),
                         with: .radialGradient(Gradient(colors: [LXLight.specular.opacity(0.35), .clear]), center: p, startRadius: 0, endRadius: br))
            }
            // Rim and specular highlight.
            ctx.stroke(Path(ellipseIn: rect.insetBy(dx: 0.5, dy: 0.5)), with: .color(.white.opacity(0.35)), lineWidth: max(0.5, r * 0.03))
            let hl = CGRect(x: c.x - r * 0.55, y: c.y - r * 0.75, width: r * 0.7, height: r * 0.4)
            ctx.fill(Path(ellipseIn: hl), with: .linearGradient(Gradient(colors: [.white.opacity(0.55), .clear]),
                                                                startPoint: CGPoint(x: hl.midX, y: hl.minY), endPoint: CGPoint(x: hl.midX, y: hl.maxY)))
        }
        .scaleEffect(breath)
        .background {
            if phase == .listening {
                Circle().fill(accent.opacity(0.18)).scaleEffect(1.15 + level * 0.5)
            }
        }
        .animation(.easeOut(duration: 0.12), value: level)
    }
}
