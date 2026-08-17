// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MoaKit",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "MoaKit", targets: ["MoaKit"])
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", exact: "0.9.20")
    ],
    targets: [
        .target(name: "MoaKit", dependencies: ["ZIPFoundation"]),
        .testTarget(name: "MoaKitTests", dependencies: ["MoaKit"])
    ]
)
