import AppKit
import WebKit
import XCTest
@testable import MailPortEmbedded

final class YouTubeSkipTests: XCTestCase {
    @MainActor func testNativeChecksClickALateAppearingButtonAcrossContentWorlds() async throws {
        let resource = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/MailPortEmbedded/Resources/YouTubeSkipAds.js")
        let source = try String(contentsOf: resource, encoding: .utf8)
            .replacingOccurrences(of: "/*__MAILPORT_SKIP_ENABLED__*/false", with: "true")
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
        webView.loadHTMLString("<html><body><div id='movie_player'></div></body></html>", baseURL: URL(string: "https://www.youtube.com/"))
        for _ in 0..<200 where webView.isLoading { try await Task.sleep(for: .milliseconds(10)) }
        _ = try await webView.callAsyncJavaScript(source, contentWorld: .defaultClient)
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 800, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
        defer { window.orderOut(nil); window.contentView = nil }
        let timer = Timer(timeInterval: 0.05, repeats: true) { _ in
            webView.evaluateJavaScript("globalThis.__mailportSkipNow?.()", in: nil, in: .defaultClient) { result in
                if case .success(let value) = result, let geometry = value as? [String: Any] {
                    YouTubeSkipInput.activate(on: webView, geometry: geometry)
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        defer { timer.invalidate() }
        // The page installs its own handler after the isolated script has loaded.
        _ = try await webView.callAsyncJavaScript("const b = document.createElement('button'); b.className = 'ytp-skip-ad-button'; b.textContent = 'Skip'; b.onclick = event => document.body.setAttribute('data-skipped', event.isTrusted ? 'yes' : 'untrusted'); document.getElementById('movie_player').append(b);", contentWorld: .page)
        var skipped = false
        for _ in 0..<100 {
            skipped = (try await webView.callAsyncJavaScript("return document.body.getAttribute('data-skipped');", contentWorld: .page) as? String) == "yes"
            if skipped { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(skipped, "A native timer must deliver a trusted click to the late-appearing Skip control")
    }
}
