import Foundation
import MailPortCore
import WebKit
import OSLog

@MainActor
final class WebNotificationBridge: NSObject, WKScriptMessageHandler {
    private weak var tab: BrowserTab?
    private var identifiers: [String: String] = [:]
    private let notifications = MailPortNotifications.shared
    private weak var controller: WKUserContentController?
    private var source: String?
    private var installedPermission: String?
    private var installedScript: WKUserScript?
    private let logger = Logger(subsystem: "com.chriswilson.mailport.embedded", category: "NotificationBridge")

    init(tab: BrowserTab) { self.tab = tab }

    func install(on controller: WKUserContentController) {
        guard let file = Bundle.main.url(forResource: "NotificationBridge", withExtension: "js"),
              let source = try? String(contentsOf: file, encoding: .utf8) else {
            notifications.reportError("The notification bridge is missing. Rebuild MailPort with scripts/build.sh.")
            return
        }
        self.controller = controller
        self.source = source
        controller.add(self, name: "mailPortNotifications")
        refreshUserScript()
    }

    private func refreshUserScript() {
        guard installedPermission != notifications.permission, let controller, let source else { return }
        // Preserve the independent activity observer when refreshing notification permission.
        let others = controller.userScripts.filter { $0 !== installedScript }
        controller.removeAllUserScripts()
        let script = WKUserScript(source: source.replacingOccurrences(of: "__MAILPORT_PERMISSION__", with: notifications.permission),
            injectionTime: .atDocumentStart, forMainFrameOnly: true)
        controller.addUserScript(script)
        others.forEach(controller.addUserScript)
        installedScript = script
        installedPermission = notifications.permission
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        logger.info("Notification message: host=\(message.frameInfo.securityOrigin.host, privacy: .public) scheme=\(message.frameInfo.securityOrigin.protocol, privacy: .public) port=\(message.frameInfo.securityOrigin.port) main=\(message.frameInfo.isMainFrame)")
        guard let tab, message.webView === tab.webView,
              WebNotificationMessage.allows(scheme: message.frameInfo.securityOrigin.protocol,
                host: message.frameInfo.securityOrigin.host, port: message.frameInfo.securityOrigin.port,
                mainFrame: message.frameInfo.isMainFrame, service: tab.service),
              let values = message.body as? [String: Any], let payload = WebNotificationMessage(values) else { return }
        switch payload.kind {
        case .permission:
            Task { [weak self] in
                guard let self else { return }
                await self.notifications.refresh()
                self.updatePermission(requestID: payload.id)
            }
        case .show:
            Task { [weak self, weak tab] in
                guard let self, let tab else { return }
                if let identifier = await self.notifications.deliver(payload, account: tab.account, service: tab.service) {
                    if self.identifiers.count > 1024 { self.identifiers.removeAll() }
                    self.identifiers[payload.id] = identifier
                    self.call("shown", id: payload.id)
                } else { self.call("failed", id: payload.id) }
            }
        case .close:
            if let identifier = identifiers.removeValue(forKey: payload.id) { notifications.close(identifier) }
        }
    }

    func updatePermission(requestID: String = "") {
        refreshUserScript()
        guard let webView = tab?.webView else { return }
        webView.callAsyncJavaScript("window.__mailportNotifications?.permissionChanged(permission, requestID)",
            arguments: ["permission": notifications.permission, "requestID": requestID], in: nil, in: .page, completionHandler: { _ in })
        webView.callAsyncJavaScript("return [Boolean(window.__mailportNotifications), window.Notification?.permission ?? 'unavailable', document.visibilityState].join(' ')",
            arguments: [:], in: nil, in: .page, completionHandler: { [logger] result in
                if case .success(let value) = result, let value = value as? String { logger.info("Notification bridge state: \(value, privacy: .public)") }
            })
    }

    func clicked(_ id: String) { identifiers.removeValue(forKey: id); call("clicked", id: id) }

    private func call(_ action: String, id: String) {
        guard ["shown", "failed", "clicked"].contains(action), let webView = tab?.webView else { return }
        webView.callAsyncJavaScript("window.__mailportNotifications?.[action]?.(id)",
            arguments: ["action": action, "id": id], in: nil, in: .page, completionHandler: { _ in })
    }
}
