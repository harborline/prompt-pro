// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PromptProducer",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "PromptProducerCore", targets: ["PromptProducerCore"]),
        .executable(name: "PromptProducer", targets: ["PromptProducer"])
    ],
    dependencies: [
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.4.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", from: "9.14.0")
    ],
    targets: [
        .target(
            name: "PromptProducerCore",
            path: "Sources/PromptProducerCore",
            resources: [
                .copy("Resources/Fuse")
            ]
        ),
        .executableTarget(
            name: "PromptProducer",
            dependencies: [
                "PromptProducerCore",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "Sentry", package: "sentry-cocoa")
            ],
            path: "Sources/PromptProducer",
            resources: [
                .copy("Resources/BlockNoteEditor")
            ]
        ),
        .testTarget(
            name: "PromptProducerCoreTests",
            dependencies: ["PromptProducerCore"],
            path: "Tests/PromptProducerCoreTests"
        )
    ]
)
