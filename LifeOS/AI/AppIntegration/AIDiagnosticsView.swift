import Observation
import SwiftUI

/// "AI diagnostics" (F01 FR14 / Phase 0 demo). Debug builds and TestFlight only.
///
/// Toggle providers live, run the same food sentence through every tier with
/// provenance and latency, inspect quotas/circuits, consent and recent events.
/// Shows no user content beyond what the tester types here.
struct AIDiagnosticsView: View {
    @State private var model = AIDiagnosticsModel()

    static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
        #endif
    }

    var body: some View {
        NavigationStack {
            List {
                tierDemoSection
                providersSection
                availabilitySection
                consentSection
                configSection
                eventsSection
            }
            .navigationTitle("AI diagnostics")
            .task { await model.reload() }
            .refreshable { await model.reload() }
        }
    }

    // MARK: Sections

    private var tierDemoSection: some View {
        Section {
            TextField("Food sentence", text: $model.sentence, axis: .vertical)
                .lineLimit(1...3)
            HStack {
                Button("Run every tier") { Task { await model.runEveryTier() } }
                Spacer()
                Button("Run routed") { Task { await model.runRouted() } }
            }
            .disabled(model.isRunning)
            if model.isRunning { ProgressView() }
            ForEach(model.tierRuns) { run in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(run.label).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(run.latency).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(run.detail).font(.caption).foregroundStyle(run.failed ? .red : .primary)
                }
            }
        } header: {
            Text("Tier demo · foodTextParse")
        } footer: {
            Text("\"Run every tier\" pins the chain to one provider at a time. \"Run routed\" uses the live routing table and shows which tier answered and what it fell back from.")
        }
    }

    private var providersSection: some View {
        Section("Providers (force unavailable)") {
            ForEach(ProviderID.allCases, id: \.self) { provider in
                VStack(alignment: .leading, spacing: 2) {
                    Toggle(isOn: Binding(
                        get: { !model.forcedOff.contains(provider) },
                        set: { enabled in Task { await model.setProvider(provider, enabled: enabled) } })) {
                        Text("\(provider.tier.rawValue.uppercased()) · \(provider.displayName)")
                    }
                    if let status = model.quota[provider] {
                        Text(status).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var availabilitySection: some View {
        Section("Routing & availability") {
            ForEach(model.availability, id: \.task) { summary in
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.task.rawValue).font(.subheadline.weight(.semibold))
                    Text(summary.chain.map { "\($0.provider.rawValue): \(Self.describe($0.availability))" }
                        .joined(separator: " → "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var consentSection: some View {
        Section {
            ForEach([ProviderID.groqBYOK, .geminiBYOK], id: \.self) { provider in
                HStack {
                    VStack(alignment: .leading) {
                        Text(provider.displayName)
                        Text(model.consentText(for: provider)).font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Revoke", role: .destructive) { model.revoke(provider) }
                        .disabled(AIServices.shared.consents.consent(for: provider) == nil)
                }
            }
            SecureField("Gemini API key (testing)", text: $model.geminiKey)
            HStack {
                Button("Save Gemini key") { model.saveGeminiKey() }
                    .disabled(model.geminiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button("Delete", role: .destructive) { model.deleteGeminiKey() }
            }
        } header: {
            Text("Third-party cloud consent & keys")
        } footer: {
            Text("Saving a key grants personal-data consent only. Health data always needs the explicit consent sheet (Phase 1, design kit C6).")
        }
    }

    private var configSection: some View {
        Section("Remote config") {
            LabeledContent("Prompt version", value: model.config?.promptVersion ?? "—")
            LabeledContent("Groq vision", value: model.config?.groqVisionModels.joined(separator: ", ") ?? "—")
            LabeledContent("Gemini", value: model.config?.geminiModels.joined(separator: ", ") ?? "—")
            LabeledContent("PCC enabled", value: (model.config?.flags.pccEnabled ?? false) ? "yes" : "no")
            LabeledContent("Apple photo vision", value: (model.config?.flags.photoAppleVision ?? false) ? "yes" : "no")
            Button("Refresh config") { Task { await model.refreshConfig() } }
            Button("Clear response cache", role: .destructive) { Task { await model.clearCache() } }
        }
    }

    private var eventsSection: some View {
        Section("Recent requests") {
            if model.events.isEmpty { Text("No AI requests yet").foregroundStyle(.secondary) }
            ForEach(model.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(event.task.rawValue).font(.caption.weight(.semibold))
                        Spacer()
                        Text("\(event.latencyMs) ms").font(.caption2.monospacedDigit())
                    }
                    Text("\(event.outcome.rawValue) · \(event.provider?.rawValue ?? event.errorCode ?? "—")"
                         + (event.attempts.isEmpty ? "" : " · fell back from " + event.attempts.map { "\($0.provider.rawValue)(\($0.errorCode))" }.joined(separator: ", ")))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    static func describe(_ availability: AIAvailability) -> String {
        switch availability {
        case .available: "ok"
        case .unavailable(let reason): reason.rawValue
        }
    }
}

@Observable
final class AIDiagnosticsModel {
    struct TierRun: Identifiable {
        let id = UUID()
        var label: String
        var detail: String
        var latency: String
        var failed: Bool
    }

    var sentence = "two rotis, dal and a bowl of curd for lunch"
    var tierRuns: [TierRun] = []
    var isRunning = false
    var forcedOff: Set<ProviderID> = []
    var availability: [AITaskAvailability] = []
    var quota: [ProviderID: String] = [:]
    var events: [AIEvent] = []
    var config: AIRemoteConfig?
    var geminiKey = ""

    private var gateway: AIGateway { AIServices.shared.gateway }

    func reload() async {
        forcedOff = await gateway.debugOverrides.forcedUnavailable
        config = await gateway.currentConfig()
        var summaries: [AITaskAvailability] = []
        for task in [AITask.foodTextParse, .mealPhotoAnalyze, .mealPhotoRefine, .memoryExtract, .assistantChat] {
            summaries.append(await gateway.availability(for: task))
        }
        availability = summaries
        var quotaText: [ProviderID: String] = [:]
        for provider in ProviderID.allCases {
            let status = await gateway.quotaStatus(provider)
            var text = "used \(status.usedLastMinute)/min, \(status.usedToday)/day"
            if status.consecutiveFailures > 0 { text += " · \(status.consecutiveFailures) consecutive failure(s)" }
            if let until = status.circuitOpenUntil { text += " · circuit open until \(until.formatted(date: .omitted, time: .shortened))" }
            quotaText[provider] = text
        }
        quota = quotaText
        events = await gateway.events.recent(30)
    }

    func setProvider(_ provider: ProviderID, enabled: Bool) async {
        var overrides = await gateway.debugOverrides
        if enabled { overrides.forcedUnavailable.remove(provider) } else { overrides.forcedUnavailable.insert(provider) }
        await gateway.setDebugOverrides(overrides)
        await reload()
    }

    func runEveryTier() async {
        isRunning = true
        defer { isRunning = false }
        tierRuns = []
        let original = await gateway.debugOverrides
        for provider in [ProviderID.appleOnDevice, .applePCC, .geminiBYOK, .groqBYOK, .deterministic] {
            var pinned = original
            pinned.forcedChains[.foodTextParse] = [provider]
            await gateway.setDebugOverrides(pinned)
            tierRuns.append(await run(label: "\(provider.tier.rawValue.uppercased()) · \(provider.displayName)"))
        }
        await gateway.setDebugOverrides(original)
        await reload()
    }

    func runRouted() async {
        isRunning = true
        defer { isRunning = false }
        tierRuns = [await run(label: "Routed")]
        await reload()
    }

    private func run(label: String) async -> TierRun {
        let request = AIRequest<ParsedMeal>(task: .foodTextParse, prompt: PromptRegistry.foodTextParse(sentence),
                                            input: .text(sentence), privacy: .personal,
                                            latencyBudget: .seconds(20), cachePolicy: .bypass)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            let result = try await gateway.run(request)
            let items = result.output.items.map { "\($0.quantity.formatted()) \($0.unit) \($0.name)" }.joined(separator: ", ")
            let fallback = result.degradedFrom.isEmpty ? "" : " (after \(result.degradedFrom.map { "\($0.provider.rawValue):\($0.error.code)" }.joined(separator: ", ")))"
            return TierRun(label: "\(label) → \(result.provider.displayName)",
                           detail: "[\(result.output.mealType.rawValue)] \(items.isEmpty ? "no items" : items)\(fallback)",
                           latency: "\(result.latency.milliseconds) ms", failed: false)
        } catch let error as AIError {
            let detail: String
            if case .exhausted(let attempts) = error {
                detail = attempts.map { "\($0.provider.rawValue): \($0.error.code)" }.joined(separator: " · ")
            } else {
                detail = error.code
            }
            return TierRun(label: label, detail: detail, latency: "\((clock.now - start).milliseconds) ms", failed: true)
        } catch {
            return TierRun(label: label, detail: "\(error)", latency: "—", failed: true)
        }
    }

    func consentText(for provider: ProviderID) -> String {
        guard let consent = AIServices.shared.consents.consent(for: provider) else { return "No consent" }
        return "\(consent.maxPrivacy.rawValue) · \(consent.source.rawValue) · \(consent.grantedAt.formatted(date: .abbreviated, time: .omitted))"
    }

    func revoke(_ provider: ProviderID) {
        AIServices.shared.revokeCloudConsent(for: provider)
        Task { await reload() }
    }

    func saveGeminiKey() {
        guard AIServices.shared.credentials.save(geminiKey, for: .geminiBYOK) else { return }
        AIServices.shared.recordKeyEntryConsent(for: .geminiBYOK)
        geminiKey = ""
        Task { await reload() }
    }

    func deleteGeminiKey() {
        AIServices.shared.credentials.delete(.geminiBYOK)
        AIServices.shared.revokeCloudConsent(for: .geminiBYOK)
        Task { await reload() }
    }

    func refreshConfig() async {
        await gateway.refreshConfig(force: true)
        await reload()
    }

    func clearCache() async {
        await gateway.clearCache()
        await reload()
    }
}
