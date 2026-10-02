import UIKit

/// Prepares a user's meal photo for analysis.
///
/// Two production problems this solves that the old scanner ignored:
///  1. **Upload size.** A modern iPhone photo is 3–6 MB. Groq rejects base64
///     images over ~4 MB, and even under that the upload is slow and burns
///     free-tier tokens (each image is billed as a fixed block regardless of
///     resolution). We downscale to a sane dimension and compress adaptively so
///     the encoded payload stays comfortably small and fast.
///  2. **Orientation.** Camera images carry an EXIF orientation that vision
///     models often ignore, silently analysing a sideways plate. We bake the
///     orientation into the pixels by redrawing upright.
enum MealImageProcessor {

    /// Longest edge, in pixels, of the image we send. 1024 keeps plenty of food
    /// detail for recognition while shrinking a 12 MP shot ~20×.
    static let maxDimension: CGFloat = 1024

    /// Hard ceiling for the JPEG we'll base64-encode, well under Groq's limit so
    /// the data URL (base64 adds ~33%) stays safe: ~1.6 MB JPEG → ~2.2 MB base64.
    static let maxJPEGBytes = 1_600_000

    struct Prepared {
        let jpegData: Data
        /// Ready-to-embed data URL: `data:image/jpeg;base64,...`
        let dataURL: String
        /// The upright, downscaled bitmap — reused for on-device fingerprinting
        /// so we don't redraw the photo a second time.
        let cgImage: CGImage?
    }

    /// Returns an upright, downscaled, size-bounded JPEG plus its data URL and
    /// the reusable downscaled bitmap. `nil` only if the image has no drawable
    /// representation at all.
    static func prepare(_ image: UIImage) -> Prepared? {
        let upright = redrawUpright(image)
        let scaled = downscale(upright, maxDimension: maxDimension)

        guard let data = compress(scaled, underBytes: maxJPEGBytes) else { return nil }
        let dataURL = "data:image/jpeg;base64," + data.base64EncodedString()
        return Prepared(jpegData: data, dataURL: dataURL, cgImage: scaled.cgImage)
    }

    /// An upright `CGImage` for on-device Vision requests (no compression needed).
    static func uprightCGImage(_ image: UIImage) -> CGImage? {
        redrawUpright(image).cgImage
    }

    // MARK: - Steps

    /// Redraws the image with orientation applied so `.up` is the true pixel layout.
    private static func redrawUpright(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }

    /// Scales the image down so its longest edge is `maxDimension`. Never upscales.
    private static func downscale(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let w = image.size.width
        let h = image.size.height
        let longest = max(w, h)
        guard longest > maxDimension, longest > 0 else { return image }

        let ratio = maxDimension / longest
        let target = CGSize(width: floor(w * ratio), height: floor(h * ratio))

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// JPEG-encodes, stepping quality down until the payload fits `underBytes`.
    /// Falls back to the smallest attempt if even low quality is too large.
    private static func compress(_ image: UIImage, underBytes limit: Int) -> Data? {
        let qualities: [CGFloat] = [0.7, 0.55, 0.4, 0.3, 0.2]
        var last: Data?
        for q in qualities {
            guard let data = image.jpegData(compressionQuality: q) else { continue }
            last = data
            if data.count <= limit { return data }
        }
        return last
    }
}
