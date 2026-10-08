import Foundation

/// Food search ranking for the Search sheet. Every word typed must appear; names
/// that start with the query come first, then a word starting with it, then any
/// match. Case and accents are ignored ("creme" finds "Crème brûlée").
nonisolated enum FoodSearch {
    /// Lower is better; nil means no match. An empty query matches everything equally.
    static func score(_ name: String, query: String) -> Int? {
        let q = fold(query)
        guard !q.isEmpty else { return 0 }
        let n = fold(name)
        let words = q.split(separator: " ").map(String.init)
        guard words.allSatisfy({ n.contains($0) }) else { return nil }
        if n.hasPrefix(q) { return 0 }
        let nameWords = n.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if nameWords.contains(where: { $0.hasPrefix(words[0]) }) { return 1 }
        return 2
    }

    /// Indices of `names` that match, best first; ties keep their original order.
    static func rank(_ names: [String], query: String) -> [Int] {
        var scored: [(index: Int, score: Int)] = []
        for (i, name) in names.enumerated() {
            if let s = score(name, query: query) { scored.append((i, s)) }
        }
        scored.sort { a, b in a.score == b.score ? a.index < b.index : a.score < b.score }
        return scored.map { $0.index }
    }

    private static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
    }
}
