// swift-tools-version: 6.0

// Purpose: Define the server executable, reusable backend module, tests, and embedded migration resource.
// Inputs: Checked-in Swift sources and compatible Vapor/PostgresNIO package versions.
// Outputs: RevaAPI executable and RevaServer test products resolved through Swift Package Manager.
// Side effects: Package resolution/builds can fetch dependencies and write build artifacts, but do not run the server.

import PackageDescription

// MARK: - Build products and source/resource ownership
let package = Package(
    name: "RevaServer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "RevaAPI", targets: ["Run"])],
    // MARK: - External server dependencies
    // Versions are resolved in Package.resolved; the native app does not depend on these packages.
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.1"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0"),
    ],
    // MARK: - Reusable backend, thin executable, and contract tests
    targets: [
        .target(
            name: "RevaServer",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                .product(name: "PostgresNIO", package: "postgres-nio"),
            ], resources: [.copy("Migrations")]),
        .executableTarget(name: "Run", dependencies: ["RevaServer"]),
        .testTarget(
            name: "RevaServerTests",
            dependencies: ["RevaServer", .product(name: "VaporTesting", package: "vapor")]),
    ]
)
