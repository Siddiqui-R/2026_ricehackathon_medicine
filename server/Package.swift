// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RevaServer",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "RevaAPI", targets: ["Run"])],
    dependencies: [
        .package(url: "https://github.com/vapor/vapor.git", from: "4.110.1"),
        .package(url: "https://github.com/vapor/postgres-nio.git", from: "1.21.0")
    ],
    targets: [
        .target(name: "RevaServer", dependencies: [
            .product(name: "Vapor", package: "vapor"),
            .product(name: "PostgresNIO", package: "postgres-nio")
        ], resources: [.copy("Migrations")]),
        .executableTarget(name: "Run", dependencies: ["RevaServer"]),
        .testTarget(name: "RevaServerTests", dependencies: ["RevaServer", .product(name: "VaporTesting", package: "vapor")])
    ]
)
