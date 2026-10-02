import Foundation
import OSLog

/// The public AI API every team codes against (contract C7).
nonisolated protocol AIGatewaying: Sendable {
    func run<Output: AIOutput>(_ request: AIRequest<Output>) async throws -> AIResult<Output>
    func stream(_ request: AIRequest<AIText>) -> AsyncThrowingStream<AIStreamEvent, Error>
    func availability(for task: AITask) async -> AITaskAvailability
    func prewarm(for task: AITask) async
}

nonisolated enum AIStreamEvent: Sendable {
    /// Cumulative text so far.
    case partial(String)
    case completed(AIResult<AIText>)
}

/// Debug/diagnostics controls (F01 FR14, Phase 0 demo). Never set in release flows.
nonisolated struct AIDebugOverrides: Sendable, Equatable {
    /// Providers treated as unavailable ("force T1 off").
    var forcedUnavailable: Set<ProviderID> = []
    /// Replace a task's chain entirely (e.g. pin to one provider to compare tiers).
    var forcedChains: [AITask: [ProviderID]] = [:]
}

nonisolated extension AITask {
    /// Guardrail false positives on food are common ("shot of whiskey", "killer
    /// burger"), so benign tasks may retry elsewhere. Safety-relevant tasks never do.
    nonisolated var allowsGuardrailFallback: Bool {
        switch self {
        case .foodTextParse, .mealPhotoAnalyze, .mealPhotoRefine, .nutritionLabelRead, .presetSuggestName:
            true
        default:
            false
        }
    }

    nonisolated var requiredCapabilities: Set<AICapability> {
        switch self {
        case .mealPhotoAnalyze, .mealPhotoRefine: [.text, .vision]
        default: [.text]
        }
    }

    /// Typical sensitivity, used for availability reporting before a real request exists.
    nonisolated var defaultPrivacy: PrivacyClass {
        switch self {
        case .presetSuggestName, .nutritionLabelRead: .public
        case .foodTextParse, .mealPhotoAnalyze, .mealPhotoRefine: .personal
        case .memoryExtract, .memoryConsolidate, .assistantChat, .briefingCompose,
             .weeklyReview, .budgetExplain, .nudgeCompose: .health
        }
    }
}

