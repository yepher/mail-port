// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailPort",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MailPortCore", targets: ["MailPortCore"]),
        .executable(name: "MailPort", targets: ["MailPort"])
    ],
    targets: [
        .target(name: "MailPortCore"),
        .executableTarget(name: "MailPort", dependencies: ["MailPortCore"]),
        .testTarget(name: "MailPortCoreTests", dependencies: ["MailPortCore"])
    ],
    swiftLanguageModes: [.v5]
)
