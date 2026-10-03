import UIKit
import Vision

// A compact, comparable fingerprint of a meal photo used by the learning
// system to recognise "I've seen a dish like this before."
//
// Two complementary signals, as an ML engineer would layer them:
//  • **Perceptual hash (aHash)** — a 64-bit average hash. Cheap, and its
//    Hamming distance is a robust detector of *near-identical* images (the same
//    plate, same shot). We use it for the high-confidence "instant override".
//  • **Vision feature print** — Apple's on-device image embedding
//    (`VNFeaturePrintObservation`). Its distance captures *semantic* similarity
//    (two different photos of egg fried rice look close), which is what powers
//    retrieval of relevant past corrections for in-context learning.
//
// The `ImageSignature` value type itself lives in LifeOSCore (FOOD-14), with
// the stored corrections; this file builds and compares signatures.

enum ImageSignatureBuilder {

    /// Builds a signature from an already-upright, downscaled CGImage. Runs the
    /// Vision request off the caller's actor. Never throws — a failed embedding
    /// simply yields a pHash-only signature.
    static func make(from cgImage: CGImage) async -> ImageSignature {
        let hash = averageHash(cgImage)
        let featureData = await featurePrint(cgImage)
        return ImageSignature(pHash: hash, featurePrintData: featureData)
    }

    // MARK: - Perceptual (average) hash

    /// Reduces the image to 8×8 grayscale and sets each bit where the pixel is
    /// at or above the mean luminance. Orientation/scale invariant enough for
    /// "same photo" detection.
    static func averageHash(_ cgImage: CGImage) -> UInt64 {
        let side = 8
        let count = side * side
        var pixels = [UInt8](repeating: 0, count: count)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return 0 }

        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let total = pixels.reduce(0) { $0 + Int($1) }
        let mean = UInt8(total / count)

        var hash: UInt64 = 0
        for (i, value) in pixels.enumerated() where value >= mean {
            hash |= (UInt64(1) << UInt64(i))
        }
        return hash
    }

    /// Number of differing bits between two average hashes (0…64). Lower = more
    /// similar; ≤ 8 reliably means "essentially the same photo".
    static func hammingDistance(_ a: UInt64, _ b: UInt64) -> Int {
        (a ^ b).nonzeroBitCount
    }

    // MARK: - Vision feature print (semantic embedding)

    static func featurePrint(_ cgImage: CGImage) async -> Data? {
        await withCheckedContinuation { continuation in
            let request = VNGenerateImageFeaturePrintRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first as? VNFeaturePrintObservation else {
                    continuation.resume(returning: nil)
                    return
                }
                let data = try? NSKeyedArchiver.archivedData(withRootObject: observation,
                                                             requiringSecureCoding: true)
                continuation.resume(returning: data)
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    /// Semantic distance between two archived feature prints. `nil` when either
    /// can't be decoded. Smaller = more similar; the scale is model-defined
    /// (typically ~0 for identical, growing with dissimilarity).
    static func featureDistance(_ lhs: Data?, _ rhs: Data?) -> Float? {
        guard let queryObservation = Self.observation(from: lhs) else { return nil }
        return distance(from: queryObservation, to: rhs)
    }

    /// Decodes an archived feature print. Do this once for the query image, then
    /// reuse the observation across many candidates via `distance(from:to:)`
    /// instead of re-decoding it in a loop.
    static func observation(from data: Data?) -> VNFeaturePrintObservation? {
        guard let data else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: VNFeaturePrintObservation.self, from: data)
    }

    /// Distance from an already-decoded observation to another archived print.
    static func distance(from observation: VNFeaturePrintObservation, to data: Data?) -> Float? {
        guard let other = Self.observation(from: data) else { return nil }
        var distance: Float = 0
        do {
            try observation.computeDistance(&distance, to: other)
            return distance
        } catch {
            return nil
        }
    }
}
