import AppKit
import Combine
import Foundation
import MailPortCore
import WebKit
import OSLog

/// An experimental WebKit page. Its compatibility suffix retains MailPort's
/// identity and uses a conservative baseline for a known system WebKit build.
/// Browser OAuth tokens cannot establish this page's web session.
@MainActor
final class BrowserTab: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    static var browserIdentity: WebKitBrowserIdentity {
        let build = Bundle(for: WKWebView.self).object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return WebKitBrowserIdentity(engineBuild: build)
    }
    static let todayURL = URL(string: "https://calendar.google.com/calendar/u/0/r/day")!
    let webView: WKWebView
    let account: Account
    let service: GoogleService
    @Published private(set) var title: String
    @Published private(set) var url: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var estimatedProgress = 0.0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorMessage: String?
    var onMailto: ((URL) -> Void)?
    var onActivity: ((TabActivity?) -> Void)?
    var onSignInChange: ((Bool) -> Void)?
    @Published var showingFind = false
    @Published var findText = ""
    @Published private(set) var findMissed = false
    @Published private(set) var findFocusRequest = 0
    private(set) var notificationBridge: WebNotificationBridge!
    private var activityBridge: TabActivityBridge?
    private let activityOnly: Bool
    private var authenticating = false
    private var openingAttachment = false
    private var discardedForSecurity = false
    private var loadRequested = false
    private let navigationLogger = Logger(subsystem: "com.chriswilson.mailport.embedded", category: "BrowserNavigation")

    private var observations: [NSKeyValueObservation] = []
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var downloadDestinations: [ObjectIdentifier: (temporary: URL, final: URL, replacing: Bool)] = [:]

    init(account: Account, service: GoogleService, store: WKWebsiteDataStore, activityOnly: Bool = false) {
        self.account = account
        self.service = service
        self.activityOnly = activityOnly
        title = service.title
        let configuration = WKWebViewConfiguration()
        let contentController = WKUserContentController()
        configuration.userContentController = contentController
        configuration.websiteDataStore = store
        configuration.preferences.isElementFullscreenEnabled = true
        // WebKit's base UA deliberately freezes OS/engine tokens and omits a
        // Version/Safari suffix. Keep the generated base and MailPort identity.
        configuration.applicationNameForUserAgent = Self.browserIdentity.applicationNameForUserAgent
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 900), configuration: configuration)
        super.init()
        notificationBridge = WebNotificationBridge(tab: self)
        if !activityOnly { notificationBridge.install(on: contentController) }
        if service == .gmail || activityOnly {
            let bridge = TabActivityBridge(tab: self)
            activityBridge = bridge
            bridge.install(on: contentController)
        }
        if service == .youtube, let scriptURL = Bundle.main.url(forResource: "YouTubeSkipAds", withExtension: "js"),
           let source = try? String(contentsOf: scriptURL, encoding: .utf8) {
            contentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient))
        }
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observeState()
        if activityOnly {
            load(Self.todayURL)
        } else if service == .calendar || service == .gmail {
            Task { [weak self] in
                await MailPortNotifications.shared.refresh()
                guard let self else { return }
                self.notificationBridge.updatePermission()
                // A pin or compose request may have arrived during the refresh.
                if !self.loadRequested { self.load(service.url) }
            }
        } else { load(service.url) }
    }

    func load(_ url: URL) {
        guard !discardedForSecurity else { return }
        loadRequested = true
        guard isSecureWebURL(url) else {
            if url.scheme?.lowercased() == "mailto" { onMailto?(url) }
            else { errorMessage = "MailPort can load only secure web pages." }
            return
        }
        errorMessage = nil
        authenticating = BrowserLinkRouting.isAuthenticationURL(url)
        openingAttachment = BrowserLinkRouting.isGmailAttachmentURL(url)
        webView.load(URLRequest(url: url))
    }

    func reload() {
        guard !discardedForSecurity else { return }
        errorMessage = nil
        if webView.url == nil { load(service.url) }
        else { webView.reload() }
    }

    /// Reloads a page left on sign-in once another page shows the account is signed in.
    func leaveSignIn() {
        guard let url = webView.url,
              BrowserLinkRouting.isAuthenticationURL(url) || BrowserLinkRouting.signInRequired(at: url, service: service) == true else { return }
        load(activityOnly ? Self.todayURL : service.url)
    }

    /// Nil means YouTube didn't provide captions for this video.
    func readTranscript() async throws -> VideoTranscript? {
        guard !discardedForSecurity, let url = webView.url,
              let file = Bundle.main.url(forResource: "TranscriptReader", withExtension: "js") else { return nil }
        let source = try String(contentsOf: file, encoding: .utf8)
        // The player lives in the page's world, so its result is untrusted; VideoTranscript checks it.
        let result = try await webView.callAsyncJavaScript(source, contentWorld: .page)
        return (result as? [String: Any]).flatMap { VideoTranscript(message: $0, url: url) }
    }

    var skipsYouTubeAds = false { didSet { updateYouTubeAdSkipping() } }

    func updateYouTubeAdSkipping() {
        guard service == .youtube, !discardedForSecurity else { return }
        webView.evaluateJavaScript("globalThis.__mailportSkipEnabled = \(skipsYouTubeAds ? "true" : "false");", in: nil, in: .defaultClient, completionHandler: nil)
    }

    func showFind() {
        showingFind = true
        findFocusRequest += 1
    }

    func find(backwards: Bool = false) {
        guard !findText.isEmpty else { findMissed = false; return }
        guard showingFind else { showFind(); return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        webView.find(findText, configuration: configuration) { [weak self] result in
            self?.findMissed = !result.matchFound
        }
    }

    func closeFind() {
        showingFind = false
        findText = ""
        findMissed = false
        webView.window?.makeFirstResponder(webView)
    }

    func back() { if webView.canGoBack { webView.goBack() } }
    func forward() { if webView.canGoForward { webView.goForward() } }

    func discardForSecurity() {
        discardedForSecurity = true
        onActivity = nil; onMailto = nil; onSignInChange = nil
        webView.stopLoading()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.navigationDelegate = nil; webView.uiDelegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        webView.configuration.userContentController.removeAllUserScripts()
        observations.forEach { $0.invalidate() }; observations.removeAll()
        for download in downloads.values { download.delegate = nil; download.cancel { _ in } }
        for destination in downloadDestinations.values { try? FileManager.default.removeItem(at: destination.temporary) }
        downloads.removeAll(); downloadDestinations.removeAll()
        webView.loadHTMLString("", baseURL: nil)
    }

    func printPage() {
        guard let window = webView.window else {
            errorMessage = "Select this page before printing it."
            return
        }
        let operation = webView.printOperation(with: NSPrintInfo.shared)
        // WebKit's print view starts with no size, which prints blank pages.
        operation.view?.frame = webView.bounds
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }

    private func observeState() {
        observations = [
            webView.observe(\.title, options: [.initial, .new]) { [weak self] _, _ in self?.updateStateOnMain() },
            webView.observe(\.url, options: [.initial, .new]) { [weak self] _, _ in self?.updateStateOnMain() },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] _, _ in self?.updateStateOnMain() },
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] _, _ in self?.updateStateOnMain() },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] _, _ in self?.updateStateOnMain() },
            webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] _, _ in self?.updateStateOnMain() }
        ]
    }

    private nonisolated func updateStateOnMain() {
        Task { @MainActor [weak self] in self?.updateState() }
    }

    private func updateState() {
        title = webView.title.flatMap { $0.isEmpty ? nil : $0 } ?? service.title
        url = webView.url
        isLoading = webView.isLoading
        estimatedProgress = webView.estimatedProgress
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
    }

    private func isSecureWebURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host != nil && url.user == nil && url.password == nil
    }

    private func isGoogleHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "google.com" || host.hasSuffix(".google.com")
            || host == "googleusercontent.com" || host.hasSuffix(".googleusercontent.com")
    }

    private func openMailto(_ url: URL) {
        if let onMailto { onMailto(url) }
        else { NSWorkspace.shared.open(url) }
    }

    private func openExternal(_ url: URL) {
        let opened = NSWorkspace.shared.open(url)
        navigationLogger.info("External navigation handed to default browser: \(opened)")
        if !opened { errorMessage = "macOS couldn’t open this link in your default browser." }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let destination = navigationAction.request.url else { decisionHandler(.cancel); return }
        let scheme = destination.scheme?.lowercased()
        let isTopLevel = navigationAction.targetFrame?.isMainFrame ?? true

        if scheme == "mailto" {
            decisionHandler(.cancel)
            openMailto(destination)
            return
        }
        // Client-generated attachments can use blob URLs. Only let a trusted
        // Google HTTPS page turn one into a download; never launch it externally.
        if scheme == "blob", navigationAction.shouldPerformDownload,
           navigationAction.sourceFrame.securityOrigin.protocol == "https",
           isGoogleHost(navigationAction.sourceFrame.securityOrigin.host) {
            decisionHandler(.download)
            return
        }
        if destination.absoluteString == "about:blank", !isTopLevel {
            decisionHandler(.allow)
            return
        }
        if let external = BrowserLinkRouting.externalURL(for: destination, service: service,
            topLevel: isTopLevel, download: navigationAction.shouldPerformDownload,
            authenticating: authenticating, userLink: navigationAction.navigationType == .linkActivated,
            attachment: openingAttachment) {
            decisionHandler(.cancel)
            openExternal(external)
            return
        }
        guard isSecureWebURL(destination) else {
            if isTopLevel { errorMessage = "This page tried to open an unsupported or insecure address." }
            decisionHandler(.cancel)
            return
        }
        if isTopLevel {
            if BrowserLinkRouting.isAuthenticationURL(destination) { authenticating = true }
            if BrowserLinkRouting.isGmailAttachmentURL(destination) { openingAttachment = true }
            else if destination.host == service.url.host { openingAttachment = false }
        }
        // Redirects, scripted links and new-window requests follow the same
        // routing policy; WebKit doesn't always label Gmail clicks linkActivated.
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if !navigationResponse.canShowMIMEType || disposition.hasPrefix("attachment") {
            decisionHandler(.download)
            return
        }
        // Server redirects can reach the response delegate without another
        // navigation-action callback. Don't let their final page replace Gmail.
        if let destination = navigationResponse.response.url,
           let external = BrowserLinkRouting.externalURL(for: destination, service: service,
               topLevel: navigationResponse.isForMainFrame, authenticating: authenticating,
               attachment: openingAttachment) {
            decisionHandler(.cancel)
            openExternal(external)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
        onActivity?(nil)
        updateState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateYouTubeAdSkipping()
        if webView.url?.host == service.url.host { authenticating = false }
        openingAttachment = false
        updateState()
        if let url = webView.url, let required = BrowserLinkRouting.signInRequired(at: url, service: service) {
            onSignInChange?(required)
        }
        if !activityOnly { notificationBridge.updatePermission() }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        reportNavigationError(error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        reportNavigationError(error)
    }

    private func reportNavigationError(_ error: Error) {
        let nsError = error as NSError
        // Cancellation is normal when a link becomes a download or another
        // navigation replaces the page before its request has finished.
        if !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
            errorMessage = error.localizedDescription
        }
        updateState()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        onActivity?(nil)
        errorMessage = "This page’s web process stopped. Reload the page to continue."
        updateState()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let destination = navigationAction.request.url else { return nil }
        if destination.scheme?.lowercased() == "mailto" { openMailto(destination); return nil }
        if let external = BrowserLinkRouting.externalURL(for: destination, service: service,
            topLevel: true, download: navigationAction.shouldPerformDownload,
            authenticating: authenticating, userLink: navigationAction.navigationType == .linkActivated,
            attachment: openingAttachment) {
            openExternal(external)
            return nil
        }
        guard isSecureWebURL(destination) else { return nil }
        if BrowserLinkRouting.isAuthenticationURL(destination) { authenticating = true }
        // Only the current service and its sign-in flow may reuse this tab.
        webView.load(navigationAction.request)
        return nil
    }

    private func alert(for message: String, frame: WKFrameInfo) -> NSAlert {
        let alert = NSAlert()
        alert.messageText = "\(frame.securityOrigin.host.isEmpty ? service.title : frame.securityOrigin.host) says"
        alert.informativeText = message
        alert.alertStyle = .informational
        return alert
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        guard let window = webView.window else { completionHandler(); return }
        let panel = alert(for: message, frame: frame)
        panel.addButton(withTitle: "OK")
        panel.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard let window = webView.window else { completionHandler(false); return }
        let panel = alert(for: message, frame: frame)
        panel.addButton(withTitle: "OK")
        panel.addButton(withTitle: "Cancel")
        panel.beginSheetModal(for: window) { completionHandler($0 == .alertFirstButtonReturn) }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        guard let window = webView.window else { completionHandler(nil); return }
        let panel = alert(for: prompt, frame: frame)
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 24))
        input.stringValue = defaultText ?? ""
        panel.accessoryView = input
        panel.addButton(withTitle: "OK")
        panel.addButton(withTitle: "Cancel")
        panel.window.initialFirstResponder = input
        panel.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseFiles = true
        // Directory uploads can unexpectedly include many private files. This
        // preview supports choosing explicit files, even if a site asks for a folder.
        panel.canChooseDirectories = false
        panel.canCreateDirectories = false
        panel.prompt = "Choose files"
        let finished: (NSApplication.ModalResponse) -> Void = { response in
            completionHandler(response == .OK ? panel.urls : nil)
        }
        if let window = webView.window { panel.beginSheetModal(for: window, completionHandler: finished) }
        else { completionHandler(nil) }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        retainDownload(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        retainDownload(download)
    }

    private func retainDownload(_ download: WKDownload) {
        openingAttachment = false
        downloads[ObjectIdentifier(download)] = download
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard let window = webView.window else { completionHandler(nil); return }
        let panel = NSSavePanel()
        let filename = (suggestedFilename as NSString).lastPathComponent
        panel.nameFieldStringValue = filename.isEmpty || filename == "." || filename == ".." ? "Download" : filename
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] result in
            guard let self, result == .OK, let destination = panel.url else {
                self?.downloads.removeValue(forKey: ObjectIdentifier(download))
                completionHandler(nil)
                return
            }
            // Write a new temporary file, then apply the user's Save/Replace
            // choice only once the download is complete.
            let temporary = destination.deletingLastPathComponent()
                .appendingPathComponent(".MailPort-download-\(UUID().uuidString)")
            self.downloadDestinations[ObjectIdentifier(download)] = (
                temporary, destination, FileManager.default.fileExists(atPath: destination.path)
            )
            completionHandler(temporary)
        }
    }

    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        decisionHandler(request.url.map(isSecureWebURL) == true ? .allow : .cancel)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        defer { downloads.removeValue(forKey: key); downloadDestinations.removeValue(forKey: key) }
        guard let destination = downloadDestinations[key] else { return }
        do {
            if destination.replacing && FileManager.default.fileExists(atPath: destination.final.path) {
                _ = try FileManager.default.replaceItemAt(destination.final, withItemAt: destination.temporary)
            } else {
                try FileManager.default.moveItem(at: destination.temporary, to: destination.final)
            }
        } catch {
            errorMessage = "The download finished, but its file couldn’t be saved: \(error.localizedDescription)"
            try? FileManager.default.removeItem(at: destination.temporary)
        }
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        if let destination = downloadDestinations.removeValue(forKey: key) {
            try? FileManager.default.removeItem(at: destination.temporary)
        }
        downloads.removeValue(forKey: key)
        let nsError = error as NSError
        if !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }
}
