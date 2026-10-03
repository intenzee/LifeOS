import SwiftUI
import WatchKit

/// Watch Water (UI/UX Phase 5 §2): one big +1, the Digital Crown adjusts,
/// a glass that fills, and a tap of haptic per glass.
struct WatchWaterView: View {
    @ObservedObject var session: WatchSessionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var crown: Double = 0
    @State private var shown = 0
    @State private var commit: Task<Void, Never>?

    private var snapshot: WatchSnapshot { session.snapshot }
    private let maxGlasses = 12 // same cap as the phone

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                glass
                    .frame(width: 46, height: 66)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(shown)").font(WatchTheme.number(34))
                    Text("of \(snapshot.waterTarget) glasses").font(.system(size: 11)).foregroundStyle(WatchTheme.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Water, \(shown) of \(snapshot.waterTarget) glasses")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: set(shown + 1)
                case .decrement: set(shown - 1)
                @unknown default: break
                }
            }

            Button { set(shown + 1) } label: {
                Label("Glass", systemImage: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.borderedProminent)
            .tint(WatchTheme.water)
            .disabled(shown >= maxGlasses)
            .accessibilityLabel("Add a glass")

            Text("Turn the Crown to correct").font(.system(size: 10)).foregroundStyle(WatchTheme.secondary)
        }
        .padding(.horizontal, 6)
        .focusable(true)
        .digitalCrownRotation($crown, from: 0, through: Double(maxGlasses), by: 1, sensitivity: .low, isContinuous: false)
        .onChange(of: crown) { _, value in
            let n = Int(value.rounded())
            if n != shown { set(n) }
        }
        .onAppear { sync() }
        .onChange(of: snapshot.waterCount) { _, _ in if commit == nil { sync() } }
        .navigationTitle("Water")
    }

    private var glass: some View {
        let level = snapshot.waterTarget > 0 ? min(Double(shown) / Double(snapshot.waterTarget), 1) : 0
        return ZStack(alignment: .bottom) {
            GlassShape().stroke(WatchTheme.water, lineWidth: 2)
            GlassShape()
                .fill(LinearGradient(colors: [WatchTheme.water, WatchTheme.water.opacity(0.55)], startPoint: .bottom, endPoint: .top))
                .mask(alignment: .bottom) {
                    GeometryReader { geo in
                        Rectangle().frame(height: geo.size.height * level).frame(maxHeight: .infinity, alignment: .bottom)
                    }
                }
                .padding(3)
                .animation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.2), value: level)
        }
        .accessibilityHidden(true)
    }

    private func sync() {
        shown = snapshot.waterCount
        crown = Double(snapshot.waterCount)
    }

    /// Show the change at once with a haptic per glass; send it to the iPhone after the Crown settles.
    private func set(_ n: Int) {
        let next = max(0, min(n, maxGlasses))
        guard next != shown else { return }
        WKInterfaceDevice.current().play(next > shown ? .click : .directionDown)
        shown = next
        crown = Double(next)
        commit?.cancel()
        commit = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            session.setWater(next)
            commit = nil
        }
    }
}

/// A tumbler: slightly narrower at the base.
private struct GlassShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let inset = r.width * 0.12
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + inset, y: r.maxY))
        p.closeSubpath()
        return p
    }
}
