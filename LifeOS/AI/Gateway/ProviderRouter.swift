import Foundation

/// Task → ordered provider chain (F01 FR3, §5.2).
///
/// The code-defined table is the default; remote config can replace a task's
/// chain, kill-switch providers, or flip feature flags that add conditional
/// entries. The first available provider in the chain wins.
nonisolated struct RoutingTable: Sendable, Equatable {

    nonisolated struct Entry: Sendable, Equatable {
        var provider: ProviderID
        /// Included only when this remote-config flag is on.
        var requiresFlag: AIFeatureFlag?

        init(_ provider: ProviderID, requires flag: AIFeatureFlag? = nil) {
            self.provider = provider
            self.requiresFlag = flag
        }
    }

    var chains: [AITask: [Entry]]

    /// v1 routing table (F01 §5.2).
    static let v1 = RoutingTable(chains: [
        .foodTextParse: [.init(.appleOnDevice), .init(.applePCC, requires: .pccEnabled),
                         .init(.geminiBYOK), .init(.groqBYOK), .init(.deterministic)],
        // Learned overrides run before the gateway (deterministic, in MealScannerEngine).
        // Apple vision is flag-gated so Phase 0 photo behaviour is unchanged.
        .mealPhotoAnalyze: [.init(.appleOnDevice, requires: .photoAppleVision),
                            .init(.applePCC, requires: .photoAppleVision),
                            .init(.geminiBYOK, requires: .photoAppleVision),
                            .init(.groqBYOK), .init(.visionLegacy)],
        .mealPhotoRefine: [.init(.appleOnDevice, requires: .photoAppleVision),
                           .init(.applePCC, requires: .photoAppleVision),
                           .init(.geminiBYOK, requires: .photoAppleVision),
                           .init(.groqBYOK)],
        .nutritionLabelRead: [.init(.appleOnDevice), .init(.deterministic)],
        .memoryExtract: [.init(.appleOnDevice), .init(.applePCC, requires: .pccEnabled)],
        .memoryConsolidate: [.init(.appleOnDevice), .init(.applePCC, requires: .pccEnabled)],
        .assistantChat: [.init(.appleOnDevice), .init(.applePCC, requires: .pccEnabled), .init(.geminiBYOK)],
        .briefingCompose: [.init(.appleOnDevice), .init(.deterministic)],
        .nudgeCompose: [.init(.appleOnDevice), .init(.deterministic)],
        .budgetExplain: [.init(.appleOnDevice), .init(.deterministic)],
        .weeklyReview: [.init(.applePCC, requires: .pccEnabled), .init(.appleOnDevice), .init(.deterministic)],
        .presetSuggestName: [.init(.appleOnDevice), .init(.deterministic)],
    ])

    /// Resolves the effective chain for a task under a config.
    func chain(for task: AITask, config: AIRemoteConfig) -> [ProviderID] {
        let base: [ProviderID]
        if let override = config.routing[task.rawValue], !override.isEmpty {
            base = override
        } else {
            base = (chains[task] ?? []).compactMap { entry in
                guard let flag = entry.requiresFlag else { return entry.provider }
                return config.flags.isOn(flag) ? entry.provider : nil
            }
        }
        let disabled = Set(config.disabledProviders)
        var seen = Set<ProviderID>()
        return base.filter { !disabled.contains($0) && seen.insert($0).inserted }
    }
}
