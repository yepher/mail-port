import Foundation

public struct WebNotificationMessage: Equatable, Sendable {
    public enum Kind: String, Sendable { case permission, show, close }
    public let kind: Kind
    public let id: String
    public let title: String
    public let body: String
    public let tag: String
    public let silent: Bool

    public static func allows(scheme: String, host: String, port: Int, mainFrame: Bool, service: GoogleService) -> Bool {
        guard mainFrame, scheme == "https", port == 0 || port == 443 else { return false }
        return (service == .calendar && host == "calendar.google.com") || (service == .gmail && host == "mail.google.com")
    }

    public init?(_ values: [String: Any]) {
        guard let rawKind = values["kind"] as? String, let kind = Kind(rawValue: rawKind),
              let id = values["id"] as? String,
              id.range(of: #"^[A-Za-z0-9._-]{1,128}$"#, options: .regularExpression) != nil else { return nil }
        self.kind = kind
        self.id = id
        title = String((values["title"] as? String ?? "").prefix(256))
        body = String((values["body"] as? String ?? "").prefix(2048))
        tag = String((values["tag"] as? String ?? "").prefix(256))
        silent = values["silent"] as? Bool ?? false
    }
}
