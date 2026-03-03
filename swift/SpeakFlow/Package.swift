// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpeakFlow",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "SpeakFlowApp", targets: ["SpeakFlowApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
    ],
    targets: [
        .target(
            name: "Domain"
        ),
        .target(
            name: "Infra",
            dependencies: [
                "Domain",
                .product(name: "WhisperKit", package: "WhisperKit"),
            ]
        ),
        .target(
            name: "Platform",
            dependencies: ["Domain", "Infra"]
        ),
        .target(
            name: "AppLayer",
            dependencies: ["Domain", "Infra", "Platform"]
        ),
        .executableTarget(
            name: "SpeakFlowApp",
            dependencies: ["AppLayer"]
        ),
        .testTarget(
            name: "SpeakFlowTests",
            dependencies: ["Domain", "Infra", "Platform"]
        ),
    ]
)
