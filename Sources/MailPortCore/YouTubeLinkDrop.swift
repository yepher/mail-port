import Foundation

public enum YouTubeLinkDrop {
    /// Accept URL and plain-text pasteboard representations, preserving playback
    /// times and playlist context while normalizing shared/mobile hostnames.
    public static func url(from text: String) -> URL? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.utf8.count <= 16384, !text.contains(where: { $0.isWhitespace }),
              var parts = URLComponents(string: text), parts.scheme?.lowercased() == "https",
              parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443,
              let host = parts.host?.lowercased() else { return nil }
        switch host {
        case "youtube.com", "www.youtube.com", "m.youtube.com":
            parts.host = "www.youtube.com"
        case "youtu.be":
            let components = parts.path.split(separator: "/")
            guard components.count == 1 else { return nil }
            let id = String(components[0])
            guard id.count == 11, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { return nil }
            parts.host = "www.youtube.com"; parts.path = "/watch"
            parts.queryItems = [URLQueryItem(name: "v", value: id)] + (parts.queryItems ?? []).filter { $0.name != "v" }
        default: return nil
        }
        parts.scheme = "https"; parts.port = nil
        return parts.url
    }
}
