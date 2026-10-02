import Foundation
import SwiftUI
import Testing
@testable import LifeOSDesign
#if canImport(AppKit)
import AppKit
#endif

/// Renders every Phase 1 artefact in every direction (and both colour schemes)
/// to PNG. Runs only when LX_RENDER_DIR is set, so normal `swift test` stays fast.
///
///     LX_RENDER_DIR=docs/uiux-plan/phase1/renders swift test --filter Render
@Suite struct RenderMockups {
    nonisolated static var outputDir: URL? {
        ProcessInfo.processInfo.environment["LX_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    @Test(.enabled(if: RenderMockups.outputDir != nil))
    func renderAllArtefacts() throws {
        let dir = try #require(Self.outputDir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for direction in LXDirection.allCases {
            for scheme in [ColorScheme.dark, .light] {
                for artefact in LXMockArtefact.allCases {
                    let view = artefact.view
                        .frame(width: artefact.size.width, height: artefact.size.height)
                        .lxDirection(direction)
                        .environment(\.colorScheme, scheme)
                        .environment(\.lxSnapshotMode, true)
                    let name = "\(direction.rawValue)-\(scheme == .dark ? "dark" : "light")-\(artefact.rawValue).png"
                    try writePNG(view, scale: 2, to: dir.appendingPathComponent(name))
                }
            }
        }
    }

    @Test(.enabled(if: RenderMockups.outputDir != nil))
    func renderOrbStates() throws {
        let dir = try #require(Self.outputDir)
        let states: [(String, LifeOrbState)] = [
            ("empty", LifeOrbState(fillLevel: 0)),
            ("25", LifeOrbState(fillLevel: 0.25)),
            ("50", LifeOrbState(fillLevel: 0.5, rimIntensity: 0.3)),
            ("75", LifeOrbState(fillLevel: 0.75, rimIntensity: 0.6)),
            ("100", LifeOrbState(fillLevel: 1.0, rimIntensity: 0.6)),
            ("over", LifeOrbState(fillLevel: 1.12, rimIntensity: 0.6, wobble: 0.5)),
            ("stale", LifeOrbState(fillLevel: 0.6, isStale: true)),
            ("layers", LifeOrbState(fillLevel: 0.64, macroLayers: .init(proteinG: 96, carbsG: 150, fatG: 40))),
        ]
        for direction in LXDirection.allCases {
            for scheme in [ColorScheme.dark, .light] {
                let row = HStack(spacing: 8) {
                    ForEach(states, id: \.0) { name, state in
                        VStack(spacing: 4) {
                            LifeOrb(state: state, size: 120, frozenTime: 1.0)
                            Text(name).lxFont(.caption).foregroundStyle(.lx(.textSecondary))
                        }
                    }
                }
                .padding(16)
                .background(.lx(.background))
                .lxDirection(direction)
                .environment(\.colorScheme, scheme)
                try writePNG(row, scale: 2, to: dir.appendingPathComponent("orb-states-\(direction.rawValue)-\(scheme == .dark ? "dark" : "light").png"))
                let hero = LifeOrb(state: states[7].1, size: 240, frozenTime: 1.0)
                    .padding(16).background(.lx(.background))
                    .lxDirection(direction).environment(\.colorScheme, scheme)
                try writePNG(hero, scale: 2, to: dir.appendingPathComponent("orb-layers-\(direction.rawValue)-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }

    private func writePNG(_ view: some View, scale: CGFloat, to url: URL) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        let cg = try #require(renderer.cgImage, "render failed for \(url.lastPathComponent)")
        #if canImport(AppKit)
        let rep = NSBitmapImageRep(cgImage: cg)
        let data = try #require(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
        #endif
    }
}

/// Feasibility proxy for the Phase 1 spike: CPU time to draw one hero orb frame.
/// The real measurement is on the owner's iPhone (Instruments); this guards
/// against regressions and gives an order of magnitude.
@Suite struct OrbPerformance {
    @Test func heroFrameDrawsWellInsideA120HzBudget() throws {
        let frames = 60
        var times: [Double] = []
        for i in 0..<frames {
            let view = LifeOrb(state: LifeOrbState(fillLevel: 0.64, rimIntensity: 0.6, wobble: 0.4), size: 240, frozenTime: Double(i) / 120)
                .lxDirection(.aurora).environment(\.colorScheme, .dark)
            let r = ImageRenderer(content: view)
            r.scale = 3
            let start = DispatchTime.now().uptimeNanoseconds
            _ = r.cgImage
            times.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1e6)
        }
        times.sort()
        let p50 = times[frames / 2], p95 = times[Int(Double(frames) * 0.95)]
        print("LifeOrb 240pt @3x CPU raster: p50 \(String(format: "%.2f", p50)) ms, p95 \(String(format: "%.2f", p95)) ms")
        // ImageRenderer is a full offscreen CPU rasterisation including setup; on device
        // the Canvas is GPU-composited. 25 ms CPU here is a generous upper bound.
        #expect(p50 < 25)
    }
}

@Suite struct OrbStateTests {
    @Test func zeroBudgetDoesNotProduceNaN() {
        let s = LifeOrbState.budget(eaten: 500, budget: 0, earned: 0)
        #expect(s.clampedFill == 0)
        #expect(LifeOrbState(fillLevel: .nan).clampedFill == 0)
        #expect(LifeOrbState(fillLevel: .infinity).clampedFill == 0)
    }

    @Test func overBudgetClampsAt120Percent() {
        let s = LifeOrbState(fillLevel: 3)
        #expect(s.clampedFill == 1.2)
        #expect(s.isOver)
        #expect(s.liquidHeight <= 1)
    }

    @Test func macroSharesUseCaloriesPerGram() {
        let l = LifeOrbState.MacroLayers(proteinG: 100, carbsG: 100, fatG: 0)
        #expect(l.shares.protein == 0.5)
        #expect(LifeOrbState.MacroLayers(proteinG: 0, carbsG: 0, fatG: 0).shares.fat == 0)
    }
}
