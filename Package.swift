// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MenuPin",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MenuPin", targets: ["MenuPin"])],
    targets: [
        .target(name: "MenuPinCore"),
        .executableTarget(name: "MenuPin", dependencies: ["MenuPinCore"]),
        .executableTarget(name: "MenuPinTests", dependencies: ["MenuPinCore"], path: "Tests/MenuPinCoreTests")
    ]
)
