// swift-tools-version: 5.9
// Purpose: Define the Swift package for the platform-independent Reva domain and client tests.
// Inputs: Core Swift sources and XCTest files at the explicit target paths below.
// Outputs: The RevaCore library product and its RevaCoreTests test target.
// Side effects: Manifest evaluation declares build metadata; it does not run the app or contact providers.

import PackageDescription

// MARK: - Library product and test target

let package = Package(
    name: "RevaCore",
    platforms: [.macOS(.v13), .iOS("18.0")],
    products: [.library(name: "RevaCore", targets: ["RevaCore"])],
    targets: [
        .target(name: "RevaCore", path: "apps/ios/Reva/Core"),
        .testTarget(name: "RevaCoreTests", dependencies: ["RevaCore"], path: "Tests/RevaCoreTests"),
    ]
)
