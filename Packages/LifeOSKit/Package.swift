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
        .library(name: "LifeOSConnectivity", targets: ["LifeOSConnectivity"])
    ],
    targets: [
        // Pure Swift: models, calculators, DayKey. Foundation + os only. Safe on watchOS.
        .target(name: "LifeOSCore"),
        // Date-keyed file store, repositories, legacy migration. iPhone only.
        .target(name: "LifeOSData", dependencies: ["LifeOSCore"],
                resources: [.process("PrivacyInfo.xcprivacy")]),
        // Typed, versioned phone <-> watch contract.
        .target(name: "LifeOSConnectivity", dependencies: ["LifeOSCore"]),

        .testTarget(name: "LifeOSCoreTests", dependencies: ["LifeOSCore"]),
        .testTarget(name: "LifeOSDataTests", dependencies: ["LifeOSData"]),
        .testTarget(name: "LifeOSConnectivityTests", dependencies: ["LifeOSConnectivity"])
    ],
    swiftLanguageModes: [.v6]
)
