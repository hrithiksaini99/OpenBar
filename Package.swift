// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "OpenBar", targets: ["OpenBar"])],
    targets: [
        .target(name: "MenuBarBridge", publicHeadersPath: "include", cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("Foundation")]),
        .executableTarget(name: "OpenBar", dependencies: ["MenuBarBridge"]),
        .testTarget(name: "OpenBarTests", dependencies: ["OpenBar"])
    ]
)
