import Foundation

public struct VideoTranscript: Equatable, Sendable {
    public struct Segment: Equatable, Sendable {
        public let time: String
        public let text: String
    }

    public static let maximumSegments = 100_000
    public let title: String
    public let url: URL
    public let segments: [Segment]

    /// Page data is treated as untrusted, so only strings of a sensible size are kept.
    public init?(message: [String: Any], url: URL) {
        guard let items = message["segments"] as? [[String: Any]], !items.isEmpty, items.count <= Self.maximumSegments else { return nil }
        segments = items.compactMap { item in
            guard let text = item["text"] as? String else { return nil }
            let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4096))
            guard !trimmed.isEmpty else { return nil }
            return Segment(time: String((item["time"] as? String ?? "").prefix(16)), text: trimmed)
        }
        guard !segments.isEmpty else { return nil }
        title = String((message["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(256))
        self.url = url
    }

    public var text: String {
        let body = segments.map { $0.time.isEmpty ? $0.text : "[\($0.time)] \($0.text)" }.joined(separator: "\n")
        return "\(title.isEmpty ? "YouTube video" : title)\n\(url.absoluteString)\n\n\(body)\n"
    }

    /// Titles come from the page, so path separators and leading dots can't reach the file name.
    public var suggestedFilename: String {
        let cleaned = title.map { "/:\\".contains($0) || $0.isNewline || $0.asciiValue == 0 ? "-" : $0 }
        var name = String(String(cleaned).trimmingCharacters(in: .whitespaces).prefix(120))
        while name.hasPrefix(".") { name.removeFirst() }
        return (name.isEmpty ? "YouTube video" : name) + " transcript.txt"
    }

    public static func isVideoPage(_ url: URL?, service: GoogleService) -> Bool {
        guard service == .youtube, let url, url.scheme?.lowercased() == "https", url.host?.lowercased() == "www.youtube.com",
              url.path == "/watch" else { return false }
        return URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.contains { $0.name == "v" && $0.value?.isEmpty == false } == true
    }
}
