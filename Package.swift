// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Memcheck",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Memcheck", targets: ["Memcheck"])],
    targets: [
        .executableTarget(name: "Memcheck"),
        .testTarget(name: "MemcheckTests", dependencies: ["Memcheck"]),
    ]
)
