import Foundation

/// Provider-neutral description of a structured output (F01 FR5).
///
/// One schema drives every engine: it becomes a `DynamicGenerationSchema` for
/// Apple's guided generation, a JSON Schema for REST providers, and the contract
/// `SchemaValidator` checks every raw answer against before decoding.
nonisolated indirect enum AISchema: Sendable, Hashable {
    case object(name: String, description: String? = nil, properties: [AISchemaProperty])
    case array(of: AISchema, description: String? = nil, minItems: Int? = nil, maxItems: Int? = nil)
    case string(description: String? = nil, choices: [String]? = nil)
    case number(description: String? = nil, minimum: Double? = nil, maximum: Double? = nil)
    case integer(description: String? = nil, minimum: Int? = nil, maximum: Int? = nil)
    case boolean(description: String? = nil)

    var description: String? {
        switch self {
        case .object(_, let d, _), .array(_, let d, _, _), .string(let d, _),
             .number(let d, _, _), .integer(let d, _, _), .boolean(let d):
            return d
        }
    }

    var typeName: String {
        switch self {
        case .object: "object"
        case .array: "array"
        case .string: "string"
        case .number: "number"
        case .integer: "integer"
        case .boolean: "boolean"
        }
    }
}

nonisolated struct AISchemaProperty: Sendable, Hashable {
    var name: String
    var description: String?
    var schema: AISchema
    var isOptional: Bool

    init(_ name: String, _ schema: AISchema, description: String? = nil, optional: Bool = false) {
        self.name = name
        self.schema = schema
        self.description = description
        self.isOptional = optional
    }
}

/// A structured output the gateway can produce. The root schema must be an object
/// (Apple guided generation and JSON mode both require it).
nonisolated protocol AIOutput: Codable, Sendable {
    static var schema: AISchema { get }
    /// Plain-text outputs (chat, briefings) skip JSON entirely; providers return
    /// prose and the gateway wraps it as `{"text": …}`.
    static var isPlainText: Bool { get }
    /// Domain checks beyond the schema (e.g. "a meal with zero everything is not
    /// an answer"). Non-empty → treated as invalid output and repaired/rerouted.
    func semanticIssues() -> [String]
}

nonisolated extension AIOutput {
    static var isPlainText: Bool { false }
    func semanticIssues() -> [String] { [] }
}

/// Free-form text output for chat-like tasks.
nonisolated struct AIText: AIOutput, Hashable {
    var text: String

    static let schema: AISchema = .object(name: "Text", properties: [AISchemaProperty("text", .string())])
    static var isPlainText: Bool { true }

    func semanticIssues() -> [String] {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ["empty text"] : []
    }
}

// MARK: - JSON Schema rendering (REST providers)

