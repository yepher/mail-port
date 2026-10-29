import AppKit
import Combine
import WebKit
import MailPortCore

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
    @Published var errorMessage: String?
    @Published var pendingCompose: URL?
    @Published private(set) var storageAvailable = true
    @Published private(set) var recentlyClosed: [WorkspaceTab] = []
    weak var mainWindow: NSWindow?
    var reopenWindow: (() -> Void)?

    let directory: URL
    private let accountStore: AccountStore
    private var stores: [UUID: WKWebsiteDataStore] = [:]
    private var browsers: [WorkspaceTab: BrowserTab] = [:]
    private var browserChanges: AnyCancellable?
    private var preferences: UserDefaults
    private var lastAccountID: UUID?

    var selectedAccount: Account? { accounts.first { $0.id == (selection?.accountID ?? lastAccountID) } }

    init() {
        let override = ProcessInfo.processInfo.environment["MAILPORT_PREVIEW_DATA_DIR"]
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        directory = override.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? support.appendingPathComponent("MailPortPreview", isDirectory: true)
        accountStore = AccountStore(directory: directory)
        preferences = override == nil ? .standard : (UserDefaults(suiteName: "com.chriswilson.mailport.embedded.testing") ?? .standard)
        do {
            accounts = try accountStore.load()
            lastAccountID = preferences.string(forKey: "lastAccount").flatMap(UUID.init(uuidString:))
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
        let notifications = MailPortNotifications.shared
        notifications.onPermissionChanged = { [weak self] in
            guard let self else { return }
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
    }

    func select(_ tab: WorkspaceTab) {
        guard let account = accounts.first(where: { $0.id == tab.accountID }) else { return }
        if !tabs.contains(tab) { tabs.append(tab) }
        ensureBrowser(for: tab, account: account)
        selection = tab
        lastAccountID = tab.accountID
        preferences.set(tab.accountID.uuidString, forKey: "lastAccount")
        currentBrowser = browsers[tab]
        browserChanges = currentBrowser?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        preferences.set(tab.id, forKey: "selectedTab")
        persistTabs()
    }

    func open(_ service: GoogleService, account: Account? = nil) {
        guard let account = account ?? selectedAccount ?? accounts.first else { addAccount(); return }
        select(WorkspaceTab(accountID: account.id, service: service))
    }

    func close(_ tab: WorkspaceTab) {
        guard tabs.contains(tab) else { return }
        let next = WorkspaceTab.selection(afterClosing: tab, in: tabs, selected: selection)
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
        recentlyClosed.removeAll { $0 == tab }
        recentlyClosed.append(tab)
        if recentlyClosed.count > 20 { recentlyClosed.removeFirst() }
        persistTabs()
    }

    func closeCurrentTab() { if let selection { close(selection) } }

    func moveTab(_ source: WorkspaceTab, over target: WorkspaceTab) {
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
        browsers[tab] = browser
    }

    func prepareCalendarReminders() {
        for account in accounts { ensureBrowser(for: WorkspaceTab(accountID: account.id, service: .calendar), account: account) }
    }

    func openCalendarNotificationSettings(account: Account) {
        select(WorkspaceTab(accountID: account.id, service: .calendar))
        currentBrowser?.load(URL(string: "https://calendar.google.com/calendar/u/0/r/settings")!)
    }

    func reopenClosedTab() {
        while let tab = recentlyClosed.popLast() {
            if accounts.contains(where: { $0.id == tab.accountID }) { select(tab); return }
        }
    }

    private func persistTabs() {
        if let data = try? JSONEncoder().encode(tabs) { preferences.set(data, forKey: "openTabs") }
    }

    func nextTab(_ delta: Int) {
        guard !tabs.isEmpty else { return }
        let index = tabs.firstIndex(where: { $0 == selection }) ?? 0
        select(tabs[(index + delta + tabs.count) % tabs.count])
    }

    func selectTab(number: Int) { if tabs.indices.contains(number - 1) { select(tabs[number - 1]) } }

    func addAccount() {
        guard storageAvailable else { return }
        editingAccount = nil
        showingAccountEditor = true
    }

    func editAccount(_ account: Account) {
        editingAccount = account
        showingAccountEditor = true
    }

    func saveAccount(_ account: Account) throws {
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
        do {
            let updated = accounts.filter { $0.id != account.id }
            try accountStore.save(updated)
            accounts = updated
            tabs.removeAll { $0.accountID == account.id }
            recentlyClosed.removeAll { $0.accountID == account.id }
            browsers = browsers.filter { $0.key.accountID != account.id }
            stores.removeValue(forKey: account.id)
            if selection?.accountID == account.id {
                browserChanges = nil
                currentBrowser = nil
                selection = nil
                if let first = tabs.first { select(first) }
            }
            persistTabs()
        } catch { errorMessage = error.localizedDescription }
    }

    func compose() {
        guard let account = selectedAccount else { addAccount(); return }
        select(WorkspaceTab(accountID: account.id, service: .gmail))
        if let compose = try? GmailCompose() { currentBrowser?.load(compose.url) }
    }

    func home() { if let selection { currentBrowser?.load(selection.service.url) } }

    func receive(_ url: URL) {
        if url.scheme?.lowercased() == "mailto" {
            do { _ = try GmailCompose(mailto: url); pendingCompose = url }
            catch { errorMessage = error.localizedDescription }
        }
        showWindow()
    }

    func composePending(with account: Account) {
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
        NSApp.activate(ignoringOtherApps: true)
    }
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
