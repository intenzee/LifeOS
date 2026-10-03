import Foundation

/// "Never invent numbers" (F07 §5, doc 05 §5 numbers rule, AI-308 grounding).
///
/// Every number in a model's reply must appear in the data the model was given
/// (context packet, tool results, the user's own question), allowing for
/// rounding and formatting ("1,240" = 1240.4; "1.2k" = 1,200; "6.4h").
/// Small counting words ("3 options", "2 rotis") are allowed.
nonisolated enum GroundingValidator {
    nonisolated struct Result: Sendable, Equatable {
        var isGrounded: Bool
        var ungrounded: [Double]
    }

    /// Integers up to this are list counts, not data claims.
    static let freeIntegerLimit = 10.0

    static func validate(_ reply: String, allowed: [Double], sourceTexts: [String] = []) -> Result {
        let pool = allowed + sourceTexts.flatMap(numbers)
        let ungrounded = numbers(in: reply).filter { value in
            if value.rounded() == value, abs(value) <= freeIntegerLimit { return false }
            return !pool.contains { matches(value, $0) }
        }
        return Result(isGrounded: ungrounded.isEmpty, ungrounded: ungrounded)
    }

    /// Equal after the rounding a person would do when speaking about it.
    static func matches(_ said: Double, _ source: Double) -> Bool {
        if abs(said - source) < 0.051 { return true }
        if said.rounded() == source.rounded() { return true }
        let magnitude = abs(source)
        if magnitude >= 100, abs(said - (source / 10).rounded() * 10) < 0.5 { return true }       // 1,236 → 1,240
        if magnitude >= 1_000, abs(said - (source / 50).rounded() * 50) < 0.5 { return true }     // 2,180 → 2,200 (not 2,150)
        if magnitude >= 1_000, abs(said - (source / 100).rounded() * 100) < 0.5 { return true }
        if abs(said - (source * 10).rounded() / 10) < 0.051 { return true }                     // 6.43 → 6.4
        // Percentages written as fractions in the data (0.5 → 50%).
        if source > 0, source <= 1, abs(said - source * 100) < 0.51 { return true }
        return false
    }

    static func numbers(in text: String) -> [Double] {
        Rx.allGroups(#"(?<![A-Za-z])(\d{1,3}(?:,\d{2,3})+|\d+(?:\.\d+)?)\s*(k\b)?"#, text).compactMap { groups in
            guard groups.count >= 2, var v = Double(groups[1].replacingOccurrences(of: ",", with: "")) else { return nil }
            if groups.count > 2, groups[2].lowercased() == "k" { v *= 1_000 }
            return v
        }
    }
}
