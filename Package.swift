// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailPort",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MailPort", targets: ["MailPortEmbedded"])],
    targets: [
        .target(name: "MailPortCore"),
        .executableTarget(name: "MailPortEmbedded", dependencies: ["MailPortCore"], exclude: ["Resources"]),
        .testTarget(name: "MailPortCoreTests", dependencies: ["MailPortCore"])
    ],
    swiftLanguageModes: [.v5]
)
