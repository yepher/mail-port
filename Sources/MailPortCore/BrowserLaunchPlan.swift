import Foundation

public struct BrowserLaunchPlan: Equatable, Sendable {
    public let profileDirectory: URL
    public let url: URL
    public let arguments: [String]

    public init(account: Account, url: URL, profilesDirectory: URL) throws {
        let allowedHosts: Set<String> = [
            "mail.google.com", "calendar.google.com", "drive.google.com",
            "contacts.google.com", "chat.google.com", "meet.google.com", "accounts.google.com"
        ]
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(), allowedHosts.contains(host),
              url.user == nil, url.password == nil, url.port == nil,
              profilesDirectory.isFileURL else {
            throw BrowserLaunchError.unsupportedURL
        }
        self.profileDirectory = profilesDirectory.appendingPathComponent(account.id.uuidString, isDirectory: true)
        self.url = url
        self.arguments = [
            "--user-data-dir=\(profileDirectory.path)",
            "--no-first-run",
            "--no-default-browser-check",
            "--app=\(url.absoluteString)"
        ]
    }
}

public enum BrowserLaunchError: LocalizedError, Equatable {
    case unsupportedURL
    public var errorDescription: String? { "MailPort can open only supported Google services using a secure connection." }
}
