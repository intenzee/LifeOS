import Foundation
#if canImport(Accelerate)
import Accelerate
#endif
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif

/// On-device sentence embeddings for memory dedupe and retrieval (F06 AI-221).
///
/// Vectors from different embedders are not comparable, so every stored vector
/// carries `version`; a version change re-embeds (F06 §7 step 4).
nonisolated protocol TextEmbedding: Sendable {
    var version: String { get }
    func vector(for text: String) -> [Float]?
}

nonisolated enum VectorMath {
    /// vDSP: the plain loop cost ~40 ms per 300-memory retrieval in Debug builds.
    static func cosine(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        #if canImport(Accelerate)
        let n = vDSP_Length(a.count)
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, n)
        vDSP_svesq(a, 1, &na, n)
        vDSP_svesq(b, 1, &nb, n)
        #else
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        #endif
        guard na > 0, nb > 0 else { return 0 }
        return Double(dot / (na.squareRoot() * nb.squareRoot()))
    }
}

/// Apple's NaturalLanguage sentence embedding — on every iPhone, no Apple
/// Intelligence needed. nil vectors when the asset isn't on the device.
nonisolated struct NLSentenceEmbedder: TextEmbedding {
    let version = "nl-sentence-en-1"

    func vector(for text: String) -> [Float]? {
        #if canImport(NaturalLanguage)
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let vector = embedding.vector(for: text.lowercased()) else { return nil }
        return vector.map(Float.init)
        #else
        return nil
        #endif
    }
}

/// Deterministic fallback: hashed word + character-trigram features with light
/// stemming. Not semantic, but stable everywhere (CI, devices without the NL
/// asset) and good at near-duplicate wording ("I hate oats" / "I really hate oats").
nonisolated struct HashingEmbedder: TextEmbedding {
    let version = "hash-trigram-256-1"
    let dimensions = 256

    func vector(for text: String) -> [Float]? {
        let words = Self.words(text)
        guard !words.isEmpty else { return nil }
        var v = [Float](repeating: 0, count: dimensions)
        for word in words {
            v[Self.bucket("w:" + word, dimensions)] += 2
            let padded = Array("^" + word + "$")
            if padded.count >= 3 {
                for i in 0...(padded.count - 3) {
                    v[Self.bucket(String(padded[i..<i + 3]), dimensions)] += 1
                }
            }
        }
        return v
    }

    static let stopWords: Set<String> = ["i", "me", "my", "you", "your", "the", "a", "an", "is", "am", "are", "to",
                                         "and", "of", "it", "that", "really", "very", "do", "on", "in", "at", "for", "with"]

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "n't", with: " not")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && !stopWords.contains($0) }
            .map { $0.count > 4 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 }
    }

    /// FNV-1a — stable across launches (Swift's `hashValue` is seeded per process).
    static func bucket(_ s: String, _ n: Int) -> Int {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return Int(hash % UInt64(n))
    }
}

/// NL embeddings when available, hashing otherwise. The version reflects which
/// one actually answered, so mixed stores re-embed cleanly.
nonisolated struct DefaultEmbedder: TextEmbedding {
    private let primary: NLSentenceEmbedder?
    private let fallback = HashingEmbedder()

    init(preferSemantic: Bool = true) {
        primary = preferSemantic && NLSentenceEmbedder().vector(for: "test") != nil ? NLSentenceEmbedder() : nil
    }

    var version: String { primary?.version ?? fallback.version }

    func vector(for text: String) -> [Float]? {
        // Never mix: a text the NL model can't embed gets no vector rather than a
        // hashing vector that would be compared against NL ones.
        if let primary { return primary.vector(for: text) }
        return fallback.vector(for: text)
    }
}
