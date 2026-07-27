// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OutcutShare",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CVirtualDisplay"),
        .executableTarget(name: "OutcutShare", dependencies: ["CVirtualDisplay"]),
        .testTarget(name: "OutcutShareTests", dependencies: ["OutcutShare"]),
    ]
)