nonisolated extension AISchema {
    /// Standard JSON Schema (draft 2020-12 subset) as an ordered JSON value.
    func jsonSchema() -> JSONValue {
        var members: [JSONValue.Member] = []
        switch self {
        case .object(_, let description, let properties):
            members.append(.init("type", .string("object")))
            if let description { members.append(.init("description", .string(description))) }
            members.append(.init("properties", .object(properties.map { property in
                var schema = property.schema.jsonSchema()
                if let d = property.description, case .object(var m) = schema {
                    m.removeAll { $0.key == "description" }
                    m.insert(.init("description", .string(d)), at: min(1, m.count))
                    schema = .object(m)
                }
                return .init(property.name, schema)
            })))
            members.append(.init("required", .array(properties.filter { !$0.isOptional }.map { .string($0.name) })))
            members.append(.init("additionalProperties", .bool(false)))
        case .array(let items, let description, let minItems, let maxItems):
            members.append(.init("type", .string("array")))
            if let description { members.append(.init("description", .string(description))) }
            members.append(.init("items", items.jsonSchema()))
            if let minItems { members.append(.init("minItems", .number(Double(minItems)))) }
            if let maxItems { members.append(.init("maxItems", .number(Double(maxItems)))) }
        case .string(let description, let choices):
            members.append(.init("type", .string("string")))
            if let description { members.append(.init("description", .string(description))) }
            if let choices { members.append(.init("enum", .array(choices.map { .string($0) }))) }
        case .number(let description, let minimum, let maximum):
            members.append(.init("type", .string("number")))
            if let description { members.append(.init("description", .string(description))) }
            if let minimum { members.append(.init("minimum", .number(minimum))) }
            if let maximum { members.append(.init("maximum", .number(maximum))) }
        case .integer(let description, let minimum, let maximum):
            members.append(.init("type", .string("integer")))
            if let description { members.append(.init("description", .string(description))) }
            if let minimum { members.append(.init("minimum", .number(Double(minimum)))) }
            if let maximum { members.append(.init("maximum", .number(Double(maximum)))) }
        case .boolean(let description):
            members.append(.init("type", .string("boolean")))
            if let description { members.append(.init("description", .string(description))) }
        }
        return .object(members)
    }

    /// Gemini `responseSchema` (OpenAPI 3.0 subset: upper-case types,
    /// `propertyOrdering`, no `additionalProperties`).
    func geminiSchema() -> JSONValue {
        var members: [JSONValue.Member] = []
        func describe(_ d: String?) { if let d { members.append(.init("description", .string(d))) } }
        switch self {
        case .object(_, let description, let properties):
            members.append(.init("type", .string("OBJECT")))
            describe(description)
            members.append(.init("properties", .object(properties.map { property in
                var schema = property.schema.geminiSchema()
                if let d = property.description, case .object(var m) = schema {
                    m.removeAll { $0.key == "description" }
                    m.append(.init("description", .string(d)))
                    schema = .object(m)
                }
                return .init(property.name, schema)
            })))
            members.append(.init("required", .array(properties.filter { !$0.isOptional }.map { .string($0.name) })))
            members.append(.init("propertyOrdering", .array(properties.map { .string($0.name) })))
        case .array(let items, let description, let minItems, let maxItems):
            members.append(.init("type", .string("ARRAY")))
            describe(description)
            members.append(.init("items", items.geminiSchema()))
            if let minItems { members.append(.init("minItems", .string(String(minItems)))) }
            if let maxItems { members.append(.init("maxItems", .string(String(maxItems)))) }
        case .string(let description, let choices):
            members.append(.init("type", .string("STRING")))
            describe(description)
            if let choices {
                members.append(.init("format", .string("enum")))
                members.append(.init("enum", .array(choices.map { .string($0) })))
            }
        case .number(let description, let minimum, let maximum):
            members.append(.init("type", .string("NUMBER")))
            describe(description)
            if let minimum { members.append(.init("minimum", .number(minimum))) }
            if let maximum { members.append(.init("maximum", .number(maximum))) }
        case .integer(let description, let minimum, let maximum):
            members.append(.init("type", .string("INTEGER")))
            describe(description)
            if let minimum { members.append(.init("minimum", .number(Double(minimum)))) }
            if let maximum { members.append(.init("maximum", .number(Double(maximum)))) }
        case .boolean(let description):
            members.append(.init("type", .string("BOOLEAN")))
            describe(description)
        }
        return .object(members)
    }

    /// Instruction block appended to REST prompts that don't already embed a contract.
    func promptInstruction() -> String {
        """
        Respond with ONLY a single JSON object (no prose, no markdown fences) that \
        conforms to this JSON Schema:
        \(jsonSchema().serialized(pretty: true))
        """
    }
}

// MARK: - Ordered JSON value

/// Minimal JSON value with *ordered* object members, so schemas render in a
/// stable, model-friendly order and the validator can coerce before decoding.
nonisolated enum JSONValue: Sendable, Equatable {
    nonisolated struct Member: Sendable, Equatable {
        var key: String
        var value: JSONValue
        init(_ key: String, _ value: JSONValue) {
            self.key = key
            self.value = value
        }
    }

    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([Member])

    subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first { $0.key == key }?.value
    }

    // MARK: Parsing

    static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else {
            return nil
        }
        return JSONValue(foundation: object)
    }

    init?(foundation object: Any) {
        switch object {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            var values: [JSONValue] = []
            for element in array {
                guard let value = JSONValue(foundation: element) else { return nil }
                values.append(value)
            }
            self = .array(values)
        case let dictionary as [String: Any]:
            var members: [Member] = []
            for key in dictionary.keys.sorted() {
                guard let value = JSONValue(foundation: dictionary[key]!) else { return nil }
                members.append(Member(key, value))
            }
            self = .object(members)
        default:
            return nil
        }
    }

    // MARK: Serialisation

    func serialized(pretty: Bool = false) -> String {
        var out = ""
        write(into: &out, pretty: pretty, indent: 0)
        return out
    }

    private func write(into out: inout String, pretty: Bool, indent: Int) {
        let pad = pretty ? String(repeating: "  ", count: indent + 1) : ""
        let closePad = pretty ? String(repeating: "  ", count: indent) : ""
        let newline = pretty ? "\n" : ""
        switch self {
        case .null:
            out += "null"
        case .bool(let b):
            out += b ? "true" : "false"
        case .number(let n):
            out += Self.format(n)
        case .string(let s):
            out += Self.quote(s)
        case .array(let values):
            if values.isEmpty { out += "[]"; return }
            out += "[" + newline
            for (i, v) in values.enumerated() {
                out += pad
                v.write(into: &out, pretty: pretty, indent: indent + 1)
                if i < values.count - 1 { out += "," }
                out += newline
            }
            out += closePad + "]"
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            out += "{" + newline
            for (i, m) in members.enumerated() {
                out += pad + Self.quote(m.key) + (pretty ? ": " : ":")
                m.value.write(into: &out, pretty: pretty, indent: indent + 1)
                if i < members.count - 1 { out += "," }
                out += newline
            }
            out += closePad + "}"
        }
    }

    private static func format(_ n: Double) -> String {
        guard n.isFinite else { return "0" }
        if n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
        return String(n)
    }

    private static func quote(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }
}
