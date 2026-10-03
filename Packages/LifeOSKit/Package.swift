// swift-tools-version: 6.0
import PackageDescription

// LifeOSKit — shared, UI-free modules for the iPhone and Watch apps.
// See docs/adr/0002-module-structure.md for why these live in one package.
let package = Package(
    name: "LifeOSKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "LifeOSCore", targets: ["LifeOSCore"]),
        .library(name: "LifeOSData", targets: ["LifeOSData"]),
        .library(name: "LifeOSConnectivity", targets: ["LifeOSConnectivity"]),
        .library(name: "LifeOSHealth", targets: ["LifeOSHealth"]),
        .library(name: "LifeOSAPI", targets: ["LifeOSAPI"])
    ],
    targets: [
        // Pure Swift: models, calculators, DayKey. Foundation + os only. Safe on watchOS.
        .target(name: "LifeOSCore"),
        // Date-keyed file store, repositories, legacy migration. iPhone only.
        .target(name: "LifeOSData", dependencies: ["LifeOSCore"],
                resources: [.process("PrivacyInfo.xcprivacy")]),
        // Typed, versioned phone <-> watch contract.
        .target(name: "LifeOSConnectivity", dependencies: ["LifeOSCore"]),
        // HealthKit ingestion (doc 02). The service is tested against a fake client.
        .target(name: "LifeOSHealth", dependencies: ["LifeOSCore", "LifeOSData"]),
        // Client for the LifeOS AI proxy (doc 07, BE-11): App Attest, install
        // tokens, signed requests, typed errors. Foundation + DeviceCheck only.
        .target(name: "LifeOSAPI"),

        .testTarget(name: "LifeOSCoreTests", dependencies: ["LifeOSCore"]),
        .testTarget(name: "LifeOSDataTests", dependencies: ["LifeOSData"]),
        .testTarget(name: "LifeOSConnectivityTests", dependencies: ["LifeOSConnectivity"]),
        .testTarget(name: "LifeOSHealthTests", dependencies: ["LifeOSHealth"]),
        .testTarget(name: "LifeOSAPITests", dependencies: ["LifeOSAPI"])
    ],
    swiftLanguageModes: [.v6]
)
