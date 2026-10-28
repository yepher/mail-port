import Foundation

/// A transparent compatibility suffix for the runtime WebKit engine.
///
/// This never replaces WKWebView's generated user agent. The Safari version is
/// a conservative engine compatibility baseline, not the installed Safari.app
/// version; MailPort's own product identity remains visible in every case.
public struct WebKitBrowserIdentity: Equatable, Sendable {
    public let engineBuild: String
    private let appVersion: String

    public init(engineBuild: String, appVersion: String = "0.2.1") {
        self.engineBuild = engineBuild
        self.appVersion = appVersion
    }

    public var safariCompatibilityVersion: String? {
        let components = engineBuild.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count >= 2,
              components.allSatisfy({ component in
                  !component.isEmpty && component.utf8.allSatisfy { (48...57).contains($0) }
              }),
              ["19624", "20624", "21624"].contains(String(components[0])),
              let revision = Int(components[1]) else { return nil }

        // Verified Apple release baselines for the WebKit 624 family:
        // 26.4 (20624.1.16): https://developer.apple.com/documentation/safari-release-notes/safari-26_4-release-notes
        // 26.5 (20624.2.5):  https://developer.apple.com/documentation/safari-release-notes/safari-26_5-release-notes
        // 26.6 (20624.4.5):  https://developer.apple.com/documentation/safari-release-notes/safari-26_6-release-notes
        // Later revisions in this known family keep the last verified baseline.
        // Unknown engine families intentionally receive no inferred version.
        switch revision {
        case 1: return "26.4"
        case 2...3: return "26.5"
        case 4...: return "26.6"
        default: return nil
        }
    }

    public var applicationNameForUserAgent: String {
        let product = "MailPortPreview/\(appVersion)"
        guard let compatibility = safariCompatibilityVersion else { return product }
        return "Version/\(compatibility) Safari/605.1.15 \(product)"
    }
}
