import AppKit
import Combine
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
    @Published private(set) var tabActivity: [WorkspaceTab: TabActivity] = [:]
    @Published private(set) var pins: [WorkspacePin] = []
    @Published private(set) var collapsedAccounts: Set<UUID> = []
    @Published private(set) var showsShortcutHints = true
    @Published var layout: WorkspaceLayout = .sidebar {
        didSet { preferences.set(layout.rawValue, forKey: "workspaceLayout") }
    }
    weak var mainWindow: NSWindow?
    var reopenWindow: (() -> Void)?

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

    var selectedAccount: Account? { accounts.first { $0.id == (selection?.accountID ?? lastAccountID) } }

    /// The order shortcuts and closing follow, matching what's on screen.
    var navigationTabs: [WorkspaceTab] { layout == .sidebar ? WorkspaceTab.grouped(tabs, by: accounts) : tabs }

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
        guard !security.blocksAccess else { return }
        storageAvailable = true
        do {
            accounts = try accountStore.load()
            lastAccountID = preferences.string(forKey: "lastAccount").flatMap(UUID.init(uuidString:))
            if let saved = preferences.data(forKey: "pins"), let restored = try? JSONDecoder().decode([WorkspacePin].self, from: saved) {
                pins = restored.filter { pin in pin.isValid && accounts.contains { $0.id == pin.accountID } }
            }
            showsShortcutHints = preferences.object(forKey: "showsShortcutHints") as? Bool ?? true
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
        pins.removeAll(); collapsedAccounts.removeAll()
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
        browser.onMailto = { [weak self] url in self?.receive(url) }
        if tab.service == .gmail {
            browser.onActivity = { [weak self] sample in self?.tabActivity[tab] = sample }
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
                monitor.onActivity = { [weak self] sample in self?.tabActivity[tab] = sample }
                calendarMonitors[account.id] = monitor
            }
        }
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
            browsers = browsers.filter { $0.key.accountID != account.id }
            calendarMonitors.removeValue(forKey: account.id)?.webView.stopLoading()
            tabActivity = tabActivity.filter { $0.key.accountID != account.id }
            stores.removeValue(forKey: account.id)
            pins.removeAll { $0.accountID == account.id }
            persistPins()
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
            do { _ = try GmailCompose(mailto: url); pendingCompose = url }
            catch { errorMessage = error.localizedDescription }
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
