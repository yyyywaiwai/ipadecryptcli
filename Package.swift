// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ipadecryptcli",
    platforms: [.macOS(.v12)],
    products: [.executable(name: "ipadecrypt", targets: ["ipadecrypt"])],
    dependencies: [.package(path: "Vendor/FairDecKit")],
    targets: [
        .executableTarget(name: "ipadecrypt", dependencies: [.product(name: "FairDecKit", package: "FairDecKit")]),
        .testTarget(name: "ipadecryptTests", dependencies: ["ipadecrypt"], resources: [.copy("Fixtures")])
    ]
)
