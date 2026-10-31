import AppKit
import WebKit

/// SwiftUI sizes this container, while WebKit remains frame-based. WebKit reparents
/// the web view during element fullscreen; ancestor SwiftUI constraints otherwise
/// collapse its viewport (WebKit bug 313802).
@MainActor
final class WebViewHost: NSView {
    init(webView: WKWebView) {
        super.init(frame: webView.frame)
        webView.translatesAutoresizingMaskIntoConstraints = true
        webView.autoresizingMask = [.width, .height]
        webView.frame = bounds
        addSubview(webView)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
