// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailPortSingleWindow",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MailPortPreview", targets: ["MailPortEmbedded"])],
    targets: [
        .target(name: "MailPortCore"),
        .executableTarget(name: "MailPortEmbedded", dependencies: ["MailPortCore"]),
        .testTarget(name: "MailPortCoreTests", dependencies: ["MailPortCore"])
    ],
    swiftLanguageModes: [.v5]
)
