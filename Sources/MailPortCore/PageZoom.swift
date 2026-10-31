import Foundation

/// Browser-style zoom stops, remembered per service.
public enum PageZoom {
    public static let levels: [Double] = [0.5, 0.67, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2]
    public static let standard = 1.0

    /// The next stop in a direction, starting from any value.
    public static func stepped(from zoom: Double, by direction: Int) -> Double {
        if direction > 0 { return levels.first { $0 > zoom + 0.001 } ?? levels[levels.count - 1] }
        return levels.last { $0 < zoom - 0.001 } ?? levels[0]
    }

    /// Saved preferences are rechecked because they can be edited outside the app.
    public static func isValid(_ zoom: Double) -> Bool {
        zoom.isFinite && zoom >= levels[0] && zoom <= levels[levels.count - 1]
    }
}
