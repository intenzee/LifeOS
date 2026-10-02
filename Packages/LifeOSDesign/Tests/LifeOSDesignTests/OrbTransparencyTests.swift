import SwiftUI
import Testing
@testable import LifeOSDesign

/// The orb must not paint anything outside its glow: corners of its frame stay
/// fully transparent so it sits on any background (device showed a dark square).
@Suite struct OrbTransparency {
    /// Draws the renderer into its full canvas and checks the canvas edges, where
    /// a clipped glow halo would show as a hard square on device.
    @Test(arguments: LXDirection.allCases)
    func glowFadesOutBeforeCanvasEdge(_ direction: LXDirection) throws {
        let theme = LXTheme(direction: direction, colorScheme: .dark)
        let side = 240 * LifeOrbRenderer.canvasScale
        let view = Canvas { ctx, size in
            LifeOrbRenderer(state: LifeOrbState(fillLevel: 0.64, rimIntensity: 1), theme: theme, time: 1).draw(in: &ctx, size: size)
        }
        .frame(width: side, height: side)
        let r = ImageRenderer(content: view)
        r.scale = 1
        r.isOpaque = false
        let image = try #require(r.cgImage)
        var px = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = try #require(CGContext(data: &px, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        func alpha(_ x: Int, _ y: Int) -> UInt8 { px[(y * image.width + x) * 4 + 3] }
        let w = image.width, h = image.height
        let probes = [(2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3),        // corners
                      (2, h / 2), (w - 3, h / 2), (w / 2, 2), (w / 2, h - 3)] // edge midpoints: nearest the glow
        for (x, y) in probes {
            #expect(alpha(x, y) < 8, "\(direction) corner (\(x),\(y)) alpha \(alpha(x, y))")
        }
    }
}
