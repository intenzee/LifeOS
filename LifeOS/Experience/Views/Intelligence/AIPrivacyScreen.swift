import SwiftUI

/// 4.5 AI and privacy. Every line here is read from the running gateway, so it
/// stays true: availability, saved keys, consent and today's usage.
struct AIPrivacyScreen: View {
    var onOpenMemory: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lxTheme) private var theme

    @State private var onDevice: AIAvailability?
    @State private var usage: [ProviderID: QuotaManager.Status] = [:]
    @State private var hasKey: [ProviderID: Bool] = [:]
    @State private var consent: [ProviderID: CloudConsent] = [:]
    @State private var keyDraft: [ProviderID: String] = [:]
    @State private var testResult: [ProviderID: String] = [:]
    @State private var testing: ProviderID?

    private let services = AIServices.shared
    private let cloud: [ProviderID] = [.groqBYOK, .geminiBYOK]

    var body: some View {
        NavigationStack {
            Form {
                Section("Where AI runs") {
                    LabeledContent("On device") {
                        Text(onDeviceText).foregroundStyle(onDevice?.isAvailable == true ? .lx(.statusOnTrack) : .lx(.textSecondary))
                    }
                    ForEach(cloud, id: \.self) { p in
                        Toggle(isOn: Binding(get: { consent[p] != nil && hasKey[p] == true }, set: { setCloud(p, on: $0) })) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(name(p))
                                Text(hasKey[p] == true ? "Your free key is saved" : "Add a key below to use it").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .disabled(hasKey[p] != true)
                        .tint(theme.color(.accentPrimary))
                    }
                }

                Section {
                    ForEach(cloud, id: \.self) { p in keyRow(p) }
                } header: { Text("Free keys") } footer: {
                    Text("Keys are stored in the iPhone Keychain, on this device only. Get a free Groq key at console.groq.com → API Keys, or a Gemini key at aistudio.google.com → Get API key, then paste it here.")
                }

                Section("Today's free usage") {
                    ForEach(cloud, id: \.self) { p in
                        let s = usage[p]
                        let limit = s?.limits.perDay ?? 0
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(name(p))
                                Spacer()
                                Text(limit > 0 ? "\(s?.usedToday ?? 0) of \(limit) requests" : "\(s?.usedToday ?? 0) requests")
                                    .monospacedDigit().foregroundStyle(.secondary)
                            }
                            if limit > 0 { LXProgressBar(value: Double(s?.usedToday ?? 0) / Double(limit), role: .accentPrimary) }
                            if let until = s?.circuitOpenUntil, until > Date() {
                                Text("Paused after errors until \(until.formatted(date: .omitted, time: .shortened)). On-device estimates are used meanwhile.")
                                    .font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text("When a daily limit is reached, LifeOS switches to on-device estimates until tomorrow.").font(.footnote).foregroundStyle(.secondary)
                }

                Section("What is shared") {
                    LXRowLabel(title: "Photo estimates", explanation: "Send the photo, plus the names of dishes you corrected before if they look similar. Never your name or health history.", systemImage: "camera")
                    LXRowLabel(title: "Typed or spoken meals", explanation: "Send only the sentence, e.g. “2 rotis and dal”. Calories are worked out on this iPhone.", systemImage: "text.bubble")
                    LXRowLabel(title: "Assistant", explanation: "Most answers are worked out on this iPhone. Open questions send a short summary of your recent days and memories, only to Apple Intelligence or to Gemini if you allow health questions.", systemImage: "sparkles")
                    LXRowLabel(title: "Memory", explanation: "Learned on this iPhone only. Memory extraction never goes to Groq or Gemini.", systemImage: "brain")
                }

                Section {
                    Toggle(isOn: Binding(get: { consent[.geminiBYOK]?.maxPrivacy == .health }, set: { setGeminiHealth($0) })) {
                        Text("Allow health questions to Gemini")
                    }
                    .disabled(hasKey[.geminiBYOK] != true)
                    .tint(theme.color(.accentPrimary))
                } header: { Text("Gemini") } footer: {
                    Text("Google may use content sent on the free tier to improve its products. Health questions are only sent to Gemini if you turn this on.")
                }

                Section {
                    Button { dismiss(); onOpenMemory() } label: { Label("What LifeOS knows", systemImage: "brain.head.profile") }
                }
            }
            .navigationTitle("AI and privacy").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await refresh() }
        }
    }

    private var onDeviceText: String {
        switch onDevice {
        case .available?: return "On"
        case .unavailable(.deviceNotEligible)?, .unavailable(.osTooOld)?: return "Not available on this iPhone"
        case .unavailable(.appleIntelligenceNotEnabled)?: return "Turn on Apple Intelligence in Settings"
        case .unavailable(.modelNotReady)?: return "Downloading…"
        case .unavailable?: return "Unavailable"
        case nil: return "Checking…"
        }
    }

    private func name(_ p: ProviderID) -> String { p == .groqBYOK ? "Groq" : "Gemini" }

    @ViewBuilder private func keyRow(_ p: ProviderID) -> some View {
        if hasKey[p] == true {
            HStack {
                Label("\(name(p)) key saved", systemImage: "key.fill")
                Spacer()
                Button(testing == p ? "Testing…" : "Test key") { Task { await test(p) } }.disabled(testing != nil)
                Button("Remove", role: .destructive) { removeKey(p) }
            }
            .buttonStyle(.borderless)
            if let r = testResult[p] { Text(r).font(.footnote).foregroundStyle(.secondary) }
        } else {
            HStack {
                SecureField("Paste your \(name(p)) key", text: Binding(get: { keyDraft[p] ?? "" }, set: { keyDraft[p] = $0 }))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Save") { saveKey(p) }.disabled((keyDraft[p] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    // MARK: Actions

    private func refresh() async {
        let gateway = services.gateway
        onDevice = await gateway.availability(for: .foodTextParse).chain.first { $0.provider == .appleOnDevice }?.availability
        for p in cloud {
            usage[p] = await gateway.quotaStatus(p)
            hasKey[p] = services.credentials.apiKey(for: p) != nil
            consent[p] = services.consents.consent(for: p)
        }
    }

    private func saveKey(_ p: ProviderID) {
        guard let k = keyDraft[p], services.credentials.save(k, for: p) else { return }
        keyDraft[p] = nil
        // Same as the existing key screen: saving a key on a disclosing screen covers personal data, never health.
        if services.consents.consent(for: p) == nil {
            services.consents.grant(CloudConsent(maxPrivacy: .personal, grantedAt: Date(), source: .keyEntry), for: p)
        }
        Task { await refresh() }
    }

    private func removeKey(_ p: ProviderID) {
        services.credentials.delete(p)
        services.consents.revoke(p)
        Task { await services.gateway.consentDidChange(); await refresh() }
    }

    private func setCloud(_ p: ProviderID, on: Bool) {
        if on {
            services.consents.grant(CloudConsent(maxPrivacy: .personal, grantedAt: Date(), source: .keyEntry), for: p)
        } else {
            services.consents.revoke(p)
        }
        Task { await services.gateway.consentDidChange(); await refresh() }
    }

    private func setGeminiHealth(_ on: Bool) {
        let level: PrivacyClass = on ? .health : .personal
        services.consents.grant(CloudConsent(maxPrivacy: level, grantedAt: Date(), source: on ? .consentSheet : .keyEntry), for: .geminiBYOK)
        Task { await services.gateway.consentDidChange(); await refresh() }
    }

    private func test(_ p: ProviderID) async {
        testing = p
        defer { testing = nil }
        do {
            let result = try await services.gateway.run(AIRequest<ParsedMeal>(
                task: .foodTextParse, prompt: PromptRegistry.foodTextParse("one banana"), input: .text("one banana"),
                privacy: .personal, latencyBudget: .seconds(15), cachePolicy: .bypass))
            testResult[p] = result.provider == p ? "Works. \(name(p)) answered in \(result.latency.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))."
                                                 : "Answered by \(result.provider.displayName) instead; \(name(p)) wasn't used. Check the key and the toggle above."
        } catch {
            testResult[p] = "That didn't work: \(error.localizedDescription)"
        }
        await refresh()
    }
}
