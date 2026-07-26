// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "RegionShare",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "CVirtualDisplay"),
        .executableTarget(name: "RegionShare", dependencies: ["CVirtualDisplay"]),
        .testTarget(name: "RegionShareTests", dependencies: ["RegionShare"]),
    ]
)
