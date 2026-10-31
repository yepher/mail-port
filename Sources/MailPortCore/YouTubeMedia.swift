import Foundation

public enum YouTubeMedia {
    /// Only a single, canonical video URL reaches the helper. Drop playlists and other page input.
    public static func videoURL(_ url: URL?) -> URL? {
        guard let url, url.scheme == "https", url.host == "www.youtube.com",
              url.user == nil, url.password == nil else { return nil }
        let id: String?
        if url.path == "/watch" {
            id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "v" }?.value
        } else if url.path.hasPrefix("/shorts/") {
            id = url.path.split(separator: "/").last.map(String.init)
        } else { return nil }
        guard let id, id.count == 11, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == "-") }) else { return nil }
        return URL(string: "https://www.youtube.com/watch?v=\(id)")
    }

    /// Only list MP4 heights that can be saved with audio. No invented quality choices.
    public static func availableHeights(in metadata: [String: Any]) -> [Int] {
        let formats = metadata["formats"] as? [[String: Any]] ?? []
        let hasAudio = formats.contains { $0["ext"] as? String == "m4a" && ($0["acodec"] as? String).map { $0 != "none" } == true }
        return Set(formats.compactMap { format -> Int? in
            guard format["ext"] as? String == "mp4",
                  let video = format["vcodec"] as? String, video != "none",
                  let height = format["height"] as? NSNumber,
                  height.doubleValue.isFinite, height.doubleValue.rounded() == height.doubleValue,
                  (1...16384).contains(height.intValue),
                  let audio = format["acodec"] as? String, audio != "none" || hasAudio else { return nil }
            return height.intValue
        }).sorted(by: >)
    }

    public static func arguments(url: URL, audio: Bool, output: String, height: Int? = nil, ffmpeg: String? = nil) -> [String] {
        var arguments = ["--ignore-config", "--no-playlist", "--no-overwrites", "--no-progress", "--quiet"]
        let size = height.map { "[height=\($0)]" } ?? ""
        let video = "bestvideo[ext=mp4]\(size)+bestaudio[ext=m4a]/best[ext=mp4][vcodec!=none][acodec!=none]\(size)"
        arguments += ["--format", audio ? "bestaudio[ext=m4a]" : video]
        if !audio {
            arguments += ["--format-sort", "res", "--merge-output-format", "mp4"]
            if let ffmpeg { arguments += ["--ffmpeg-location", ffmpeg] }
        }
        return arguments + ["--output", output, "--", url.absoluteString]
    }
}
