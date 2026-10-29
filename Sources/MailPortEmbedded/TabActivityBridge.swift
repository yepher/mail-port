import Foundation
import MailPortCore
import WebKit
import OSLog

@MainActor
final class TabActivityBridge: NSObject, WKScriptMessageHandler {
    private weak var tab: BrowserTab?
    private let logger = Logger(subsystem: "com.chriswilson.mailport.embedded", category: "TabActivity")
    static let world = WKContentWorld.world(name: "MailPortTabActivity")

    init(tab: BrowserTab) { self.tab = tab }

    func install(on controller: WKUserContentController) {
        guard let file = Bundle.main.url(forResource: "TabActivity", withExtension: "js"),
              let source = try? String(contentsOf: file, encoding: .utf8) else { return }
        controller.add(self, contentWorld: Self.world, name: "mailPortActivity")
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd,
            forMainFrameOnly: true, in: Self.world))
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let tab, message.webView === tab.webView,
              WebNotificationMessage.allows(scheme: message.frameInfo.securityOrigin.protocol,
                host: message.frameInfo.securityOrigin.host, port: message.frameInfo.securityOrigin.port,
                mainFrame: message.frameInfo.isMainFrame, service: tab.service),
              let values = message.body as? [String: Any],
              let activity = TabActivity(message: values, service: tab.service) else { return }
        tab.onActivity?(activity)
        // Only state totals are logged; no message subjects or event titles leave the page.
        logger.debug("Activity sample: service=\(tab.service.rawValue, privacy: .public) unread=\(activity.unreadCount ?? -1) timedEvents=\(activity.events.count)")
    }
}
