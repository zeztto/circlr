// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "circlr",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "circlr-audition-worker", targets: ["CirclrAuditionWorker"]), .executable(name: "circlr", targets: ["CirclrApp"]), .executable(name: "circlr-studio", targets: ["CirclrStudioTool"]), .executable(name: "circlr-output-worker", targets: ["CirclrOutputWorker"]), .executable(name: "circlr-au-effect-worker", targets: ["CirclrAUEffectWorker"]), .executable(name: "circlr-au-instrument-worker", targets: ["CirclrAUInstrumentWorker"]), .executable(name: "circlr-output-device-catalog", targets: ["CirclrOutputDeviceCatalog"]), .executable(name: "circlr-trusted-mcp-helper", targets: ["CirclrTrustedMCPHelper"])],
    targets: [
        .target(name: "CirclrCore"),
        .target(name: "CirclrRealtime", publicHeadersPath: "include"),
        .target(name: "CirclrAudio", dependencies: ["CirclrCore", "CirclrRealtime"]),
        .target(name: "CirclrCodex"),
        .executableTarget(name: "CirclrApp", dependencies: ["CirclrCore", "CirclrAudio"]),
        .executableTarget(name: "CirclrStudioTool", dependencies: ["CirclrCore", "CirclrAudio"], path: "Tools/CirclrStudioTool"),
        .executableTarget(name: "CirclrAuditionWorker", dependencies: ["CirclrAudio"], path: "Tools/CirclrAuditionWorker"),
        .executableTarget(name: "CirclrOutputWorker", dependencies: ["CirclrAudio"], path: "Tools/CirclrOutputWorker"),
        .executableTarget(name: "CirclrAUEffectWorker", dependencies: ["CirclrAudio"], path: "Tools/CirclrAUEffectWorker"),
        .executableTarget(name: "CirclrAUInstrumentWorker", dependencies: ["CirclrAudio"], path: "Tools/CirclrAUInstrumentWorker"),
        .executableTarget(name: "CirclrOutputDeviceCatalog", dependencies: ["CirclrAudio"], path: "Tools/CirclrOutputDeviceCatalog"),
        .executableTarget(name: "CirclrTrustedMCPHelper", path: "Tools/CirclrTrustedMCPHelper"),
        .testTarget(name: "CirclrCoreTests", dependencies: ["CirclrCore"]),
        .testTarget(name: "CirclrAudioTests", dependencies: ["CirclrAudio"]),
        .testTarget(name: "CirclrCodexTests", dependencies: ["CirclrCodex"]),
        .testTarget(name: "CirclrAppTests", dependencies: ["CirclrApp", "CirclrCore", "CirclrTrustedMCPHelper"])
    ]
)
