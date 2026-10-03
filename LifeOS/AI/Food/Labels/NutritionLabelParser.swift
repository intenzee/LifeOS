import Foundation

/// Nutrition facts read from a packaged-food label (F04 §4.4).
nonisolated struct NutritionFacts: Sendable, Hashable, Codable {
    var productName: String?
    var servingDescription: String?
    var servingGrams: Double?
    var servingsPerPack: Double?
    var perServing: Macros?
    var per100g: Macros?
    /// Which fields were actually read (vs derived) — drives confidence.
    var fieldsRead: Int
    /// 0…1: how complete and internally consistent the label read was.
    var confidence: Double

    var isUsable: Bool { (perServing ?? per100g).map { $0.kcal > 0 } ?? false }

    /// Nutrition for an amount eaten, preferring exact grams when known.
    func macros(servings: Double? = nil, grams: Double? = nil) -> Macros? {
        if let grams, let per100g { return per100g.scaled(grams / 100) }
        if let servings, let perServing { return perServing.scaled(servings) }
        if let servings, let per100g, let servingGrams { return per100g.scaled(servingGrams * servings / 100) }
        return perServing ?? per100g
    }
}

/// Deterministic parser for OCR'd nutrition tables — Indian FSSAI layouts
/// ("per 100 g | per serve (30 g)") and US/EU "Nutrition Facts" panels.
/// No model needed, so label scanning works fully on-device on any iPhone.
nonisolated enum NutritionLabelParser {

    private enum Basis { case per100, serving }
    private enum Nutrient: CaseIterable { case energy, protein, carbs, fat }

    static func parse(lines rawLines: [String]) -> NutritionFacts {
        let lines = rawLines.map(normalise).filter { !$0.isEmpty }

        // 1. Columns: which basis does each number column mean?
        var columns: [Basis] = []
        for line in lines where line.contains("per") || line.contains("100") || line.contains("serv") {
            var found: [(Basis, String.Index)] = []
            if let r = line.range(of: #"(per|/)\s*100\s*(g|gm|ml)"#, options: .regularExpression) { found.append((.per100, r.lowerBound)) }
            if let r = line.range(of: #"per\s*(serve|serving|portion|pack|piece)"#, options: .regularExpression) { found.append((.serving, r.lowerBound)) }
            if !found.isEmpty {
                columns = found.sorted { $0.1 < $1.1 }.map(\.0)
                if columns.count == 2 { break }
            }
        }

        // 2. Serving size.
        var servingGrams: Double?
        var servingDescription: String?
        for line in lines {
            guard line.contains("serv") || line.contains("portion") else { continue }
            let weights = line.matches(of: #/(\d+(?:\.\d+)?)\s*(g|gm|ml)\b/#).compactMap { Double($0.1) }
            if let grams = weights.first(where: { $0 != 100 }) ?? (line.contains("serving size") ? weights.first : nil) {
                servingGrams = grams
                servingDescription = line.replacingOccurrences(of: "serving size", with: "")
                    .trimmingCharacters(in: .whitespaces.union(.punctuationCharacters))
                break
            }
        }
        var servingsPerPack: Double?
        for line in lines where line.contains("servings per") || line.contains("serves per") || line.contains("no. of serv") {
            if let match = line.firstMatch(of: #/(\d+(?:\.\d+)?)/#) { servingsPerPack = Double(match.1) }
        }

        // 3. Nutrient rows.
        var values: [Nutrient: [Double]] = [:]
        for (index, line) in lines.enumerated() {
            guard let nutrient = nutrient(in: line), values[nutrient] == nil else { continue }
            var numbers = numbers(in: line, nutrient: nutrient)
            if numbers.isEmpty, index + 1 < lines.count, self.nutrient(in: lines[index + 1]) == nil {
                numbers = self.numbers(in: lines[index + 1], nutrient: nutrient)   // OCR split the row
            }
            if !numbers.isEmpty { values[nutrient] = numbers }
        }

        // 4. Assign columns.
        let singleBasis: Basis = columns.first ?? (servingGrams != nil && !lines.contains { $0.contains("100") } ? .serving : .per100)
        func macros(for basis: Basis) -> Macros? {
            func pick(_ n: Nutrient) -> Double? {
                guard let list = values[n], !list.isEmpty else { return nil }
                if columns.count == 2, let col = columns.firstIndex(of: basis) {
                    return list.count > col ? list[col] : nil
                }
                return basis == singleBasis ? list.first : nil
            }
            guard let kcal = pick(.energy) else { return nil }
            return Macros(kcal: kcal, protein: pick(.protein) ?? 0, carbs: pick(.carbs) ?? 0, fat: pick(.fat) ?? 0)
        }
        var per100 = macros(for: .per100)
        var perServing = macros(for: .serving)

        // 5. Derive the missing basis when the serving weight is known.
        if let grams = servingGrams, grams > 0 {
            if perServing == nil, let per100 { perServing = per100.scaled(grams / 100) }
            if per100 == nil, let perServing { per100 = perServing.scaled(100 / grams) }
        }

        let read = Nutrient.allCases.filter { values[$0] != nil }.count + (servingGrams == nil ? 0 : 1)
        return NutritionFacts(productName: productName(in: rawLines), servingDescription: servingDescription,
                              servingGrams: servingGrams, servingsPerPack: servingsPerPack, perServing: perServing,
                              per100g: per100, fieldsRead: read,
                              confidence: confidence(read: read, macros: per100 ?? perServing))
    }

    // MARK: - Pieces

    static func normalise(_ line: String) -> String {
        var s = line.lowercased()
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "|", with: " ")
        // Decimal commas ("6,5 g") and common OCR confusions inside numbers.
        s = s.replacing(#/(\d),(\d)/#) { "\($0.1).\($0.2)" }
        s = s.replacing(#/(\d)[o](\d|\b)/#) { "\($0.1)0\($0.2)" }
        return s.split(separator: " ").joined(separator: " ")
    }

    private static func nutrient(in line: String) -> Nutrient? {
        if line.contains("energy") || line.hasPrefix("calories") || line.contains(" calories") || line.contains("kcal") && !line.contains("%") && line.count < 30 {
            if line.contains("from fat") { return nil }
            return .energy
        }
        if line.contains("protein") { return .protein }
        if (line.contains("carbohydrate") || line.contains("carbs")) && !line.contains("sugar") { return .carbs }
        if line.contains("fat") && !line.contains("saturated") && !line.contains("trans") && !line.contains("mono")
            && !line.contains("poly") && !line.contains("from fat") && !line.contains("calories") {
            return .fat
        }
        return nil
    }

    /// Numbers in a nutrient row, skipping % daily values and handling kJ/kcal pairs.
    private static func numbers(in line: String, nutrient: Nutrient) -> [Double] {
        var result: [Double] = []
        let tokens = line.matches(of: #/(\d+(?:\.\d+)?)\s*(kcal|kj|cal|mg|g|%)?/#)
        let hasKJ = line.contains("kj"), hasKcal = line.contains("kcal") || line.contains("calories")
        for match in tokens {
            guard let value = Double(match.1) else { continue }
            let unit = match.2.map(String.init)
            if unit == "%" { continue }
            if nutrient == .energy {
                if unit == "kj" { if !hasKcal { result.append(value / 4.184) }; continue }
                if hasKJ && hasKcal && unit == nil {
                    // "energy 2180 kj 520 kcal" — untagged numbers are ambiguous; keep only tagged kcal.
                    continue
                }
            }
            if unit == "mg" { result.append(value / 1000); continue }
            // "100" in "per 100 g" headers mixed into the row is not a value.
            if line.contains("per 100") && value == 100 { continue }
            result.append(value)
        }
        return result
    }

    private static func productName(in lines: [String]) -> String? {
        lines.first { line in
            let lower = line.lowercased()
            return line.count >= 3 && line.count <= 40 && line.rangeOfCharacter(from: .decimalDigits) == nil
                && !["nutrition", "ingredient", "information", "facts", "per", "serving", "energy", "approx"].contains { lower.contains($0) }
        }
    }

    private static func confidence(read: Int, macros: Macros?) -> Double {
        guard let m = macros, m.kcal > 0 else { return 0.1 }
        var score = 0.4 + Double(min(read, 5)) * 0.1
        let computed = 4 * m.protein + 4 * m.carbs + 9 * m.fat
        if computed > 0 {
            let error = abs(computed - m.kcal) / m.kcal
            score -= error > 0.25 ? 0.3 : 0
        }
        return min(1, max(0.1, score))
    }
}

/// Groups OCR fragments (Vision observations) into reading-order lines.
nonisolated enum OCRLineAssembler {
    nonisolated struct Fragment: Sendable, Hashable {
        var text: String
        /// Normalised, origin bottom-left (Vision convention).
        var minX: Double
        var midY: Double
        var height: Double
    }

    static func lines(from fragments: [Fragment]) -> [String] {
        let sorted = fragments.sorted { $0.midY > $1.midY }
        var rows: [[Fragment]] = []
        for fragment in sorted {
            if let index = rows.lastIndex(where: { row in
                guard let first = row.first else { return false }
                return abs(first.midY - fragment.midY) < max(first.height, fragment.height) * 0.6
            }) {
                rows[index].append(fragment)
            } else {
                rows.append([fragment])
            }
        }
        return rows.map { $0.sorted { $0.minX < $1.minX }.map(\.text).joined(separator: " ") }
    }
}
