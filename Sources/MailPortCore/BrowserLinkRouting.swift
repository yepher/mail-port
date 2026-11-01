import Foundation

public enum BrowserLinkRouting {
    public static func isAuthenticationURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.lowercased() == "accounts.google.com"
    }

    /// Whether a Mail or Calendar page shows the account is signed out. Signed-out
    /// pages can land on Google's sign-in or its product pages. Nil means this page can't tell.
    public static func signInRequired(at url: URL, service: GoogleService) -> Bool? {
        guard service == .gmail || service == .calendar, url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        if isAuthenticationURL(url) || host == "workspace.google.com" { return true }
        if host == "www.google.com", path.contains("/gmail/about") || path.contains("/calendar/about") { return true }
        guard host == service.url.host?.lowercased() else { return nil }
        return path.hasPrefix("/calendar/about")
    }

    public static func isGmailAttachmentURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.host?.lowercased() == "mail.google.com",
              url.path.hasPrefix("/mail/"), let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return false }
        return query.contains { $0.name == "view" && $0.value == "att" }
    }

    /// The service that shows this address, so a Google link can stay in its account.
    /// Nil means no service does, and the link belongs in a browser.
    public static func service(for url: URL) -> GoogleService? {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased() else { return nil }
        if host == "docs.google.com" {
            let path = url.path.lowercased()
            if path.hasPrefix("/document") { return .docs }
            if path.hasPrefix("/spreadsheets") { return .sheets }
            if path.hasPrefix("/presentation") { return .slides }
            return nil
        }
        if host == "notebooklm.google.com" { return .notebooklm }
        return GoogleService.allCases.first { $0.url.host?.lowercased() == host }
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
            // YouTube spreads Studio, sign-in, and consent across its own subdomains.
            if service == .youtube, host == "youtube.com" || host.hasSuffix(".youtube.com") { return nil }
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
