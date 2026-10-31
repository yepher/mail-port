import Foundation
import CoreGraphics

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

public enum FloatingVideoPlacement {
    public static func isValid(_ frame: CGRect) -> Bool {
        [frame.origin.x, frame.origin.y, frame.width, frame.height].allSatisfy { $0.isFinite }
            && abs(frame.origin.x) <= 1_000_000 && abs(frame.origin.y) <= 1_000_000
            && frame.width >= 32 && frame.height >= 32 && frame.width <= 32768 && frame.height <= 32768
    }

    /// Keep the last width and top-left corner, adapting height for the current video.
    public static func restore(_ saved: CGRect, aspect: CGFloat, screens: [CGRect], fallback: CGRect) -> CGRect? {
        guard isValid(saved), aspect.isFinite, aspect > 0 else { return nil }
        let available = screens.filter { isValid($0) }
        let screen = available.max { left, right in
            let a = left.intersection(saved), b = right.intersection(saved)
            return (a.isNull ? 0 : a.width * a.height) < (b.isNull ? 0 : b.width * b.height)
        }.flatMap { $0.intersects(saved) ? $0 : nil } ?? fallback
        guard isValid(screen) else { return nil }
        let maximumWidth = min(screen.width, screen.height * aspect)
        let width = min(maximumWidth, max(min(280, maximumWidth), saved.width))
        let height = width / aspect
        guard width > 0, height > 0 else { return nil }
        return CGRect(x: min(max(saved.minX, screen.minX), screen.maxX - width),
                      y: min(max(saved.maxY - height, screen.minY), screen.maxY - height), width: width, height: height)
    }
}
