// swift-tools-version: 6.2
//
// LifeOSDesign — test harness for the design system.
//
// The sources live in `LifeOS/DesignSystem/` and are compiled straight into the
// iOS app by Xcode's synchronized folder (no project-file edits). This package
// reaches them through the `Sources/LifeOSDesign` symlink so the design system
// can be unit-tested, contrast-checked and snapshot-rendered with plain
// `swift test` on a Mac with only the Command Line Tools.
//
// Settings mirror the app target (Swift 5 mode, MainActor default isolation,
// approachable concurrency) so anything that compiles here compiles in the app.
//
//   cd Packages/LifeOSDesign && swift test
//   LX_RENDER_DIR=/path swift test --filter Render   # write mockup PNGs

import PackageDescription

let appMatchingSettings: [SwiftSetting] = [
    .defaultIsolation(MainActor.self),
    .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
    .enableUpcomingFeature("InferIsolatedConformances"),
    .enableUpcomingFeature("InferSendableFromCaptures"),
    .enableUpcomingFeature("GlobalActorIsolatedTypesUsability"),
    .enableUpcomingFeature("DisableOutwardActorInference"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let package = Package(
    name: "LifeOSDesign",
    platforms: [.iOS("17.6"), .macOS(.v14)],
    products: [.library(name: "LifeOSDesign", targets: ["LifeOSDesign"])],
    targets: [
        .target(name: "LifeOSDesign", swiftSettings: appMatchingSettings),
        // UI/UX Phase 3 pure logic (budget maths, meal timing, copy, snapshots):
        // `LifeOS/Experience/Core`, Foundation only, symlinked like the design system.
        .target(name: "LifeOSExperienceCore", swiftSettings: appMatchingSettings),
        .testTarget(name: "LifeOSDesignTests", dependencies: ["LifeOSDesign"], swiftSettings: appMatchingSettings),
        .testTarget(name: "LifeOSExperienceTests", dependencies: ["LifeOSExperienceCore"], swiftSettings: appMatchingSettings),
    ],
    swiftLanguageModes: [.v5]
)
