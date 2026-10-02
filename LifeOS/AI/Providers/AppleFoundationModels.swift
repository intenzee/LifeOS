import CoreGraphics
import Foundation
import ImageIO
#if canImport(FoundationModels)
import FoundationModels
#endif

/// T1 — Apple's on-device Foundation Model (iOS 26+, Apple Intelligence devices).
/// Image input requires iOS 27.
nonisolated struct AppleOnDeviceProvider: AIProvider {
    let id: ProviderID = .appleOnDevice

    var capabilities: Set<AICapability> {
        var caps: Set<AICapability> = [.text, .streaming, .tools]
        if #available(iOS 27.0, macOS 27.0, *) { caps.insert(.vision) }
        return caps
    }

    func availability(for task: AITask) async -> AIAvailability {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return .unavailable(.osTooOld) }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable(.appleIntelligenceNotEnabled)
        case .unavailable(.modelNotReady):
            return .unavailable(.modelNotReady)
        case .unavailable:
            return .unavailable(.modelNotReady)
        }
        #else
        return .unavailable(.osTooOld)
        #endif
    }

    func generate(_ call: ProviderCall) async throws -> ProviderResponse {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { throw AIError.unavailable(.osTooOld) }
        return try await AppleFMRunner.generate(call, model: .onDevice, label: "apple-on-device")
        #else
        throw AIError.unavailable(.osTooOld)
        #endif
    }

    func stream(_ call: ProviderCall) -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            return AppleFMRunner.stream(call, model: .onDevice)
        }
        #endif
        return AsyncThrowingStream { $0.finish(throwing: AIError.unavailable(.osTooOld)) }
    }

    func prewarm(for task: AITask) async {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, macOS 26.0, *) {
            LanguageModelSession(model: SystemLanguageModel.default).prewarm()
        }
        #endif
    }
}

/// T2 — Apple Private Cloud Compute model (iOS 27+). Free under Apple's terms;
/// treated as inside the privacy boundary. Gated by the `pccEnabled` flag.
nonisolated struct ApplePCCProvider: AIProvider {
    let id: ProviderID = .applePCC
    let capabilities: Set<AICapability> = [.text, .vision, .streaming, .tools, .longContext]

    func availability(for task: AITask) async -> AIAvailability {
        #if canImport(FoundationModels)
        guard #available(iOS 27.0, macOS 27.0, *) else { return .unavailable(.osTooOld) }
        switch PrivateCloudComputeLanguageModel().availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable(.deviceNotEligible)
        case .unavailable:
            return .unavailable(.modelNotReady)
        }
        #else
        return .unavailable(.osTooOld)
        #endif
    }

    func generate(_ call: ProviderCall) async throws -> ProviderResponse {
        #if canImport(FoundationModels)
        guard #available(iOS 27.0, macOS 27.0, *) else { throw AIError.unavailable(.osTooOld) }
        return try await AppleFMRunner.generate(call, model: .privateCloud, label: "apple-pcc")
        #else
        throw AIError.unavailable(.osTooOld)
        #endif
    }

    func stream(_ call: ProviderCall) -> AsyncThrowingStream<String, Error> {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return AppleFMRunner.stream(call, model: .privateCloud)
        }
        #endif
        return AsyncThrowingStream { $0.finish(throwing: AIError.unavailable(.osTooOld)) }
    }
}

#if canImport(FoundationModels)