/// Routes typed AI requests across tiers with privacy, quota, cache, validation,
/// fallback and telemetry (F01 §5). Product code never talks to a model directly.
actor AIGateway: AIGatewaying {

    private var providers: [ProviderID: any AIProvider]
    private let routing: RoutingTable
    private let configStore: AIRemoteConfigStore
    private let quota: QuotaManager
    private let cache: AIResponseCache
    private let privacyGate: PrivacyGate
    nonisolated let events: AIEventLog
    private var debug = AIDebugOverrides()
    private var appliedQuotaConfig: [String: QuotaManager.Limits]?
    private let clock = ContinuousClock()

    private nonisolated enum CancelReason: Sendable { case timeout, consentRevoked }
    private struct InFlight {
        var provider: ProviderID
        var task: AITask
        var privacy: PrivacyClass
        var cancel: @Sendable () -> Void
        var reason: CancelReason?
    }
    private var inFlight: [UUID: InFlight] = [:]

    init(providers: [any AIProvider],
         routing: RoutingTable = .v1,
         configStore: AIRemoteConfigStore = AIRemoteConfigStore(remoteURL: nil, cacheURL: nil),
         quota: QuotaManager = QuotaManager(),
         cache: AIResponseCache = AIResponseCache(),
         consents: any ConsentStoring = InMemoryConsentStore(),
         events: AIEventLog = AIEventLog()) {
        self.providers = Dictionary(providers.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        self.routing = routing
        self.configStore = configStore
        self.quota = quota
        self.cache = cache
        self.privacyGate = PrivacyGate(consents: consents)
        self.events = events
    }

    // MARK: - Configuration

    func register(_ provider: any AIProvider) {
        providers[provider.id] = provider
    }

    func setDebugOverrides(_ overrides: AIDebugOverrides) {
        debug = overrides
    }

    var debugOverrides: AIDebugOverrides { debug }

    var registeredProviders: [ProviderID] { providers.keys.sorted { $0.tier < $1.tier } }

    /// Pull a fresh remote config (if stale) and apply quotas.
    func refreshConfig(force: Bool = false) async {
        _ = await configStore.refreshIfStale(force: force)
        await applyConfigIfChanged()
    }

    func currentConfig() async -> AIRemoteConfig { await configStore.current }

    func clearCache() async { await cache.removeAll() }

    func resetCircuit(_ provider: ProviderID) async { await quota.reset(provider) }

    func quotaStatus(_ provider: ProviderID) async -> QuotaManager.Status { await quota.status(provider) }

    /// Call after any consent change. In-flight third-party requests that are no
    /// longer permitted are cancelled immediately (F01 §8).
    func consentDidChange() {
        for (id, flight) in inFlight where flight.provider.isThirdPartyCloud {
            if case .deny = privacyGate.evaluate(task: flight.task, privacy: flight.privacy, provider: flight.provider) {
                inFlight[id]?.reason = .consentRevoked
                flight.cancel()
            }
        }
    }

    // MARK: - Availability

    func availability(for task: AITask) async -> AITaskAvailability {
        await applyConfigIfChanged()
        let config = await configStore.current
        var chain: [(provider: ProviderID, availability: AIAvailability)] = []
        for id in resolvedChain(for: task, config: config) {
            chain.append((id, await availability(of: id, task: task, privacy: task.defaultPrivacy,
                                                 capabilities: task.requiredCapabilities)))
        }
        return AITaskAvailability(task: task, chain: chain)
    }

    func prewarm(for task: AITask) async {
        let summary = await availability(for: task)
        guard let primary = summary.primary, let provider = providers[primary] else { return }
        await provider.prewarm(for: task)
    }

    private func availability(of id: ProviderID, task: AITask, privacy: PrivacyClass,
                              capabilities: Set<AICapability>) async -> AIAvailability {
        guard let provider = providers[id] else { return .unavailable(.notImplemented) }
        if debug.forcedUnavailable.contains(id) { return .unavailable(.disabledByConfig) }
        guard capabilities.isSubset(of: provider.capabilities) else { return .unavailable(.unsupportedInput) }
        if case .deny = privacyGate.evaluate(task: task, privacy: privacy, provider: id) {
            return .unavailable(.consentRequired)
        }
        if case .unavailable(let reason) = await quota.check(id) { return .unavailable(reason) }
        return await provider.availability(for: task)
    }

    private func resolvedChain(for task: AITask, config: AIRemoteConfig) -> [ProviderID] {
        if let forced = debug.forcedChains[task], !forced.isEmpty { return forced }
        return routing.chain(for: task, config: config)
    }

    private func applyConfigIfChanged() async {
        let config = await configStore.current
        guard appliedQuotaConfig != config.quotas else { return }
        appliedQuotaConfig = config.quotas
        await quota.setLimits(config.quotaLimits)
    }

    // MARK: - Run

    func run<Output: AIOutput>(_ request: AIRequest<Output>) async throws -> AIResult<Output> {
        await applyConfigIfChanged()
        let config = await configStore.current
        let started = clock.now
        let deadline = started + request.latencyBudget
        let privacy = request.effectivePrivacy
        let signpostID = AILog.signposter.makeSignpostID()
        let interval = AILog.signposter.beginInterval("AIRequest", id: signpostID, "\(request.task.rawValue, privacy: .public)")
        defer { AILog.signposter.endInterval("AIRequest", interval) }

        let baseCall = ProviderCall(task: request.task, prompt: request.prompt, input: request.input,
                                    context: request.context, schema: Output.schema,
                                    outputIsPlainText: Output.isPlainText, generation: request.generation)

        // Cache (FR9): keyed on the unfiltered request so every tier shares it.
        let ttl = request.cachePolicy == .bypass ? nil : AIResponseCache.defaultTTL(for: request.task)
        let cacheKey = ttl == nil ? nil : AIResponseCache.key(for: baseCall)
        if let cacheKey, let hit = await cache.lookup(cacheKey),
           let output = try? JSONDecoder().decode(Output.self, from: hit.outputJSON) {
            let result = AIResult(output: output, provider: hit.provider, model: hit.model,
                                  promptVersion: hit.promptVersion, latency: clock.now - started,
                                  fromCache: true, degradedFrom: [])
            await record(task: request.task, result: result, outcome: .cacheHit, attempts: [])
            return result
        }

        var attempts: [AIAttempt] = []
        let chain = resolvedChain(for: request.task, config: config)

        for id in chain {
            try Task.checkCancellation()
            let attemptStarted = clock.now
            func fail(_ error: AIError) {
                attempts.append(AIAttempt(provider: id, error: error, latency: clock.now - attemptStarted))
            }

            guard let provider = providers[id] else { fail(.unavailable(.notImplemented)); continue }

            // Gate checks, cheapest first.
            if debug.forcedUnavailable.contains(id) { fail(.unavailable(.disabledByConfig)); continue }
            guard request.input.requiredCapabilities.isSubset(of: provider.capabilities) else {
                fail(.unsupportedInput); continue
            }
            let ceiling: PrivacyClass
            switch privacyGate.evaluate(task: request.task, privacy: privacy, provider: id) {
            case .deny(let error): fail(error); continue
            case .allow(let contextCeiling): ceiling = contextCeiling
            }
            let hasOverride = request.credentialOverrides[id] != nil
            if case .unavailable(let reason) = await provider.availability(for: request.task),
               !(reason == .missingCredential && hasOverride) {
                fail(.unavailable(reason)); continue
            }
            if !provider.isLocalFallback, clock.now >= deadline { fail(.timeout); continue }
            do { try await quota.reserve(id) } catch let error as AIError { fail(error); continue }

            var call = baseCall
            call.apiKeyOverride = request.credentialOverrides[id]
            if id.isThirdPartyCloud {
                call.context = request.context?.filtered(maxPrivacy: ceiling)
                call.prompt.user = PrivacyGate.redact(call.prompt.user)
            }

            do {
                let (output, response, outputJSON) = try await execute(provider, call: call, as: Output.self,
                                                                       privacy: privacy,
                                                                       deadline: provider.isLocalFallback ? nil : deadline)
                await quota.recordSuccess(id)
                let result = AIResult(output: output, provider: id, model: response.model,
                                      promptVersion: request.prompt.version, latency: clock.now - started,
                                      fromCache: false, degradedFrom: attempts)
                if let cacheKey, let ttl {
                    await cache.store(cacheKey, outputJSON: outputJSON, provider: id, model: response.model,
                                      promptVersion: request.prompt.version, ttl: ttl, privacy: privacy)
                }
                await record(task: request.task, result: result, outcome: .success, attempts: attempts)
                return result
            } catch {
                let aiError = AIError.from(error)
                fail(aiError)
                await quota.recordFailure(id, error: aiError)
                AILog.provider.info("\(id.rawValue, privacy: .public) failed \(request.task.rawValue, privacy: .public): \(aiError.code, privacy: .public)")
                if aiError == .cancelled { throw AIError.cancelled }
                if aiError == .guardrail || aiError == .refusal, !request.task.allowsGuardrailFallback {
                    await recordFailure(task: request.task, promptVersion: request.prompt.version,
                                        started: started, attempts: attempts)
                    throw aiError
                }
                continue
            }
        }

        await recordFailure(task: request.task, promptVersion: request.prompt.version, started: started, attempts: attempts)
        throw AIError.exhausted(attempts)
    }

    /// One provider attempt: call → validate → (one repair) → typed output.
    private func execute<Output: AIOutput>(_ provider: any AIProvider, call: ProviderCall, as: Output.Type,
                                           privacy: PrivacyClass, deadline: ContinuousClock.Instant?)
        async throws -> (Output, ProviderResponse, Data) {
        var call = call
        for round in 0..<2 {
            let response = try await callWithTimeout(provider, call: call, privacy: privacy, deadline: deadline)
            switch SchemaValidator.decode(response.raw, as: Output.self) {
            case .success(let output):
                let json = (try? JSONEncoder().encode(output)) ?? Data()
                return (output, response, json)
            case .failure(let failure):
                // Deterministic engines won't answer differently the second time.
                guard round == 0, !provider.isLocalFallback else {
                    throw AIError.invalidOutput(failure.issues.first ?? "invalid output")
                }
                AILog.provider.info("\(provider.id.rawValue, privacy: .public) repair retry: \(failure.issues.count) issue(s)")
                call.repairFeedback = failure.repairFeedback
                call.previousRaw = failure.raw
            }
        }
        throw AIError.invalidOutput("unreachable")
    }

    /// Runs `generate` in its own task so it can be cancelled by the deadline,
    /// by the caller, or by a consent revocation — whichever comes first.
    private func callWithTimeout(_ provider: any AIProvider, call: ProviderCall, privacy: PrivacyClass,
                                 deadline: ContinuousClock.Instant?) async throws -> ProviderResponse {
        let id = UUID()
        let work = Task.detached { try await provider.generate(call) }
        inFlight[id] = InFlight(provider: provider.id, task: call.task, privacy: privacy,
                                cancel: { work.cancel() }, reason: nil)
        defer { inFlight[id] = nil }

        let timer: Task<Void, Never>? = deadline.map { deadline in
            Task { [weak self] in
                try? await Task.sleep(until: deadline, clock: .continuous)
                guard !Task.isCancelled else { return }
                await self?.cancelInFlight(id, reason: .timeout)
            }
        }
        defer { timer?.cancel() }

        do {
            return try await withTaskCancellationHandler {
                try await work.value
            } onCancel: {
                work.cancel()
            }
        } catch {
            switch inFlight[id]?.reason {
            case .timeout?: throw AIError.timeout
            case .consentRevoked?: throw AIError.consentRequired(provider.id)
            case nil: break
            }
            if Task.isCancelled { throw AIError.cancelled }
            throw AIError.from(error)
        }
    }

    private func cancelInFlight(_ id: UUID, reason: CancelReason) {
        guard let flight = inFlight[id] else { return }
        inFlight[id]?.reason = reason
        flight.cancel()
    }

    // MARK: - Stream

    nonisolated func stream(_ request: AIRequest<AIText>) -> AsyncThrowingStream<AIStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { await self.runStream(request, continuation: continuation) }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Streams from the first provider that starts producing text. A provider that
    /// fails before its first token is skipped; a failure mid-stream is surfaced.
    private func runStream(_ request: AIRequest<AIText>,
                           continuation: AsyncThrowingStream<AIStreamEvent, Error>.Continuation) async {
        await applyConfigIfChanged()
        let config = await configStore.current
        let started = clock.now
        let privacy = request.effectivePrivacy
        var attempts: [AIAttempt] = []

        for id in resolvedChain(for: request.task, config: config) {
            let attemptStarted = clock.now
            guard let provider = providers[id] else { continue }
            func fail(_ error: AIError) {
                attempts.append(AIAttempt(provider: id, error: error, latency: clock.now - attemptStarted))
            }
            if debug.forcedUnavailable.contains(id) { fail(.unavailable(.disabledByConfig)); continue }
            let ceiling: PrivacyClass
            switch privacyGate.evaluate(task: request.task, privacy: privacy, provider: id) {
            case .deny(let error): fail(error); continue
            case .allow(let contextCeiling): ceiling = contextCeiling
            }
            if case .unavailable(let reason) = await provider.availability(for: request.task) {
                fail(.unavailable(reason)); continue
            }
            do { try await quota.reserve(id) } catch let error as AIError { fail(error); continue } catch { continue }

            var call = ProviderCall(task: request.task, prompt: request.prompt, input: request.input,
                                    context: request.context, schema: AIText.schema, outputIsPlainText: true,
                                    generation: request.generation)
            if id.isThirdPartyCloud {
                call.context = request.context?.filtered(maxPrivacy: ceiling)
                call.prompt.user = PrivacyGate.redact(call.prompt.user)
            }

            var latest = ""
            var started_ = false
            do {
                for try await snapshot in provider.stream(call) {
                    started_ = true
                    latest = snapshot
                    continuation.yield(.partial(snapshot))
                }
                await quota.recordSuccess(id)
                let text = latest.trimmingCharacters(in: .whitespacesAndNewlines)
                let result = AIResult(output: AIText(text: text), provider: id, model: id.rawValue,
                                      promptVersion: request.prompt.version, latency: clock.now - started,
                                      fromCache: false, degradedFrom: attempts)
                await record(task: request.task, result: result, outcome: .success, attempts: attempts)
                continuation.yield(.completed(result))
                continuation.finish()
                return
            } catch {
                let aiError = AIError.from(error)
                fail(aiError)
                await quota.recordFailure(id, error: aiError)
                if started_ || aiError == .cancelled || Task.isCancelled {
                    continuation.finish(throwing: aiError)
                    return
                }
            }
        }
        await recordFailure(task: request.task, promptVersion: request.prompt.version, started: started, attempts: attempts)
        continuation.finish(throwing: AIError.exhausted(attempts))
    }

    // MARK: - Telemetry

    private func record<Output>(task: AITask, result: AIResult<Output>, outcome: AIEvent.Outcome, attempts: [AIAttempt]) async {
        let event = AIEvent(id: UUID(), date: Date(), task: task, provider: result.provider, model: result.model,
                            outcome: outcome, errorCode: nil, latencyMs: result.latency.milliseconds,
                            promptVersion: result.promptVersion,
                            attempts: attempts.map { .init(provider: $0.provider, errorCode: $0.error.code, latencyMs: $0.latency.milliseconds) })
        AILog.gateway.info("""
            \(task.rawValue, privacy: .public) → \(result.provider.rawValue, privacy: .public) \
            \(outcome.rawValue, privacy: .public) \(event.latencyMs)ms after \(attempts.count) fallback(s)
            """)
        await events.record(event)
    }

    private func recordFailure(task: AITask, promptVersion: String, started: ContinuousClock.Instant, attempts: [AIAttempt]) async {
        let event = AIEvent(id: UUID(), date: Date(), task: task, provider: nil, model: nil, outcome: .failed,
                            errorCode: attempts.last?.error.code ?? "noProviders",
                            latencyMs: (clock.now - started).milliseconds, promptVersion: promptVersion,
                            attempts: attempts.map { .init(provider: $0.provider, errorCode: $0.error.code, latencyMs: $0.latency.milliseconds) })
        AILog.gateway.notice("\(task.rawValue, privacy: .public) exhausted after \(attempts.count) attempt(s)")
        await events.record(event)
    }
}

nonisolated extension AIError {
    /// Normalises any thrown error into the taxonomy.
    nonisolated static func from(_ error: Error) -> AIError {
        switch error {
        case let error as AIError:
            return error
        case is CancellationError:
            return .cancelled
        case let error as URLError:
            switch error.code {
            case .cancelled: return .cancelled
            case .timedOut: return .timeout
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
                return .unavailable(.offline)
            default: return .network(error.code.rawValue.description)
            }
        default:
            return .server(-1)
        }
    }
}
