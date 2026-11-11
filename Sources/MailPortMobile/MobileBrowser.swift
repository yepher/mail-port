import Combine
import MailPortCore
import OSLog
import UIKit
import WebKit

/// One account's page for one service. Pages for the same account share a data
/// store, so they share a Google sign-in; other accounts never see it.
@MainActor
final class MobileBrowser: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    static var browserIdentity: WebKitBrowserIdentity {
        let build = Bundle(for: WKWebView.self).object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
        return WebKitBrowserIdentity(engineBuild: build, appVersion: version, mobile: true)
    }

    let tab: WorkspaceTab
    let webView: WKWebView
    var service: GoogleService { tab.service }
    @Published private(set) var title: String
    @Published private(set) var url: URL?
    @Published private(set) var isLoading = false
    @Published private(set) var progress = 0.0
    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false
    @Published private(set) var errorMessage: String?
    /// Opens a Google link in this account's page for another service. False means no page took it.
    var onOpenInService: ((GoogleService, URL) -> Bool)?

    struct SavedDownload: Identifiable {
        let id = UUID()
        let url: URL
    }
    @Published private(set) var savedDownloads: [SavedDownload] = []
    @Published private(set) var activeDownloadCount = 0
    @Published var downloadError: String?
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var downloadFiles: [ObjectIdentifier: URL] = [:]
    private var discarded = false
    var skipsYouTubeAds = false {
        didSet { if skipsYouTubeAds != oldValue { updateYouTubeAdSkipping() } }
    }

    /// Installed in an isolated world and only on YouTube's top-level page.
    static func adSkipSource(enabled: Bool) -> String? {
        guard let url = Bundle.main.url(forResource: "YouTubeSkipAds", withExtension: "js"),
              let template = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return template.replacingOccurrences(of: "/*__MAILPORT_SKIP_ENABLED__*/false", with: enabled ? "true" : "false")
    }

    private func updateYouTubeAdSkipping() {
        guard !discarded, service == .youtube, let source = Self.adSkipSource(enabled: skipsYouTubeAds) else { return }
        let controller = webView.configuration.userContentController
        let others = controller.userScripts.filter { !$0.source.hasPrefix("// MailPort mobile YouTube ad skipping") }
        controller.removeAllUserScripts()
        others.forEach { controller.addUserScript($0) }
        if skipsYouTubeAds {
            controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd,
                forMainFrameOnly: true, in: .defaultClient))
        }
        // Changing Settings also updates an already-open video without reloading it.
        webView.evaluateJavaScript(source, in: nil, in: .defaultClient, completionHandler: nil)
    }

    var keepsBackgroundPage: Bool {
        service == .meet || service == .colab || service == .youtube || activeDownloadCount > 0 || !savedDownloads.isEmpty
            || webView.cameraCaptureState != .none || webView.microphoneCaptureState != .none
    }

    private var authenticating = false
    private var observations: [NSKeyValueObservation] = []
    private var popupCatchers: Set<PopupCatcher> = []
    private let logger = Logger(subsystem: "com.chriswilson.mailport.mobile", category: "BrowserNavigation")

    init(tab: WorkspaceTab, store: WKWebsiteDataStore, loadsInitialPage: Bool = true) {
        self.tab = tab
        title = tab.service.title
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        configuration.allowsInlineMediaPlayback = true
        configuration.applicationNameForUserAgent = Self.browserIdentity.applicationNameForUserAgent
        #if os(iOS)
        configuration.allowsPictureInPictureMediaPlayback = true
        #endif
        configuration.preferences.isElementFullscreenEnabled = true
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        #if DEBUG
        if #available(iOS 16.4, visionOS 1.0, *) { webView.isInspectable = true }
        #endif
        observeState()
        if loadsInitialPage { load(tab.service.url) }
    }

    func load(_ url: URL) {
        guard !discarded, url.scheme?.lowercased() == "https", url.host != nil,
              url.user == nil, url.password == nil else { return }
        errorMessage = nil
        if BrowserLinkRouting.isAuthenticationURL(url) { authenticating = true }
        webView.load(URLRequest(url: url))
    }

    func reload() {
        errorMessage = nil
        if webView.url == nil { load(service.url) } else { webView.reload() }
    }

    func goHome() { load(service.url) }

    private func observeState() {
        observations = [
            webView.observe(\.title) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.title = view.title.flatMap { $0.isEmpty ? nil : $0 } ?? self?.service.title ?? "" }
            },
            webView.observe(\.url) { [weak self] view, _ in MainActor.assumeIsolated { self?.url = view.url } },
            webView.observe(\.isLoading) { [weak self] view, _ in MainActor.assumeIsolated { self?.isLoading = view.isLoading } },
            webView.observe(\.estimatedProgress) { [weak self] view, _ in MainActor.assumeIsolated { self?.progress = view.estimatedProgress } },
            webView.observe(\.canGoBack) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoBack = view.canGoBack } },
            webView.observe(\.canGoForward) { [weak self] view, _ in MainActor.assumeIsolated { self?.canGoForward = view.canGoForward } }
        ]
    }

    /// Sends a link to this account's page for its service, or to the system browser.
    /// Returns false when the link should stay in this page.
    private func route(_ url: URL, topLevel: Bool, userLink: Bool) -> Bool {
        guard !discarded else { return true }
        guard let scheme = url.scheme?.lowercased() else { return false }
        if ["about", "blob", "data", "javascript"].contains(scheme) { return false }
        if !["http", "https"].contains(scheme) {
            guard topLevel || userLink else { return true }
            // mailto:, tel:, and app links belong to the system.
            UIApplication.shared.open(url)
            return true
        }
        if topLevel, BrowserLinkRouting.isAuthenticationURL(url) { authenticating = true }
        guard let external = BrowserLinkRouting.externalURL(for: url, service: service, topLevel: topLevel,
            authenticating: authenticating, userLink: userLink) else { return false }
        if let target = BrowserLinkRouting.service(for: external), target != service,
           onOpenInService?(target, external) == true { return true }
        logger.debug("Opening outside link in the system browser: \(external.host ?? "", privacy: .public)")
        UIApplication.shared.open(external)
        return true
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard !discarded else { return .cancel }
        guard let url = navigationAction.request.url else { return .allow }
        if navigationAction.shouldPerformDownload { return .download }
        let topLevel = navigationAction.targetFrame?.isMainFrame ?? true
        return route(url, topLevel: topLevel, userLink: navigationAction.navigationType == .linkActivated) ? .cancel : .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard !discarded else { return .cancel }
        return navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateYouTubeAdSkipping()
        errorMessage = nil
        // Back on the service's own page means sign-in is over.
        if let host = webView.url?.host?.lowercased(), host == service.url.host?.lowercased() { authenticating = false }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { show(error) }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { show(error) }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // iOS reclaims page memory under pressure. Reload rather than leave a blank page.
        logger.notice("Web content process ended for \(self.service.rawValue, privacy: .public); reloading")
        guard !discarded else { return }
        errorMessage = "This page stopped. Reload to continue."
    }

    private func show(_ error: Error) {
        let error = error as NSError
        guard !PageRecovery.isExpected(domain: error.domain, code: error.code) else { return }
        errorMessage = error.localizedDescription
    }

    // MARK: WKUIDelegate

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard !discarded else { return nil }
        if navigationAction.shouldPerformDownload {
            webView.startDownload(using: navigationAction.request) { [weak self] download in self?.retainDownload(download) }
            return nil
        }
        if let url = navigationAction.request.url, url.scheme?.lowercased() != "about" {
            if !route(url, topLevel: true, userLink: true) { load(url) }
            return nil
        }
        // A blank window that the page fills in later. Catch its first real address.
        let catcher = PopupCatcher(configuration: configuration) { [weak self] catcher, url in
            guard let self else { return }
            self.popupCatchers.remove(catcher)
            if !self.route(url, topLevel: true, userLink: true) { self.load(url) }
        }
        popupCatchers.insert(catcher)
        return catcher.webView
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        await withCheckedContinuation { continuation in
            present(message: message, actions: [("OK", .default, { continuation.resume() })]) ?? continuation.resume()
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await withCheckedContinuation { continuation in
            present(message: message, actions: [
                ("Cancel", .cancel, { continuation.resume(returning: false) }),
                ("OK", .default, { continuation.resume(returning: true) })
            ]) ?? continuation.resume(returning: false)
        }
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        let allowedOrigin = !discarded && origin.protocol == "https" && [0, 443].contains(origin.port)
            && origin.host.lowercased() == service.url.host?.lowercased() && frame.isMainFrame
        decisionHandler(allowedOrigin ? .prompt : .deny)
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        guard var presenter = webView.window?.rootViewController else { return nil }
        while let next = presenter.presentedViewController { presenter = next }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in continuation.resume(returning: nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in continuation.resume(returning: alert?.textFields?.first?.text) })
            presenter.present(alert, animated: true)
        }
    }

    // MARK: Downloads

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) { retainDownload(download) }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) { retainDownload(download) }

    private func retainDownload(_ download: WKDownload) {
        guard !discarded else { download.cancel { _ in }; return }
        downloads[ObjectIdentifier(download)] = download
        activeDownloadCount = downloads.count
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                  suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
        guard !discarded else { completionHandler(nil); return }
        do {
            let destination = try makeDownloadDestination(suggestedFilename: suggestedFilename)
            downloadFiles[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        } catch {
            downloadError = error.localizedDescription
            downloads.removeValue(forKey: ObjectIdentifier(download))
            activeDownloadCount = downloads.count
            completionHandler(nil)
        }
    }

    func makeDownloadDestination(suggestedFilename: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("MailPort-download-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let filename = (suggestedFilename as NSString).lastPathComponent
        let safeName = filename.isEmpty || filename == "." || filename == ".." ? "Download" : String(filename.prefix(80))
        return folder.appendingPathComponent(safeName)
    }

    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse,
                  newRequest request: URLRequest, decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) {
        decisionHandler(request.url?.scheme?.lowercased() == "https" ? .allow : .cancel)
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        if !discarded, let url = downloadFiles.removeValue(forKey: key) { savedDownloads.append(SavedDownload(url: url)) }
        downloads.removeValue(forKey: key)
        activeDownloadCount = downloads.count
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        if let url = downloadFiles.removeValue(forKey: key) { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        downloads.removeValue(forKey: key)
        activeDownloadCount = downloads.count
        if !discarded, (error as NSError).code != NSURLErrorCancelled { downloadError = error.localizedDescription }
    }

    func cancelDownloads() {
        for download in downloads.values { download.delegate = nil; download.cancel { _ in } }
        for url in downloadFiles.values { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        downloads.removeAll(); downloadFiles.removeAll(); activeDownloadCount = 0
    }

    func removeDownload(_ file: SavedDownload) {
        try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent())
        savedDownloads.removeAll { $0.id == file.id }
    }

    func discard() {
        guard !discarded else { return }
        if service == .youtube { skipsYouTubeAds = false }
        discarded = true
        onOpenInService = nil
        observations.forEach { $0.invalidate() }; observations.removeAll()
        webView.stopLoading()
        webView.pauseAllMediaPlayback(completionHandler: nil)
        webView.setCameraCaptureState(.none, completionHandler: nil)
        webView.setMicrophoneCaptureState(.none, completionHandler: nil)
        popupCatchers.forEach { $0.webView.stopLoading(); $0.webView.navigationDelegate = nil }
        popupCatchers.removeAll()
        cancelDownloads()
        for file in savedDownloads { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        savedDownloads.removeAll()
        webView.navigationDelegate = nil; webView.uiDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    /// Nil when there's no window to show the alert in.
    private func present(message: String, actions: [(String, UIAlertAction.Style, () -> Void)]) -> Void? {
        guard var presenter = webView.window?.rootViewController else { return nil }
        while let next = presenter.presentedViewController { presenter = next }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        for (title, style, handler) in actions { alert.addAction(UIAlertAction(title: title, style: style) { _ in handler() }) }
        presenter.present(alert, animated: true)
        return ()
    }
}

/// An offscreen page for `window.open()` with no address yet. It never shows;
/// its first real navigation is handed back and then it's dropped.
@MainActor
private final class PopupCatcher: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private let onURL: (PopupCatcher, URL) -> Void

    init(configuration: WKWebViewConfiguration, onURL: @escaping (PopupCatcher, URL) -> Void) {
        webView = WKWebView(frame: .zero, configuration: configuration)
        self.onURL = onURL
        super.init()
        webView.navigationDelegate = self
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url, url.scheme?.lowercased() != "about" else { return .allow }
        onURL(self, url)
        return .cancel
    }
}
