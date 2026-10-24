// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "fairdeckit",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [.library(name: "FairDecKit", targets: ["FairDecKit"])],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.20")
    ],
    targets: [
        .target(
            name: "FairDecKit",
            dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.copy("Resources/transform_const_data.bin")]
        ),
        .testTarget(
            name: "FairDecKitTests",
            dependencies: ["FairDecKit", .product(name: "ZIPFoundation", package: "ZIPFoundation")],
            resources: [.copy("Fixtures")]
        )
    ]
)
