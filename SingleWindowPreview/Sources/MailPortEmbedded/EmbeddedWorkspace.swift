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
    @Published var errorMessage: String?
    @Published var pendingCompose: URL?
    @Published private(set) var storageAvailable = true
    weak var mainWindow: NSWindow?

    let directory: URL
    private let accountStore: AccountStore
    private var stores: [UUID: WKWebsiteDataStore] = [:]
    private var browsers: [WorkspaceTab: BrowserTab] = [:]
    private var browserChanges: AnyCancellable?
    private var preferences: UserDefaults

    var selectedAccount: Account? { accounts.first { $0.id == selection?.accountID } }

    init() {
        let override = ProcessInfo.processInfo.environment["MAILPORT_PREVIEW_DATA_DIR"]
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        directory = override.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? support.appendingPathComponent("MailPortPreview", isDirectory: true)
        accountStore = AccountStore(directory: directory)
        preferences = override == nil ? .standard : (UserDefaults(suiteName: "com.chriswilson.mailport.embedded.testing") ?? .standard)
        do {
            if !FileManager.default.fileExists(atPath: accountStore.fileURL.path), override == nil {
                // Import account labels only. Chrome cookies and credentials stay untouched.
                let previous = AccountStore(directory: support.appendingPathComponent("MailPort", isDirectory: true))
                let labels = try previous.load()
                if !labels.isEmpty { try accountStore.save(labels) }
            }
            accounts = try accountStore.load()
            tabs = WorkspaceTab.pinnedTabs(for: accounts)
            let previousID = preferences.string(forKey: "selectedTab")
            if let tab = tabs.first(where: { $0.id == previousID }) ?? tabs.first { select(tab) }
        } catch {
            storageAvailable = false
            errorMessage = "MailPort couldn’t read the account list. Your saved files have been preserved. \(error.localizedDescription)"
        }
    }

    func select(_ tab: WorkspaceTab) {
        guard let account = accounts.first(where: { $0.id == tab.accountID }) else { return }
        if !tabs.contains(tab) { tabs.append(tab) }
        if browsers[tab] == nil {
            let store = stores[account.id] ?? WKWebsiteDataStore(forIdentifier: account.id)
            stores[account.id] = store
            let browser = BrowserTab(account: account, service: tab.service, store: store)
            browser.onMailto = { [weak self] url in self?.receive(url) }
            browsers[tab] = browser
        }
        selection = tab
        currentBrowser = browsers[tab]
        browserChanges = currentBrowser?.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        preferences.set(tab.id, forKey: "selectedTab")
    }

    func open(_ service: GoogleService) {
        guard let account = selectedAccount ?? accounts.first else { addAccount(); return }
        select(WorkspaceTab(accountID: account.id, service: service))
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
        if let index = updated.firstIndex(where: { $0.id == validated.id }) { updated[index] = validated }
        else { updated.append(validated) }
        try accountStore.save(updated)
        accounts = updated
        let extras = tabs.filter { $0.service != .gmail && $0.service != .calendar }
        tabs = WorkspaceTab.pinnedTabs(for: accounts) + extras
        showingAccountEditor = false
        select(WorkspaceTab(accountID: validated.id, service: .gmail))
    }

    func removeAccount(_ account: Account) {
        do {
            let updated = accounts.filter { $0.id != account.id }
            try accountStore.save(updated)
            accounts = updated
            tabs.removeAll { $0.accountID == account.id }
            browsers = browsers.filter { $0.key.accountID != account.id }
            stores.removeValue(forKey: account.id)
            if selection?.accountID == account.id {
                browserChanges = nil
                currentBrowser = nil
                selection = nil
                if let first = tabs.first { select(first) }
            }
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
