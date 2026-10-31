import AppKit
import Combine
import UniformTypeIdentifiers
import WebKit
import MailPortCore
import MailPortSecurity

enum WorkspaceLayout: String { case sidebar, tabBar }

@MainActor
final class EmbeddedWorkspace: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var tabs: [WorkspaceTab] = []
    @Published private(set) var selection: WorkspaceTab?
    @Published private(set) var currentBrowser: BrowserTab?
    @Published var showingAccountEditor = false
    @Published var editingAccount: Account?
    @Published var showingHelp = false
    @Published var showingNotifications = false
    @Published var showingSecuritySettings = false
    @Published var showingQuickSwitch = false
    @Published var showingPinEditor = false
    @Published var accountPendingRemoval: Account?
    @Published var errorMessage: String?
    @Published var pendingCompose: URL?
    @Published private(set) var storageAvailable = true
    @Published private(set) var recentlyClosed: [WorkspaceTab] = []
    @Published private(set) var tabActivity: [WorkspaceTab: TabActivity] = [:] { didSet { updateDockBadge() } }
    @Published private(set) var dockBadgeExcluded: Set<UUID> = []
    @Published private(set) var notificationSettings: [UUID: AccountNotificationSettings] = [:]
    @Published private(set) var pins: [WorkspacePin] = []
    @Published private(set) var collapsedAccounts: Set<UUID> = []
    @Published private(set) var showsShortcutHints = true
    @Published private(set) var savingMedia = false
    @Published var mediaStatus: String?
    @Published var showingVideoOptions = false
    private(set) var videoOptionsURL: URL?
    private var pendingVideoSelection = false
    private var pendingVideoHeight: Int?
    private var mediaDownload: YouTubeDownload?
    private var videoOptionsReader: YouTubeDownload?
    @Published private(set) var skipsYouTubeAds = false
    @Published private(set) var allowsYouTubeDownloads = false
    @Published private(set) var savingTranscript = false
    @Published private(set) var accountsNeedingSignIn: Set<UUID> = []
    @Published private(set) var serviceZoom: [GoogleService: Double] = [:]
    @Published private(set) var defaultMailAccountID: UUID?
    @Published var layout: WorkspaceLayout = .sidebar {
        didSet { preferences.set(layout.rawValue, forKey: "workspaceLayout") }
    }
    weak var mainWindow: NSWindow?
    var reopenWindow: (() -> Void)?
    var clearVideoDockMenu: (() -> Void)?

    let security: AppSecurity
    let preferenceDomain: String
    private let testingMode: Bool
    let directory: URL
    private let accountStore: AccountStore
    private var stores: [UUID: WKWebsiteDataStore] = [:]
    private var browsers: [WorkspaceTab: BrowserTab] = [:]
    private var calendarMonitors: [UUID: BrowserTab] = [:]
    private var activityDay = Calendar.current.startOfDay(for: Date())
    private var activityTimer: Timer?
    private var browserChanges: AnyCancellable?
    private var securityChanges: AnyCancellable?
    private var preferences: UserDefaults
    private var lastAccountID: UUID?
    private var incomingAfterUnlock: URL?
    @Published private(set) var poppedOutVideo: WorkspaceTab?
    private var floatingVideoController: FloatingVideoController?
    private var openingFloatingVideo = false
    private(set) var popOutVideoOpacity = 1.0

    var selectedAccount: Account? { accounts.first { $0.id == (selection?.accountID ?? lastAccountID) } }

    /// The order shortcuts and closing follow, matching what's on screen.
    var navigationTabs: [WorkspaceTab] { layout == .sidebar ? WorkspaceTab.grouped(tabs, by: accounts) : tabs }

    var canSaveTranscript: Bool {
        guard let selection, !savingTranscript else { return false }
        return VideoTranscript.isVideoPage(currentBrowser?.url, service: selection.service)
    }

    var canPinCurrentPage: Bool {
        guard let selection, let url = currentBrowser?.url else { return false }
        return WorkspacePin.canPin(url, in: selection.service)
    }

    #if DEBUG
    /// Debug builds never open the real profile, whatever their bundle identifier says.
    static func debugDataDirectory(support: URL, requested: String?, environment: String?) -> String {
        let valid = requested.flatMap { URL(fileURLWithPath: $0).lastPathComponent.hasPrefix("MailPortSecurityTest-") ? $0 : nil }
        return valid ?? environment ?? support.appendingPathComponent("MailPortSecurityTest-securityqa").path
    }
    #endif

    init(testingDirectory: URL? = nil, securityEngine: PINLockEngine? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        #if DEBUG
        let requested = Bundle.main.object(forInfoDictionaryKey: "MailPortTestingDataDirectory") as? String
        let override: String? = testingDirectory?.path ?? Self.debugDataDirectory(support: support, requested: requested,
            environment: ProcessInfo.processInfo.environment["MAILPORT_PREVIEW_DATA_DIR"])
        #else
        // Release builds never accept environment overrides that could sidestep
        // the production Keychain record or substitute an unprotected account list.
        let override = testingDirectory?.path
        #endif
        testingMode = override != nil
        directory = override.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? support.appendingPathComponent("MailPortPreview", isDirectory: true)
        accountStore = AccountStore(directory: directory)
        preferenceDomain = override == nil ? (Bundle.main.bundleIdentifier ?? "com.chriswilson.mailport.embedded")
            : "com.chriswilson.mailport.testing." + AppSecurity.testingSuffix(for: directory)
        preferences = override == nil ? .standard : (UserDefaults(suiteName: preferenceDomain) ?? .standard)
        security = AppSecurity(preferences: preferences, testingDirectory: override == nil ? nil : directory, engine: securityEngine)
        layout = preferences.string(forKey: "workspaceLayout").flatMap(WorkspaceLayout.init(rawValue:)) ?? .sidebar
        securityChanges = security.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        security.onLock = { [weak self] in self?.suspendForLock() }
        security.onUnlock = { [weak self] in
            guard let self else { return }
            MailPortNotifications.shared.setPrivacyLocked(false)
            self.restoreWorkspace()
            if let incoming = self.incomingAfterUnlock {
                self.incomingAfterUnlock = nil
                self.receive(incoming)
            }
        }
        security.onErase = { [weak self] in
            guard let self else { throw PINLockError.invalidState }
            try await self.eraseLocalData()
        }
        let notifications = MailPortNotifications.shared
        notifications.setPrivacyLocked(true, clearDelivered: false)
        notifications.onPermissionChanged = { [weak self] in
            guard let self, !self.security.blocksAccess else { return }
            if notifications.permission == "granted" { self.prepareCalendarReminders() }
            else {
                for tab in Array(self.browsers.keys) where tab.service == .calendar && !self.tabs.contains(tab) {
                    self.browsers.removeValue(forKey: tab)?.webView.stopLoading()
                }
            }
            for browser in self.browsers.values { browser.notificationBridge.updatePermission() }
        }
        notifications.settingsForAccount = { [weak self] id in self?.notificationSettings[id] ?? AccountNotificationSettings() }
        notifications.attachOpenHandler { [weak self] accountID, service, webID in
            guard let self, self.accounts.contains(where: { $0.id == accountID }) else { return }
            self.select(WorkspaceTab(accountID: accountID, service: service))
            self.showWindow()
            if let webID { self.currentBrowser?.notificationBridge.clicked(webID) }
        }
        Task { await notifications.refresh() }
        security.start()
        activityTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.updateDockBadge()
                let today = Calendar.current.startOfDay(for: Date())
                if today != self.activityDay {
                    self.activityDay = today
                    for monitor in self.calendarMonitors.values {
                        monitor.load(URL(string: "https://calendar.google.com/calendar/u/0/r/day")!)
                    }
                }
            }
        }
    }

    private func restoreWorkspace() {
        skipsYouTubeAds = preferences.bool(forKey: "youtubeAutoSkipAds")
        allowsYouTubeDownloads = preferences.bool(forKey: "youtubeMediaDownloads")
        popOutVideoOpacity = VideoOpacity.normalized((preferences.object(forKey: "popOutVideoOpacity") as? Double) ?? 1)
        guard !security.blocksAccess else { return }
        storageAvailable = true
        do {
            accounts = try accountStore.load()
            lastAccountID = preferences.string(forKey: "lastAccount").flatMap(UUID.init(uuidString:))
            if let saved = preferences.data(forKey: "pins"), let restored = try? JSONDecoder().decode([WorkspacePin].self, from: saved) {
                pins = restored.filter { pin in pin.isValid && accounts.contains { $0.id == pin.accountID } }
            }
            showsShortcutHints = preferences.object(forKey: "showsShortcutHints") as? Bool ?? true
            defaultMailAccountID = preferences.string(forKey: "defaultMailAccount").flatMap(UUID.init(uuidString:))
                .flatMap { id in accounts.contains { $0.id == id } ? id : nil }
            let accountIDs = Set(accounts.map(\.id))
            dockBadgeExcluded = Set((preferences.stringArray(forKey: "dockBadgeExcluded") ?? []).compactMap(UUID.init(uuidString:))).intersection(accountIDs)
            if let saved = preferences.data(forKey: "accountNotifications"),
               let restored = try? JSONDecoder().decode([UUID: AccountNotificationSettings].self, from: saved) {
                notificationSettings = restored.filter { accountIDs.contains($0.key) }
            }
            let zoom = preferences.dictionary(forKey: "serviceZoom") as? [String: Double] ?? [:]
            serviceZoom = zoom.reduce(into: [:]) { result, entry in
                if let service = GoogleService(rawValue: entry.key), PageZoom.isValid(entry.value) { result[service] = entry.value }
            }
            let collapsed = preferences.stringArray(forKey: "collapsedAccounts") ?? []
            collapsedAccounts = Set(collapsed.compactMap(UUID.init(uuidString:))).intersection(accounts.map(\.id))
            if let saved = preferences.data(forKey: "openTabs"), let restored = try? JSONDecoder().decode([WorkspaceTab].self, from: saved) {
                var seen = Set<WorkspaceTab>()
                tabs = restored.filter { tab in accounts.contains { $0.id == tab.accountID } && seen.insert(tab).inserted }
            } else { tabs = WorkspaceTab.pinnedTabs(for: accounts) }
            let previousID = preferences.string(forKey: "selectedTab")
            if preferences.data(forKey: "openTabs") == nil,
               let previous = accounts.flatMap({ account in GoogleService.allCases.map { WorkspaceTab(accountID: account.id, service: $0) } }).first(where: { $0.id == previousID }),
               !tabs.contains(previous) { tabs.append(previous) }
            if let tab = tabs.first(where: { $0.id == previousID }) ?? tabs.first { select(tab) }
        } catch {
            storageAvailable = false
            errorMessage = "MailPort couldn’t read the account list. Your saved files have been preserved. \(error.localizedDescription)"
        }
        prepareTabActivity()
        if MailPortNotifications.shared.permission == "granted" { prepareCalendarReminders() }
    }

    private func suspendForLock() {
        clearVideoDockMenu?()
        closeFloatingVideo()
        openingFloatingVideo = false
        popOutVideoOpacity = 1
        cancelMediaDownload()
        showingVideoOptions = false; videoOptionsURL = nil; pendingVideoSelection = false; pendingVideoHeight = nil
        skipsYouTubeAds = false; allowsYouTubeDownloads = false
        // Remove sensitive views and AppKit sheets before returning from the sleep hook.
        showingAccountEditor = false; editingAccount = nil
        showingHelp = false; showingNotifications = false; showingSecuritySettings = false
        showingQuickSwitch = false; showingPinEditor = false; accountPendingRemoval = nil
        pendingCompose = nil; errorMessage = nil
        for sheet in mainWindow?.sheets ?? [] { mainWindow?.endSheet(sheet); sheet.orderOut(nil) }
        MailPortNotifications.shared.setPrivacyLocked(true)
        browserChanges = nil
        for browser in Array(browsers.values) + Array(calendarMonitors.values) { browser.discardForSecurity() }
        currentBrowser = nil
        browsers.removeAll(); calendarMonitors.removeAll(); stores.removeAll()
        accounts.removeAll(); tabs.removeAll(); recentlyClosed.removeAll(); tabActivity.removeAll()
        pins.removeAll(); collapsedAccounts.removeAll(); accountsNeedingSignIn.removeAll(); defaultMailAccountID = nil
        dockBadgeExcluded.removeAll(); notificationSettings.removeAll()
        selection = nil; lastAccountID = nil
    }

    private func eraseLocalData() async throws {
        suspendForLock()
        incomingAfterUnlock = nil
        MailPortNotifications.shared.clearForLocalReset()
        // Let SwiftUI release the detached web views before removing WebKit stores.
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        let identifiers = testingMode ? try accountStore.load().map(\.id) : await LocalDataReset.allWebsiteIdentifiers()
        try await LocalDataReset.erase(directory: directory, preferenceDomain: preferenceDomain,
            websiteIdentifiers: identifiers, includeDefaultStore: !testingMode)
    }

    func openSecuritySettings() {
        showWindow()
        if !security.blocksAccess { showingSecuritySettings = true }
    }

    func select(_ tab: WorkspaceTab) {
        guard !security.blocksAccess else { return }
        guard let account = accounts.first(where: { $0.id == tab.accountID }) else { return }
        if !tabs.contains(tab) { tabs.append(tab) }
        ensureBrowser(for: tab, account: account)
        selection = tab
        if collapsedAccounts.remove(tab.accountID) != nil { persistCollapsedAccounts() }
        lastAccountID = tab.accountID
        preferences.set(tab.accountID.uuidString, forKey: "lastAccount")
        currentBrowser = browsers[tab]
        browserChanges = currentBrowser?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        preferences.set(tab.id, forKey: "selectedTab")
        persistTabs()
        prepareTabActivity()
    }

    func open(_ service: GoogleService, account: Account? = nil) {
        guard !security.blocksAccess else { return }
        guard let account = account ?? selectedAccount ?? accounts.first else { addAccount(); return }
        select(WorkspaceTab(accountID: account.id, service: service))
    }

    func close(_ tab: WorkspaceTab) {
        guard !security.blocksAccess else { return }
        guard tabs.contains(tab) else { return }
        let next = WorkspaceTab.selection(afterClosing: tab, in: navigationTabs, selected: selection)
        if poppedOutVideo == tab { closeFloatingVideo() }
        if tab.service == .youtube { browsers[tab]?.discardForSecurity() }
        tabs.removeAll { $0 == tab }
        if selection == tab {
            browserChanges = nil
            currentBrowser = nil
            selection = nil
            preferences.removeObject(forKey: "selectedTab")
            if let next { select(next) }
        }
        if tab.service != .calendar || MailPortNotifications.shared.permission != "granted" {
            browsers.removeValue(forKey: tab)?.webView.stopLoading()
        }
        tabActivity.removeValue(forKey: tab)
        if tab.service == .calendar { calendarMonitors.removeValue(forKey: tab.accountID)?.webView.stopLoading() }
        recentlyClosed.removeAll { $0 == tab }
        recentlyClosed.append(tab)
        if recentlyClosed.count > 20 { recentlyClosed.removeFirst() }
        persistTabs()
    }

    func closeCurrentTab() { if let selection { close(selection) } }

    func moveTab(_ source: WorkspaceTab, over target: WorkspaceTab) {
        guard !security.blocksAccess else { return }
        let reordered = WorkspaceTab.reordered(tabs, moving: source, over: target)
        guard reordered != tabs else { return }
        tabs = reordered
        persistTabs()
    }

    private func ensureBrowser(for tab: WorkspaceTab, account: Account) {
        guard browsers[tab] == nil else { return }
        let store = stores[account.id] ?? WKWebsiteDataStore(forIdentifier: account.id)
        stores[account.id] = store
        let browser = BrowserTab(account: account, service: tab.service, store: store)
        browser.skipsYouTubeAds = skipsYouTubeAds
        browser.onMailto = { [weak self] url in self?.receive(url) }
        browser.onSignInChange = { [weak self] needed in self?.updateSignIn(needed, for: account.id) }
        browser.webView.pageZoom = serviceZoom[tab.service] ?? PageZoom.standard
        if tab.service == .gmail {
            browser.onActivity = { [weak self] sample in self?.recordActivity(sample, for: tab) }
        }
        browsers[tab] = browser
    }

    private func prepareTabActivity() {
        guard !security.blocksAccess else { return }
        for tab in tabs {
            guard let account = accounts.first(where: { $0.id == tab.accountID }) else { continue }
            if tab.service == .gmail { ensureBrowser(for: tab, account: account) }
            if tab.service == .calendar, calendarMonitors[account.id] == nil {
                let store = stores[account.id] ?? WKWebsiteDataStore(forIdentifier: account.id)
                stores[account.id] = store
                // Observe today's view independently of whichever date the user is browsing.
                // This page has no native notification bridge, so it cannot duplicate alerts.
                let monitor = BrowserTab(account: account, service: .calendar, store: store, activityOnly: true)
                monitor.onActivity = { [weak self] sample in self?.recordActivity(sample, for: tab) }
                monitor.onSignInChange = { [weak self] needed in self?.updateSignIn(needed, for: account.id) }
                calendarMonitors[account.id] = monitor
            }
        }
    }

    func dockBadgeLabel(at now: Date = Date()) -> String? {
        let counted = tabActivity.filter { $0.key.service == .gmail && !dockBadgeExcluded.contains($0.key.accountID) }
        return TabActivity.totalBadge(Array(counted.values), at: now)
    }

    func updateDockBadge() { NSApp?.dockTile.badgeLabel = dockBadgeLabel() }

    func setCountsInDockBadge(_ counts: Bool, for account: Account) {
        guard !security.blocksAccess else { return }
        if counts { dockBadgeExcluded.remove(account.id) } else { dockBadgeExcluded.insert(account.id) }
        preferences.set(dockBadgeExcluded.map(\.uuidString), forKey: "dockBadgeExcluded")
        updateDockBadge()
    }

    func recordActivity(_ sample: TabActivity?, for tab: WorkspaceTab) { tabActivity[tab] = sample }

    func notificationSettings(for account: Account) -> AccountNotificationSettings {
        notificationSettings[account.id] ?? AccountNotificationSettings()
    }

    func muteNotifications(for account: Account, until date: Date?) {
        var settings = notificationSettings(for: account)
        settings.mutedUntil = date
        store(settings, for: account.id)
    }

    func setHidesPreviews(_ hides: Bool, for account: Account) {
        var settings = notificationSettings(for: account)
        settings.hidesPreviews = hides
        store(settings, for: account.id)
    }

    private func store(_ settings: AccountNotificationSettings?, for accountID: UUID) {
        guard !security.blocksAccess else { return }
        notificationSettings[accountID] = settings
        if let data = try? JSONEncoder().encode(notificationSettings) { preferences.set(data, forKey: "accountNotifications") }
    }

    /// Loaded videos stay controllable even when their account isn't selected.
    var dockVideoTabs: [WorkspaceTab] {
        guard !security.blocksAccess else { return [] }
        let loaded = navigationTabs.filter { browsers[$0]?.videoPlayback.hasVideo == true }
        return loaded.filter { browsers[$0]?.videoPlayback.isPlaying == true } + loaded.filter { browsers[$0]?.videoPlayback.isPlaying != true }
    }

    func videoState(for tab: WorkspaceTab) -> VideoPlaybackState { browsers[tab]?.videoPlayback ?? .none }

    func videoLabel(for tab: WorkspaceTab) -> String {
        guard !security.blocksAccess, let browser = browsers[tab] else { return "Video" }
        let title = browser.title.replacingOccurrences(of: " - YouTube", with: "")
        return "\(browser.account.name) · \(String(title.prefix(90)))"
    }

    func controlVideo(_ action: String, tabID: String? = nil) {
        guard !security.blocksAccess else { return }
        let target: WorkspaceTab?
        if let tabID { target = tabs.first { $0.id == tabID } }
        else { target = selection }
        guard let tab = target, tab.service == .youtube, let browser = browsers[tab] else { return }
        if action == "popOut" { popOutVideo(tab); return }
        Task { @MainActor [weak self, weak browser] in
            guard let self, let browser, !self.security.blocksAccess else { return }
            do {
                let state = try await browser.performVideoAction(action)
                if !state.hasVideo && !self.security.blocksAccess { self.errorMessage = "Start a YouTube video, then try the playback control again." }
            } catch {
                if !self.security.blocksAccess { self.errorMessage = "The video control couldn’t be used. \(error.localizedDescription)"; self.showWindow() }
            }
        }
    }

    func setPopOutVideoOpacity(_ value: Double) {
        guard !security.blocksAccess else { return }
        popOutVideoOpacity = VideoOpacity.normalized(value)
        preferences.set(popOutVideoOpacity, forKey: "popOutVideoOpacity")
        floatingVideoController?.setOpacity(popOutVideoOpacity)
    }

    func closeFloatingVideo() {
        let controller = floatingVideoController
        controller?.close()
        floatingVideoController = nil
        poppedOutVideo = nil
    }

    private func popOutVideo(_ tab: WorkspaceTab) {
        if poppedOutVideo == tab { closeFloatingVideo(); select(tab); showWindow(); return }
        guard !openingFloatingVideo, let browser = browsers[tab], browser.videoPlayback.hasVideo else { return }
        openingFloatingVideo = true
        Task { @MainActor [weak self, weak browser] in
            guard let self, let browser else { return }
            defer { self.openingFloatingVideo = false }
            do {
                guard let frame = try await browser.videoFrame() else {
                    if !self.security.blocksAccess { self.errorMessage = "Make sure the video player is fully visible and exit fullscreen, then try Pop Out Video again." }
                    return
                }
                guard !self.security.blocksAccess, self.tabs.contains(tab), self.browsers[tab] === browser else { return }
                self.closeFloatingVideo()
                self.poppedOutVideo = tab
                let controller = FloatingVideoController(browser: browser, frame: frame, screen: self.mainWindow?.screen, opacity: self.popOutVideoOpacity)
                self.floatingVideoController = controller
                controller.onOpacityChange = { [weak self] value in self?.setPopOutVideoOpacity(value) }
                controller.onReturn = { [weak self] in self?.floatingVideoController = nil; self?.poppedOutVideo = nil }
                controller.onToggle = { [weak self] in self?.controlVideo("toggle", tabID: tab.id) }
                controller.showWindow(nil)
            } catch {
                if !self.security.blocksAccess { self.errorMessage = "The video couldn’t be popped out. \(error.localizedDescription)" }
            }
        }
    }

    func showVideo(tabID: String) {
        guard !security.blocksAccess, let tab = tabs.first(where: { $0.id == tabID }) else { return }
        select(tab); showWindow()
    }

    func setSkipsYouTubeAds(_ enabled: Bool) {
        guard !security.blocksAccess else { return }
        skipsYouTubeAds = enabled
        preferences.set(enabled, forKey: "youtubeAutoSkipAds")
        for browser in browsers.values { browser.skipsYouTubeAds = enabled }
    }

    func setAllowsYouTubeDownloads(_ enabled: Bool) {
        guard !security.blocksAccess else { return }
        allowsYouTubeDownloads = enabled
        preferences.set(enabled, forKey: "youtubeMediaDownloads")
        if !enabled { cancelMediaDownload(); showingVideoOptions = false; pendingVideoSelection = false; videoOptionsURL = nil }
    }

    var canSaveMedia: Bool {
        !security.blocksAccess && allowsYouTubeDownloads && !savingMedia && selection?.service == .youtube && YouTubeMedia.videoURL(currentBrowser?.url) != nil
    }

    func cancelMediaDownload() {
        mediaDownload?.cancel()
        videoOptionsReader?.cancel()
        mediaStatus = nil
    }

    func saveMedia(audio: Bool) {
        guard canSaveMedia, let url = YouTubeMedia.videoURL(currentBrowser?.url), let window = mainWindow else { return }
        guard YouTubeDownload.helper != nil else {
            errorMessage = "Media saving uses yt-dlp and Deno, plus FFmpeg for high-resolution video. Open Terminal and run: brew install yt-dlp deno ffmpeg. After installation finishes, try Save Media again. You can also copy the command in Settings > YouTube. Other YouTube features work without these tools."
            return
        }
        if !audio {
            guard YouTubeDownload.ffmpeg != nil else {
                errorMessage = "High-resolution video saving requires FFmpeg. Open Terminal and run: brew install yt-dlp deno ffmpeg"
                return
            }
            videoOptionsURL = url
            pendingVideoSelection = false
            pendingVideoHeight = nil
            showingVideoOptions = true
            return
        }
        presentMediaSavePanel(url: url, audio: true, window: window)
    }

    func readVideoResolutions(url: URL) async throws -> [Int] {
        guard !security.blocksAccess, allowsYouTubeDownloads else { throw CancellationError() }
        videoOptionsReader?.cancel()
        let reader = YouTubeDownload()
        videoOptionsReader = reader
        defer { if videoOptionsReader === reader { videoOptionsReader = nil } }
        return try await reader.resolutions(url: url)
    }

    func cancelVideoResolutionCheck() { videoOptionsReader?.cancel() }

    func chooseVideoResolution(_ height: Int?) {
        pendingVideoHeight = height
        pendingVideoSelection = true
        showingVideoOptions = false
    }

    func completeVideoOptions() {
        defer { videoOptionsURL = nil; pendingVideoSelection = false; pendingVideoHeight = nil }
        guard pendingVideoSelection, let url = videoOptionsURL, !security.blocksAccess,
              allowsYouTubeDownloads, !savingMedia, let window = mainWindow else { return }
        presentMediaSavePanel(url: url, audio: false, window: window, height: pendingVideoHeight)
    }

    private func presentMediaSavePanel(url: URL, audio: Bool, window: NSWindow, height: Int? = nil) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = audio ? [.mpeg4Audio] : [.mpeg4Movie]
        panel.nameFieldStringValue = audio ? "YouTube audio.m4a" : "YouTube video.mp4"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let destination = panel.url,
                  !self.security.blocksAccess, self.allowsYouTubeDownloads, !self.savingMedia else { return }
            let download = YouTubeDownload()
            self.mediaDownload = download
            self.savingMedia = true
            self.mediaStatus = audio ? "Saving audio…" : "Saving video…"
            Task { @MainActor in
                defer { self.savingMedia = false; self.mediaDownload = nil }
                do {
                    try await download.save(url: url, audio: audio, destination: destination, height: height)
                    if !self.security.blocksAccess { self.mediaStatus = "Saved \(destination.lastPathComponent)" }
                } catch is CancellationError { self.mediaStatus = nil }
                catch {
                    self.mediaStatus = nil
                    if !self.security.blocksAccess { self.errorMessage = error.localizedDescription }
                }
            }
        }
    }

    func saveTranscript() {
        guard !security.blocksAccess, canSaveTranscript, let browser = currentBrowser else { return }
        savingTranscript = true
        Task {
            defer { savingTranscript = false }
            do {
                guard let transcript = try await browser.readTranscript() else {
                    errorMessage = "MailPort couldn’t get a transcript. This video may not have captions. If an ad is playing, try again once the video starts."
                    return
                }
                guard !security.blocksAccess else { return }
                presentSavePanel(for: transcript)
            } catch {
                errorMessage = "MailPort couldn’t read this video’s transcript. YouTube may have changed its page. \(error.localizedDescription)"
            }
        }
    }

    private func presentSavePanel(for transcript: VideoTranscript) {
        guard let window = mainWindow else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = transcript.suggestedFilename
        panel.allowedContentTypes = [.plainText]
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let destination = panel.url else { return }
            do { try transcript.text.write(to: destination, atomically: true, encoding: .utf8) }
            catch { self?.errorMessage = "The transcript couldn’t be saved. \(error.localizedDescription)" }
        }
    }

    func updateSignIn(_ needed: Bool, for accountID: UUID) {
        guard needed != accountsNeedingSignIn.contains(accountID) else { return }
        if needed { accountsNeedingSignIn.insert(accountID); return }
        accountsNeedingSignIn.remove(accountID)
        for (tab, browser) in browsers where tab.accountID == accountID { browser.leaveSignIn() }
        calendarMonitors[accountID]?.leaveSignIn()
    }

    func zoom(by direction: Int) {
        guard let service = selection?.service else { return }
        setZoom(PageZoom.stepped(from: serviceZoom[service] ?? PageZoom.standard, by: direction), for: service)
    }

    func resetZoom() {
        if let service = selection?.service { setZoom(PageZoom.standard, for: service) }
    }

    func setZoom(_ zoom: Double, for service: GoogleService) {
        guard !security.blocksAccess, PageZoom.isValid(zoom) else { return }
        if poppedOutVideo?.service == service { closeFloatingVideo() }
        serviceZoom[service] = zoom
        preferences.set(Dictionary(uniqueKeysWithValues: serviceZoom.map { ($0.key.rawValue, $0.value) }), forKey: "serviceZoom")
        for (tab, browser) in browsers where tab.service == service { browser.webView.pageZoom = zoom }
    }

    func setDefaultMailAccount(_ id: UUID?) {
        guard !security.blocksAccess else { return }
        defaultMailAccountID = id
        preferences.set(id?.uuidString, forKey: "defaultMailAccount")
    }

    func prepareCalendarReminders() {
        guard !security.blocksAccess else { return }
        for account in accounts { ensureBrowser(for: WorkspaceTab(accountID: account.id, service: .calendar), account: account) }
    }

    func openCalendarNotificationSettings(account: Account) {
        guard !security.blocksAccess else { return }
        select(WorkspaceTab(accountID: account.id, service: .calendar))
        currentBrowser?.load(URL(string: "https://calendar.google.com/calendar/u/0/r/settings")!)
    }

    func reopenClosedTab() {
        guard !security.blocksAccess else { return }
        while let tab = recentlyClosed.popLast() {
            if accounts.contains(where: { $0.id == tab.accountID }) { select(tab); return }
        }
    }

    private func persistTabs() {
        if let data = try? JSONEncoder().encode(tabs) { preferences.set(data, forKey: "openTabs") }
    }

    private func persistPins() {
        if let data = try? JSONEncoder().encode(pins) { preferences.set(data, forKey: "pins") }
    }

    private func persistCollapsedAccounts() {
        preferences.set(collapsedAccounts.map(\.uuidString), forKey: "collapsedAccounts")
    }

    func toggleCollapsed(_ account: Account) {
        guard !security.blocksAccess else { return }
        if collapsedAccounts.remove(account.id) == nil { collapsedAccounts.insert(account.id) }
        persistCollapsedAccounts()
    }

    func quickSwitchItems(matching query: String) -> [QuickSwitchItem] {
        QuickSwitch.items(accounts: accounts, tabs: navigationTabs, pins: pins, query: query)
    }

    func go(to item: QuickSwitchItem) {
        switch item.destination {
        case .tab(let tab): select(tab)
        case .pin(let pin): open(pin)
        }
    }

    func open(_ pin: WorkspacePin) {
        guard !security.blocksAccess else { return }
        select(WorkspaceTab(accountID: pin.accountID, service: pin.service))
        currentBrowser?.load(pin.url)
    }

    func pinCurrentPage(named name: String) {
        guard !security.blocksAccess, let selection, let url = currentBrowser?.url,
              let pin = WorkspacePin(accountID: selection.accountID, service: selection.service, name: name, url: url) else { return }
        pins.append(pin)
        persistPins()
    }

    func movePin(_ source: WorkspacePin, over target: WorkspacePin) {
        guard !security.blocksAccess else { return }
        let reordered = WorkspacePin.reordered(pins, moving: source, over: target)
        guard reordered != pins else { return }
        pins = reordered
        persistPins()
    }

    func removePin(_ pin: WorkspacePin) {
        guard !security.blocksAccess else { return }
        pins.removeAll { $0.id == pin.id }
        persistPins()
    }

    func nextTab(_ delta: Int) {
        guard !security.blocksAccess else { return }
        let ordered = navigationTabs
        guard !ordered.isEmpty else { return }
        let index = ordered.firstIndex(where: { $0 == selection }) ?? 0
        select(ordered[(index + delta + ordered.count) % ordered.count])
    }

    func shortcutNumber(for tab: WorkspaceTab) -> Int? {
        showsShortcutHints ? WorkspaceTab.shortcutNumber(of: tab, in: navigationTabs) : nil
    }

    func setShowsShortcutHints(_ shows: Bool) {
        showsShortcutHints = shows
        preferences.set(shows, forKey: "showsShortcutHints")
    }

    func selectTab(number: Int) {
        let ordered = navigationTabs
        if ordered.indices.contains(number - 1) { select(ordered[number - 1]) }
    }

    func addAccount() {
        guard !security.blocksAccess else { return }
        guard storageAvailable else { return }
        editingAccount = nil
        showingAccountEditor = true
    }

    func editAccount(_ account: Account) {
        guard !security.blocksAccess else { return }
        editingAccount = account
        showingAccountEditor = true
    }

    func saveAccount(_ account: Account) throws {
        guard !security.blocksAccess else { throw PINLockError.unavailable }
        guard storageAvailable else { throw CocoaError(.fileReadCorruptFile) }
        let validated = try account.validated()
        var updated = accounts
        let isNew = !accounts.contains { $0.id == validated.id }
        if let index = updated.firstIndex(where: { $0.id == validated.id }) { updated[index] = validated }
        else { updated.append(validated) }
        try accountStore.save(updated)
        accounts = updated
        showingAccountEditor = false
        if isNew {
            tabs.append(contentsOf: WorkspaceTab.pinnedTabs(for: [validated]))
            select(WorkspaceTab(accountID: validated.id, service: .gmail))
        }
        persistTabs()
        if MailPortNotifications.shared.permission == "granted" { prepareCalendarReminders() }
    }

    func removeAccount(_ account: Account) {
        guard !security.blocksAccess else { return }
        do {
            let updated = accounts.filter { $0.id != account.id }
            try accountStore.save(updated)
            accounts = updated
            tabs.removeAll { $0.accountID == account.id }
            recentlyClosed.removeAll { $0.accountID == account.id }
            if poppedOutVideo?.accountID == account.id { closeFloatingVideo() }
            for (tab, browser) in browsers where tab.accountID == account.id { browser.discardForSecurity() }
            browsers = browsers.filter { $0.key.accountID != account.id }
            calendarMonitors.removeValue(forKey: account.id)?.webView.stopLoading()
            tabActivity = tabActivity.filter { $0.key.accountID != account.id }
            stores.removeValue(forKey: account.id)
            pins.removeAll { $0.accountID == account.id }
            persistPins()
            accountsNeedingSignIn.remove(account.id)
            if defaultMailAccountID == account.id { setDefaultMailAccount(nil) }
            if dockBadgeExcluded.contains(account.id) { setCountsInDockBadge(true, for: account) }
            if notificationSettings[account.id] != nil { store(nil, for: account.id) }
            if collapsedAccounts.remove(account.id) != nil { persistCollapsedAccounts() }
            if selection?.accountID == account.id {
                browserChanges = nil
                currentBrowser = nil
                selection = nil
                if let first = tabs.first { select(first) }
            }
            persistTabs()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Deletes the website data before the account, so a failed removal can be
    /// retried from the sidebar instead of leaving a sign-in nothing points to.
    func signOutAndRemoveAccount(_ account: Account) async {
        guard !security.blocksAccess, accounts.contains(account) else { return }
        for tab in tabs where tab.accountID == account.id { tabActivity.removeValue(forKey: tab) }
        if selection?.accountID == account.id {
            browserChanges = nil
            currentBrowser = nil
            selection = nil
        }
        tabs.removeAll { $0.accountID == account.id }
        recentlyClosed.removeAll { $0.accountID == account.id }
        for (tab, browser) in browsers where tab.accountID == account.id { browser.discardForSecurity() }
        browsers = browsers.filter { $0.key.accountID != account.id }
        calendarMonitors.removeValue(forKey: account.id)?.discardForSecurity()
        stores.removeValue(forKey: account.id)
        persistTabs()
        if let next = navigationTabs.first { select(next) }
        // Let SwiftUI release the detached web views before removing the WebKit store.
        await withCheckedContinuation { continuation in DispatchQueue.main.async { continuation.resume() } }
        do {
            try await LocalDataReset.eraseWebsiteData(id: account.id)
            removeAccount(account)
        } catch {
            errorMessage = "MailPort couldn’t finish signing out \(account.name). The account is still listed so you can try again. \(error.localizedDescription)"
        }
    }

    func compose() {
        guard !security.blocksAccess else { return }
        guard let account = selectedAccount else { addAccount(); return }
        select(WorkspaceTab(accountID: account.id, service: .gmail))
        if let compose = try? GmailCompose() { currentBrowser?.load(compose.url) }
    }

    func home() { if let selection { currentBrowser?.load(selection.service.url) } }

    func receive(_ url: URL) {
        guard !security.blocksAccess else {
            if url.scheme?.lowercased() == "mailto", (try? GmailCompose(mailto: url)) != nil { incomingAfterUnlock = url }
            showWindow()
            return
        }
        if url.scheme?.lowercased() == "mailto" {
            do {
                _ = try GmailCompose(mailto: url)
                pendingCompose = url
                if let account = accounts.first(where: { $0.id == defaultMailAccountID }) { composePending(with: account) }
            } catch { errorMessage = error.localizedDescription }
        }
        showWindow()
    }

    func composePending(with account: Account) {
        guard !security.blocksAccess else { return }
        guard let url = pendingCompose else { return }
        do {
            let compose = try GmailCompose(mailto: url)
            select(WorkspaceTab(accountID: account.id, service: .gmail))
            currentBrowser?.load(compose.url)
            pendingCompose = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func showWindow() {
        if mainWindow?.isVisible != true { reopenWindow?() }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp?.activate(ignoringOtherApps: true)
    }
}

extension HexColor {
    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
    }
}

extension Account {
    var nsColor: NSColor { hexColor?.nsColor ?? color.nsColor }
    /// Presets all read well with white; a custom color may not.
    var labelColor: NSColor { hexColor?.prefersDarkText == true ? .black : .white }
}

extension AccountColor {
    var nsColor: NSColor {
        switch self {
        case .blue: .systemBlue
        case .teal: .systemTeal
        case .orange: .systemOrange
        case .purple: .systemPurple
        case .rose: .systemPink
        }
    }
}
