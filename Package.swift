// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AgentMeter",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "AgentMeter", targets: ["AgentMeter"])],
    targets: [
        .executableTarget(name: "AgentMeter"),
        .testTarget(name: "AgentMeterTests", dependencies: ["AgentMeter"])
    ]
)
