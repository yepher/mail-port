import AppKit
import WebKit

@MainActor
enum YouTubeSkipInput {
    static func activate(on webView: WKWebView, geometry: [String: Any]) {
        guard let window = webView.window, window.isVisible, window.attachedSheet == nil,
              let x = geometry["x"] as? Double, let y = geometry["y"] as? Double,
              let width = geometry["width"] as? Double, let height = geometry["height"] as? Double,
              [x, y, width, height].allSatisfy({ $0.isFinite }), width > 0, height > 0,
              x >= 0, y >= 0, x < width, y < height,
              webView.bounds.width > 0, webView.bounds.height > 0 else { return }
        let local = NSPoint(x: x / width * webView.bounds.width,
                            y: (webView.isFlipped ? y / height : 1 - y / height) * webView.bounds.height)
        let location = webView.convert(local, to: nil)
        guard let target = webView.hitTest(webView.convert(local, to: webView.superview)),
              target === webView || target.isDescendant(of: webView),
              let down = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [],
                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                  context: nil, eventNumber: 0, clickCount: 1, pressure: 1),
              let up = NSEvent.mouseEvent(with: .leftMouseUp, location: location, modifierFlags: [],
                  timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                  context: nil, eventNumber: 1, clickCount: 1, pressure: 0) else { return }
        // Deliver only into this WKWebView; never move the system pointer or click another app.
        target.mouseDown(with: down)
        target.mouseUp(with: up)
    }

}
