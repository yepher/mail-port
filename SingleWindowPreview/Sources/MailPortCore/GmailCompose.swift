import Foundation

/// Converts RFC 6068 email links into Gmail compose URLs without executing anything.
public struct GmailCompose: Equatable, Sendable {
    public let to: String
    public let cc: String
    public let bcc: String
    public let subject: String
    public let body: String

    public init(to: String = "", cc: String = "", bcc: String = "", subject: String = "", body: String = "") throws {
        let headers = [to, cc, bcc, subject]
        guard !headers.contains(where: { value in
            value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
        }) else { throw ComposeError.invalidHeader }
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.body = body
    }

    public init(mailto: URL) throws {
        guard mailto.scheme?.lowercased() == "mailto",
              let components = URLComponents(url: mailto, resolvingAgainstBaseURL: false),
              components.host == nil, components.fragment == nil,
              let recipients = components.percentEncodedPath.removingPercentEncoding else {
            throw ComposeError.invalidLink
        }
        var values: [String: [String]] = [:]
        for item in (components.percentEncodedQuery ?? "").split(separator: "&", omittingEmptySubsequences: true) {
            let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = String(pair[0]).removingPercentEncoding?.lowercased(),
                  let value = (pair.count > 1 ? String(pair[1]) : "").removingPercentEncoding else {
                throw ComposeError.invalidLink
            }
            if ["to", "cc", "bcc", "subject", "body"].contains(key) {
                values[key, default: []].append(value)
            }
        }
        let toValues = ([recipients] + (values["to"] ?? [])).filter { !$0.isEmpty }
        try self.init(
            to: toValues.joined(separator: ","),
            cc: (values["cc"] ?? []).joined(separator: ","),
            bcc: (values["bcc"] ?? []).joined(separator: ","),
            subject: values["subject"]?.first ?? "",
            body: values["body"]?.first ?? ""
        )
    }

    public var url: URL {
        var components = URLComponents(string: "https://mail.google.com/mail/u/0/")!
        var items = [URLQueryItem(name: "view", value: "cm"), URLQueryItem(name: "fs", value: "1")]
        let fields = [("to", to), ("cc", cc), ("bcc", bcc), ("su", subject), ("body", body)]
        items += fields.filter { !$0.1.isEmpty }.map { URLQueryItem(name: $0.0, value: $0.1) }
        components.queryItems = items
        // Gmail handles this as form-style query data. Preserve literal '+' characters.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url!
    }
}

public enum ComposeError: LocalizedError, Equatable {
    case invalidLink, invalidHeader
    public var errorDescription: String? {
        switch self {
        case .invalidLink: "This email link could not be opened."
        case .invalidHeader: "This email link contains unsupported characters in a recipient or subject."
        }
    }
}
