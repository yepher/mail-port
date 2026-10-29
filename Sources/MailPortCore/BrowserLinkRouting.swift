import Foundation

public enum BrowserLinkRouting {
    public static func isAuthenticationURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "accounts.google.com"
    }

    public static func isGmailAttachmentURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "mail.google.com",
              url.path.hasPrefix("/mail/"), let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return query.contains { $0.name == "view" && $0.value == "att" }
    }

    public static func externalURL(for url: URL, service: GoogleService, topLevel: Bool,
        download: Bool = false, authenticating: Bool = false, userLink: Bool = false,
        attachment: Bool = false) -> URL? {
        guard topLevel || userLink, !download, let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host?.lowercased(),
              url.user == nil, url.password == nil else { return nil }
        // A service's own navigation stays inside its tab. Other Google products
        // and Google redirect wrappers are external sites too.
        if scheme == "https" {
            if host == service.url.host?.lowercased() || isAuthenticationURL(url) { return nil }
            // Keep SAML redirects/form submissions inside the sign-in flow, but
            // don't treat an explicit link clicked there as an authentication redirect.
            if authenticating && !userLink { return nil }
            if attachment && !userLink && (host == "googleusercontent.com" || host.hasSuffix(".googleusercontent.com")) { return nil }
        }
        return browserDestination(url)
    }

    private static func browserDestination(_ url: URL) -> URL {
        guard ["google.com", "www.google.com"].contains(url.host?.lowercased() ?? ""),
              url.path == "/url", let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return url }
        for key in ["url", "q"] {
            if let value = query.first(where: { $0.name == key })?.value, let target = URL(string: value),
               ["http", "https"].contains(target.scheme?.lowercased() ?? ""), target.host != nil,
               target.user == nil, target.password == nil { return target }
        }
        return url
    }
}
