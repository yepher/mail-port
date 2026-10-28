import AppKit
import Combine
import Foundation
import MailPortCore
import WebKit

/// An experimental WebKit page. Its compatibility suffix retains MailPort's
/// identity and uses a conservative baseline for a known system WebKit build.
/// Browser OAuth tokens cannot establish this page's web session.
@MainActor
final class BrowserTab: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    static var browserIdentity: WebKitBrowserIdentity {
        let build = Bundle(for: WKWebView.self).object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return WebKitBrowserIdentity(engineBuild: build)
    }
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

    private var observations: [NSKeyValueObservation] = []
    private var downloads: [ObjectIdentifier: WKDownload] = [:]
    private var downloadDestinations: [ObjectIdentifier: (temporary: URL, final: URL, replacing: Bool)] = [:]

    init(account: Account, service: GoogleService, store: WKWebsiteDataStore) {
        self.account = account
        self.service = service
        title = service.title
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = store
        // WebKit's base UA deliberately freezes OS/engine tokens and omits a
        // Version/Safari suffix. Keep the generated base and MailPort identity.
        configuration.applicationNameForUserAgent = Self.browserIdentity.applicationNameForUserAgent
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        observeState()
        load(service.url)
    }

    func load(_ url: URL) {
        guard isSecureWebURL(url) else {
            if url.scheme?.lowercased() == "mailto" { onMailto?(url) }
            else { errorMessage = "MailPort can load only secure web pages." }
            return
        }
        errorMessage = nil
        webView.load(URLRequest(url: url))
    }

    func reload() {
        errorMessage = nil
        if webView.url == nil { load(service.url) }
        else { webView.reload() }
    }

    func back() { if webView.canGoBack { webView.goBack() } }
    func forward() { if webView.canGoForward { webView.goForward() } }

    func printPage() {
        guard let window = webView.window else {
            errorMessage = "Select this page before printing it."
            return
        }
        let operation = webView.printOperation(with: NSPrintInfo.shared)
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
        guard isSecureWebURL(destination) else {
            if isTopLevel { errorMessage = "This page tried to open an unsupported or insecure address." }
            decisionHandler(.cancel)
            return
        }
        if navigationAction.navigationType == .linkActivated, !isGoogleHost(destination.host) {
            decisionHandler(.cancel)
            NSWorkspace.shared.open(destination)
            return
        }
        // HTTPS redirects and form submissions are allowed for Workspace SSO.
        // They retain the visible URL and normal WebKit certificate validation.
        decisionHandler(navigationAction.shouldPerformDownload ? .download : .allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?.lowercased() ?? ""
        if !navigationResponse.canShowMIMEType || disposition.hasPrefix("attachment") {
            decisionHandler(.download)
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        errorMessage = nil
        updateState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { updateState() }

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
        errorMessage = "This page’s web process stopped. Reload the page to continue."
        updateState()
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let destination = navigationAction.request.url else { return nil }
        if destination.scheme?.lowercased() == "mailto" { openMailto(destination); return nil }
        guard isSecureWebURL(destination) else { return nil }
        if navigationAction.navigationType == .linkActivated, !isGoogleHost(destination.host) {
            NSWorkspace.shared.open(destination)
        } else {
            // Keep requested popups in this tab rather than opening more windows.
            webView.load(navigationAction.request)
        }
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
