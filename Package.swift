// swift-tools-version: 6.2
//
// LifeOS AI — SwiftPM harness.
//
// The AI sources live in `LifeOS/AI/` and are compiled straight into the iOS app
// by Xcode's synchronized folder (no project-file edits needed). This package
// compiles the *same* sources as a standalone module so the AI team can run unit
// tests, evals and the `ai-eval` CLI with plain `swift test` / `swift run` — on a
// laptop with only the Command Line Tools, or on a CI macOS runner.
//
// Concurrency settings mirror the app target (SWIFT_VERSION 5, default actor
// isolation MainActor, approachable concurrency) so anything that compiles here
// compiles in the app. `LifeOS/AI/AppIntegration/` depends on UIKit and app types
// and is therefore excluded here; it is only built by Xcode.

import PackageDescription

let appMatchingSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("MemberImportVisibility"),
    // Stricter than the app on purpose: concurrency problems surface here as
    // warnings before they become runtime bugs on device.
    .enableUpcomingFeature("StrictConcurrency"),
]

let package = Package(
    name: "LifeOSAI",
    platforms: [.iOS("17.6"), .macOS(.v14)],
    products: [
        .library(name: "LifeOSAI", targets: ["LifeOSAI"]),
        .executable(name: "ai-eval", targets: ["ai-eval"]),
    ],
    targets: [
        .target(
            name: "LifeOSAI",
            path: "LifeOS/AI",
            exclude: ["AppIntegration"],
            swiftSettings: appMatchingSettings
        ),
        .target(
            name: "LifeOSAIEvalKit",
            dependencies: ["LifeOSAI"],
            path: "Evals/EvalKit",
            swiftSettings: appMatchingSettings
        ),
        .executableTarget(
            name: "ai-eval",
            dependencies: ["LifeOSAI", "LifeOSAIEvalKit"],
            path: "Tools/ai-eval",
            swiftSettings: appMatchingSettings
        ),
        .testTarget(
            name: "LifeOSAITests",
            dependencies: ["LifeOSAI"],
            path: "Tests/LifeOSAITests",
            swiftSettings: appMatchingSettings
        ),
        .testTarget(
            name: "LifeOSAIEvals",
            dependencies: ["LifeOSAI", "LifeOSAIEvalKit"],
            path: "Tests/LifeOSAIEvals",
            swiftSettings: appMatchingSettings
        ),
    ],
    swiftLanguageModes: [.v5]
)
