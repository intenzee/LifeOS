import Foundation
import SwiftUI
import Testing
@testable import LifeOSDesign
#if canImport(AppKit)
import AppKit
#endif

/// Component snapshot tests (Phase 2 §7: light, dark, accessibility XXL).
///
/// No third-party dependency: each gallery section is rendered with
/// `ImageRenderer` and compared to a reference PNG under `__Snapshots__/`
/// with a small per-pixel tolerance (anti-aliasing differs slightly between
/// macOS versions). Record or refresh references with:
///
///     LX_RECORD=1 swift test --filter ComponentSnapshots
@Suite struct ComponentSnapshots {
    enum Variant: String, CaseIterable, Sendable {
        case light, dark, xxl
        var scheme: ColorScheme { self == .dark ? .dark : .light }
        var typeSize: DynamicTypeSize { self == .xxl ? .accessibility3 : .large }
    }

    nonisolated static let cases: [(LXGallerySection, Variant)] =
        LXGallerySection.allCases.flatMap { s in Variant.allCases.map { (s, $0) } }

    nonisolated static var recording: Bool { ProcessInfo.processInfo.environment["LX_RECORD"] == "1" }

    static let snapshotDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("__Snapshots__")

    @Test(arguments: cases)
    func section(_ section: LXGallerySection, _ variant: Variant) throws {
        let view = section.content
            .padding(LX.Space.screenMargin)
            .frame(width: 393)
            .fixedSize(horizontal: false, vertical: true)
            .background(LXColor(role: .background))
            .lxDirection(.obsidian) // the recommended direction; update after gate D1
            .environment(\.colorScheme, variant.scheme)
            .environment(\.dynamicTypeSize, variant.typeSize)
            .environment(\.lxSnapshotMode, true)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let url = Self.snapshotDir.appendingPathComponent("\(section.rawValue)-\(variant.rawValue).png")

        if Self.recording || !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: Self.snapshotDir, withIntermediateDirectories: true)
            try png(image).write(to: url)
            if !Self.recording { Issue.record("Recorded new reference \(url.lastPathComponent); re-run to compare.") }
            return
        }
        let reference = try #require(NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(image.width == reference.width && image.height == reference.height,
                "\(url.lastPathComponent): size \(image.width)×\(image.height) vs reference \(reference.width)×\(reference.height)")
        guard image.width == reference.width, image.height == reference.height else { return }
        let diff = try differingPixelFraction(image, reference)
        #expect(diff < 0.005, "\(url.lastPathComponent): \(String(format: "%.2f", diff * 100))% pixels differ")
    }

    @Test(arguments: LXGallerySection.allCases)
    func xxlTextNeverClipsHorizontally(_ section: LXGallerySection) throws {
        // At accessibility sizes the layout may grow taller but must not exceed the screen width.
        let view = section.content.padding(LX.Space.screenMargin).frame(width: 393).fixedSize(horizontal: false, vertical: true)
            .lxDirection(.obsidian).environment(\.dynamicTypeSize, .accessibility3)
        let renderer = ImageRenderer(content: view)
        let image = try #require(renderer.cgImage)
        #expect(image.width <= 393 * Int(renderer.scale))
    }

    private func png(_ image: CGImage) throws -> Data {
        let rep = NSBitmapImageRep(cgImage: image)
        return try #require(rep.representation(using: .png, properties: [:]))
    }

    private func rgba(_ image: CGImage) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let ctx = try #require(CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                                         bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return data
    }

    private func differingPixelFraction(_ a: CGImage, _ b: CGImage) throws -> Double {
        let pa = try rgba(a), pb = try rgba(b)
        var differing = 0
        for i in stride(from: 0, to: pa.count, by: 4) {
            let d = max(abs(Int(pa[i]) - Int(pb[i])), abs(Int(pa[i + 1]) - Int(pb[i + 1])), abs(Int(pa[i + 2]) - Int(pb[i + 2])))
            if d > 24 { differing += 1 }
        }
        return Double(differing) / Double(pa.count / 4)
    }
}
