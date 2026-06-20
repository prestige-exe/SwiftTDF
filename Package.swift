// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftTDF",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "SwiftTDF", targets: ["SwiftTDF"]),
    ],
    targets: [
        .target(name: "SwiftTDF"),
        .testTarget(name: "SwiftTDFTests", dependencies: ["SwiftTDF"]),
    ],
    swiftLanguageModes: [.v6]
)
