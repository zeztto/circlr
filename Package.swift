// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "circlr",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "circlr", targets: ["CirclrApp"]), .executable(name: "circlr-studio", targets: ["CirclrStudioTool"])],
    targets: [
        .target(name: "CirclrCore"),
        .target(name: "CirclrRealtime", publicHeadersPath: "include"),
        .target(name: "CirclrAudio", dependencies: ["CirclrCore", "CirclrRealtime"]),
        .executableTarget(name: "CirclrApp", dependencies: ["CirclrCore", "CirclrAudio"]),
        .executableTarget(name: "CirclrStudioTool", dependencies: ["CirclrCore", "CirclrAudio"], path: "Tools/CirclrStudioTool"),
        .testTarget(name: "CirclrCoreTests", dependencies: ["CirclrCore"]),
        .testTarget(name: "CirclrAudioTests", dependencies: ["CirclrAudio"])
    ]
)
