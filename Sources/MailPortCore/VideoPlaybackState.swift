import Foundation

public struct VideoPlaybackState: Equatable, Sendable {
    public let hasVideo: Bool
    public let isPlaying: Bool
    public static let none = VideoPlaybackState(message: [:])
    public init(message: [String: Any]) {
        hasVideo = message["hasVideo"] as? Bool == true
        isPlaying = hasVideo && message["playing"] as? Bool == true
    }
}

public struct VideoFrame: Equatable, Sendable {
    public let x: Double, y: Double, width: Double, height: Double
    public let viewportWidth: Double, viewportHeight: Double
    public init?(message: [String: Any]) {
        guard let x = message["x"] as? Double, let y = message["y"] as? Double,
              let width = message["width"] as? Double, let height = message["height"] as? Double,
              let viewportWidth = message["viewportWidth"] as? Double, let viewportHeight = message["viewportHeight"] as? Double,
              [x,y,width,height,viewportWidth,viewportHeight].allSatisfy({ $0.isFinite }),
              width >= 32, height >= 32, viewportWidth >= 32, viewportHeight >= 32,
              width <= 32768, height <= 32768, viewportWidth <= 32768, viewportHeight <= 32768,
              x >= -1, y >= -1, x + width <= viewportWidth + 1, y + height <= viewportHeight + 1 else { return nil }
        self.x = max(0,x); self.y = max(0,y); self.width = width; self.height = height
        self.viewportWidth = viewportWidth; self.viewportHeight = viewportHeight
    }
}

public enum VideoOpacity {
    public static let minimum = 0.15
    public static func normalized(_ value: Double) -> Double {
        value.isFinite ? min(1, max(minimum, value)) : 1
    }
}
