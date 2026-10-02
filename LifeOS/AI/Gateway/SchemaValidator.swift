import Foundation

/// Validates, coerces and decodes raw model output against an `AIOutput` schema
/// (F01 FR5). Its issues list doubles as the feedback for the single repair retry.
///
/// Coercions are deliberately conservative and never invent data:
///  - `"250"` / `"250 kcal"` → `250` for number fields
///  - numbers out of range are clamped
///  - enum strings match case-insensitively
///  - unknown keys are dropped; over-long arrays are truncated
/// Missing required fields, wrong shapes and unknown enum values are failures.
nonisolated enum SchemaValidator {

    nonisolated struct Failure: Error, Sendable, Equatable {
        var issues: [String]
        var raw: String

        /// Text fed back to the model on the repair retry.
        var repairFeedback: String {
            "Your previous reply was invalid:\n" + issues.prefix(8).map { "- \($0)" }.joined(separator: "\n")
                + "\nReturn a corrected JSON object only."
        }
    }

    static func decode<Output: AIOutput>(_ raw: String, as type: Output.Type = Output.self) -> Result<Output, Failure> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let candidate: JSONValue
        if Output.isPlainText {
            guard !trimmed.isEmpty else { return .failure(Failure(issues: ["empty response"], raw: raw)) }
            // A provider may still have answered in JSON; accept either.
            if let parsed = JSONValue.parse(isolateJSONObject(trimmed)), parsed["text"] != nil {
                candidate = parsed
            } else {
                candidate = .object([.init("text", .string(trimmed))])
            }
        } else {
            guard let parsed = JSONValue.parse(isolateJSONObject(trimmed)) else {
                return .failure(Failure(issues: ["response is not valid JSON"], raw: raw))
            }
            candidate = parsed
        }

        var issues: [String] = []
        let coerced = coerce(candidate, to: Output.schema, path: "$", issues: &issues)
        guard issues.isEmpty, let coerced else {
            return .failure(Failure(issues: issues.isEmpty ? ["invalid value at $"] : issues, raw: raw))
        }

        let data = Data(coerced.serialized().utf8)
        let output: Output
        do {
            output = try JSONDecoder().decode(Output.self, from: data)
        } catch {
            return .failure(Failure(issues: ["does not match expected shape: \(describe(error))"], raw: raw))
        }

        let semantic = output.semanticIssues()
        guard semantic.isEmpty else { return .failure(Failure(issues: semantic, raw: raw)) }
        return .success(output)
    }

    // MARK: - Coercion

    private static func coerce(_ value: JSONValue, to schema: AISchema, path: String, issues: inout [String]) -> JSONValue? {
        switch schema {
        case .object(_, _, let properties):
            guard case .object(let members) = value else {
                issues.append("\(path) must be an object")
                return nil
            }
            var out: [JSONValue.Member] = []
            for property in properties {
                let childPath = "\(path).\(property.name)"
                let found = members.first { $0.key == property.name }
                    ?? members.first { $0.key.caseInsensitiveCompare(property.name) == .orderedSame }
                guard let found, found.value != .null else {
                    if !property.isOptional { issues.append("\(childPath) is required") }
                    continue
                }
                if let child = coerce(found.value, to: property.schema, path: childPath, issues: &issues) {
                    out.append(.init(property.name, child))
                }
            }
            return .object(out)

        case .array(let itemSchema, _, let minItems, let maxItems):
            let values: [JSONValue]
            switch value {
            case .array(let array): values = array
            case .object: values = [value]          // a lone item where a list was expected
            default:
                issues.append("\(path) must be an array")
                return nil
            }
            var out: [JSONValue] = []
            for (i, element) in values.enumerated() {
                if let maxItems, out.count >= maxItems { break }
                if let child = coerce(element, to: itemSchema, path: "\(path)[\(i)]", issues: &issues) {
                    out.append(child)
                }
            }
            if let minItems, out.count < minItems {
                issues.append("\(path) needs at least \(minItems) item(s)")
            }
            return .array(out)

        case .string(_, let choices):
            let string: String
            switch value {
            case .string(let s): string = s
            case .number(let n): string = n == n.rounded() ? String(Int64(n)) : String(n)
            case .bool(let b): string = b ? "true" : "false"
            default:
                issues.append("\(path) must be a string")
                return nil
            }
            guard let choices else { return .string(string) }
            if let match = choices.first(where: { $0.caseInsensitiveCompare(string.trimmingCharacters(in: .whitespaces)) == .orderedSame }) {
                return .string(match)
            }
            issues.append("\(path) must be one of \(choices.joined(separator: ", ")) (got \"\(string.prefix(40))\")")
            return nil

        case .number(_, let minimum, let maximum):
            guard var number = numericValue(value) else {
                issues.append("\(path) must be a number")
                return nil
            }
            if let minimum { number = max(minimum, number) }
            if let maximum { number = min(maximum, number) }
            return .number(number)

        case .integer(_, let minimum, let maximum):
            guard let number = numericValue(value) else {
                issues.append("\(path) must be an integer")
                return nil
            }
            var integer = Int(number.rounded())
            if let minimum { integer = max(minimum, integer) }
            if let maximum { integer = min(maximum, integer) }
            return .number(Double(integer))

        case .boolean:
            switch value {
            case .bool: return value
            case .string(let s) where ["true", "yes"].contains(s.lowercased()): return .bool(true)
            case .string(let s) where ["false", "no"].contains(s.lowercased()): return .bool(false)
            case .number(let n): return .bool(n != 0)
            default:
                issues.append("\(path) must be a boolean")
                return nil
            }
        }
    }

    /// Accepts numbers and number-leading strings ("250", "250 kcal", "~1.5").
    /// Ranges like "200-300" resolve to their midpoint.
    static func numericValue(_ value: JSONValue) -> Double? {
        switch value {
        case .number(let n):
            return n.isFinite ? n : nil
        case .string(let s):
            let cleaned = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
            let pattern = #/^[~≈]?\s*(-?\d+(?:\.\d+)?)(?:\s*[-–]\s*(\d+(?:\.\d+)?))?/#
            guard let match = cleaned.firstMatch(of: pattern), let low = Double(match.1) else { return nil }
            if let highText = match.2, let high = Double(highText) { return (low + high) / 2 }
            return low
        default:
            return nil
        }
    }

    // MARK: - Helpers

    /// Pulls the first balanced `{...}` object out of arbitrary model text,
    /// tolerating prose and code fences. String-aware, so braces inside string
    /// values don't end the object early. (Generalised from `GroqMealAnalyzer`.)
    static func isolateJSONObject(_ text: String) -> String {
        var stripped = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if stripped.hasPrefix("```") {
            stripped = stripped
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let start = stripped.firstIndex(of: "{") else { return stripped }

        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < stripped.endIndex {
            let ch = stripped[index]
            if inString {
                if escaped { escaped = false }
                else if ch == "\\" { escaped = true }
                else if ch == "\"" { inString = false }
            } else if ch == "\"" {
                inString = true
            } else if ch == "{" {
                depth += 1
            } else if ch == "}" {
                depth -= 1
                if depth == 0 { return String(stripped[start...index]) }
            }
            index = stripped.index(after: index)
        }
        return String(stripped[start...])
    }

    private static func describe(_ error: Error) -> String {
        guard let decoding = error as? DecodingError else { return "decoding failed" }
        switch decoding {
        case .keyNotFound(let key, _): return "missing \(key.stringValue)"
        case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
            return context.codingPath.map(\.stringValue).joined(separator: ".")
        @unknown default: return "decoding failed"
        }
    }
}
