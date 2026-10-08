import CoreGraphics
import SwiftUI
import Testing
@testable import LifeOSDesign

/// A scaled-to-fill photo must not size `LXPhotoCard`: a tall photo in a short
/// frame used to overflow it and cover the content below (found on device in the
/// 3.5 meal result).
@MainActor
struct PhotoCardLayoutTests {
    @Test func tallPhotoStaysInsideItsFrame() throws {
        let photo = try #require(Self.solidImage(width: 300, height: 900))
        let canvas = ZStack {
            Color(red: 0, green: 0, blue: 1)
            LXPhotoCard(image: Image(decorative: photo, scale: 1), lifted: false)
                .frame(width: 300, height: 150)
        }
        .frame(width: 400, height: 400)
        let renderer = ImageRenderer(content: canvas)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        // Inside the card: the photo (red). Above and below it: still the canvas (blue).
        #expect(try Self.pixel(image, x: 200, y: 200).red > 200)
        #expect(try Self.pixel(image, x: 200, y: 100).blue > 200)
        #expect(try Self.pixel(image, x: 200, y: 300).blue > 200)
    }

    private static func solidImage(width: Int, height: Int) -> CGImage? {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        ctx?.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx?.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return ctx?.makeImage()
    }

    private static func pixel(_ image: CGImage, x: Int, y: Int) throws -> (red: Int, blue: Int) {
        let ctx = try #require(CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                         space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        // Draw so that (x, y) from the top-left lands on the single pixel.
        ctx.draw(image, in: CGRect(x: -x, y: y - image.height + 1, width: image.width, height: image.height))
        let data = try #require(ctx.data).assumingMemoryBound(to: UInt8.self)
        return (Int(data[0]), Int(data[2]))
    }
}