/// Shared Foundation Models plumbing for T1/T2: session setup, prompt with image
/// attachments, `AISchema` → `GenerationSchema`, and error mapping.
@available(iOS 26.0, macOS 26.0, *)
nonisolated enum AppleFMRunner {

    enum Model {
        case onDevice, privateCloud
        var provider: ProviderID { self == .onDevice ? .appleOnDevice : .applePCC }
    }

    static func makeSession(_ model: Model, instructions: String) throws -> LanguageModelSession {
        switch model {
        case .onDevice:
            return LanguageModelSession(model: SystemLanguageModel.default, instructions: instructions)
        case .privateCloud:
            guard #available(iOS 27.0, macOS 27.0, *) else { throw AIError.unavailable(.osTooOld) }
            return LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: instructions)
        }
    }

    static func generate(_ call: ProviderCall, model: Model, label: String) async throws -> ProviderResponse {
        let session = try makeSession(model, instructions: call.fullInstructions)
        let options = GenerationOptions(temperature: call.generation.temperature,
                                        maximumResponseTokens: call.generation.maxOutputTokens)
        let prompt = try makePrompt(call)
        do {
            if call.outputIsPlainText {
                let response = try await session.respond(to: prompt, options: options)
                return ProviderResponse(raw: response.content, model: label)
            }
            let schema = try generationSchema(for: call.schema)
            let response = try await session.respond(to: prompt, schema: schema, options: options)
            return ProviderResponse(raw: response.content.jsonString, model: label)
        } catch {
            throw map(error, provider: model.provider)
        }
    }

    static func stream(_ call: ProviderCall, model: Model) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = try makeSession(model, instructions: call.fullInstructions)
                    let options = GenerationOptions(temperature: call.generation.temperature,
                                                    maximumResponseTokens: call.generation.maxOutputTokens)
                    let stream = session.streamResponse(to: try makePrompt(call), options: options)
                    for try await snapshot in stream {
                        continuation.yield(snapshot.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: map(error, provider: model.provider))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func makePrompt(_ call: ProviderCall) throws -> Prompt {
        let text = call.fullUserText
        let images = call.input.images
        guard !images.isEmpty else { return Prompt(text) }
        guard #available(iOS 27.0, macOS 27.0, *) else { throw AIError.unsupportedInput }
        let attachments: [Attachment<ImageAttachmentContent>] = try images.map { image in
            guard let cgImage = decodeCGImage(image.data) else { throw AIError.unsupportedInput }
            return Attachment(cgImage).label("meal photo")
        }
        return Prompt {
            text
            attachments
        }
    }

    static func decodeCGImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    // MARK: Schema

    static func generationSchema(for schema: AISchema) throws -> GenerationSchema {
        var names = Set<String>()
        let root = dynamic(schema, path: "Root", names: &names)
        do {
            return try GenerationSchema(root: root, dependencies: [])
        } catch {
            throw AIError.invalidOutput("schema: \(error)")
        }
    }

    /// Nested type names must be unique within a schema, so they are derived
    /// from the property path rather than reused.
    private static func dynamic(_ schema: AISchema, path: String, names: inout Set<String>) -> DynamicGenerationSchema {
        func unique(_ base: String) -> String {
            var name = base
            var n = 2
            while names.contains(name) { name = "\(base)\(n)"; n += 1 }
            names.insert(name)
            return name
        }
        switch schema {
        case .object(let name, let description, let properties):
            let typeName = unique(names.isEmpty ? name : "\(path)_\(name)")
            return DynamicGenerationSchema(
                name: typeName, description: description,
                properties: properties.map { property in
                    DynamicGenerationSchema.Property(
                        name: property.name,
                        description: property.description ?? property.schema.description,
                        schema: dynamic(property.schema, path: "\(typeName)_\(property.name)", names: &names),
                        isOptional: property.isOptional)
                })
        case .array(let items, _, let minItems, let maxItems):
            return DynamicGenerationSchema(arrayOf: dynamic(items, path: path + "_item", names: &names),
                                           minimumElements: minItems, maximumElements: maxItems)
        case .string(_, let choices):
            if let choices, !choices.isEmpty {
                return DynamicGenerationSchema(name: unique(path + "_choice"), anyOf: choices)
            }
            return DynamicGenerationSchema(type: String.self)
        case .number(_, let minimum, let maximum):
            var guides: [GenerationGuide<Double>] = []
            if let minimum, let maximum { guides.append(.range(minimum...maximum)) }
            else if let minimum { guides.append(.minimum(minimum)) }
            else if let maximum { guides.append(.maximum(maximum)) }
            return DynamicGenerationSchema(type: Double.self, guides: guides)
        case .integer(_, let minimum, let maximum):
            var guides: [GenerationGuide<Int>] = []
            if let minimum, let maximum { guides.append(.range(minimum...maximum)) }
            else if let minimum { guides.append(.minimum(minimum)) }
            else if let maximum { guides.append(.maximum(maximum)) }
            return DynamicGenerationSchema(type: Int.self, guides: guides)
        case .boolean:
            return DynamicGenerationSchema(type: Bool.self)
        }
    }

    // MARK: Errors

    static func map(_ error: Error, provider: ProviderID = .appleOnDevice) -> AIError {
        if let error = error as? AIError { return error }
        if error is CancellationError { return .cancelled }
        if #available(iOS 27.0, macOS 27.0, *) {
            if let error = error as? LanguageModelError {
                switch error {
                case .contextSizeExceeded: return .contextOverflow
                case .rateLimited: return .rateLimited(provider)
                case .guardrailViolation: return .guardrail
                case .refusal: return .refusal
                case .unsupportedCapability, .unsupportedTranscriptContent: return .unsupportedInput
                case .unsupportedGenerationGuide: return .invalidOutput("unsupported guide")
                case .unsupportedLanguageOrLocale: return .unsupportedLocale
                case .timeout: return .timeout
                @unknown default: return .server(-1)
                }
            }
            if let error = error as? PrivateCloudComputeLanguageModel.Error {
                switch error {
                case .networkFailure: return .network("pcc")
                case .quotaLimitReached: return .quotaExhausted(.applePCC)
                case .serviceUnavailable: return .server(503)
                @unknown default: return .server(-1)
                }
            }
            if error is SystemLanguageModel.Error { return .unavailable(.modelNotReady) }
        }
        if let error = error as? LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: return .contextOverflow
            case .assetsUnavailable: return .unavailable(.modelNotReady)
            case .guardrailViolation: return .guardrail
            case .unsupportedGuide: return .invalidOutput("unsupported guide")
            case .unsupportedLanguageOrLocale: return .unsupportedLocale
            case .decodingFailure: return .invalidOutput("decoding failure")
            case .rateLimited: return .rateLimited(provider)
            case .concurrentRequests: return .server(429)
            case .refusal: return .refusal
            @unknown default: return .server(-1)
            }
        }
        // Unclassified framework errors (e.g. ModelManagerError when the app lacks
        // an entitlement) are treated as recoverable so the chain moves on.
        return .server(-1)
    }
}

#endif
