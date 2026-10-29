// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MailPort",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MailPort", targets: ["MailPortEmbedded"])],
    targets: [
        .target(name: "MailPortCore"),
        .target(name: "MailPortSecurity"),
        .executableTarget(name: "MailPortEmbedded", dependencies: ["MailPortCore", "MailPortSecurity"], exclude: ["Resources"]),
        .testTarget(name: "MailPortCoreTests", dependencies: ["MailPortCore"]),
        .testTarget(name: "MailPortSecurityTests", dependencies: ["MailPortSecurity"]),
        .testTarget(name: "MailPortEmbeddedTests", dependencies: ["MailPortEmbedded", "MailPortSecurity", "MailPortCore"])
    ],
    swiftLanguageModes: [.v5]
)
