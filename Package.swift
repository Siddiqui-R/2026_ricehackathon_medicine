// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RevaCore",
    platforms: [.macOS(.v13), .iOS("18.0")],
    products: [.library(name: "RevaCore", targets: ["RevaCore"])],
    targets: [
        .target(name: "RevaCore", path: "apps/ios/Reva/Core"),
        .testTarget(name: "RevaCoreTests", dependencies: ["RevaCore"], path: "Tests/RevaCoreTests")
    ]
)
