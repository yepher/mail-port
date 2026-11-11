import Combine
import MailPortCore
import OSLog
import UIKit
import WebKit

/// Accounts, their open services, and the pages behind them.
@MainActor
final class MobileWorkspace: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var tabs: [WorkspaceTab] = []
    @Published private(set) var pins: [WorkspacePin] = []
    @Published var selection: WorkspaceTab? { didSet { persistSelection() } }
    @Published var errorMessage: String?
    @Published private(set) var skipsYouTubeAds = false
    @Published private(set) var storageAvailable = true
    @Published private(set) var removingAccountIDs: Set<UUID> = []

    /// Off in tests, so nothing reaches the network.
    var loadsPages = true
    private let accountStore: AccountStore
    private let preferences: UserDefaults
    private var stores: [UUID: WKWebsiteDataStore] = [:]
    private var browsers: [WorkspaceTab: MobileBrowser] = [:]
    private var memoryWarning: AnyCancellable?
    private let logger = Logger(subsystem: "com.chriswilson.mailport.mobile", category: "Workspace")

    init(directory: URL? = nil, preferences: UserDefaults = .standard) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        accountStore = AccountStore(directory: directory ?? support.appendingPathComponent("MailPortPreview", isDirectory: true))
        self.preferences = preferences
        skipsYouTubeAds = preferences.bool(forKey: "youtubeAutoSkipAds")
        do { accounts = try accountStore.load() } catch {
            storageAvailable = false
            errorMessage = "MailPort couldn't read your saved accounts. \(error.localizedDescription)"
        }
        let saved = preferences.data(forKey: Keys.tabs).flatMap { try? JSONDecoder().decode([WorkspaceTab].self, from: $0) } ?? []
        let ids = Set(accounts.map(\.id))
        var seenTabs: Set<WorkspaceTab> = []
        tabs = WorkspaceTab.grouped(saved.filter { ids.contains($0.accountID) && seenTabs.insert($0).inserted }, by: accounts)
        // Every account always has Mail and Calendar.
        for tab in WorkspaceTab.pinnedTabs(for: accounts) where !tabs.contains(tab) { tabs.append(tab) }
        tabs = WorkspaceTab.grouped(tabs, by: accounts)
        let savedPins = preferences.data(forKey: Keys.pins).flatMap { try? JSONDecoder().decode([WorkspacePin].self, from: $0) } ?? []
        pins = savedPins.filter { $0.isValid && ids.contains($0.accountID) }
        let savedSelection = preferences.data(forKey: Keys.selection).flatMap { try? JSONDecoder().decode(WorkspaceTab.self, from: $0) }
        selection = savedSelection.flatMap { tabs.contains($0) ? $0 : nil } ?? tabs.first
        memoryWarning = NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.releaseBackgroundPages() } }
    }

    func account(for tab: WorkspaceTab) -> Account? { accounts.first { $0.id == tab.accountID } }

    func tabs(for account: Account) -> [WorkspaceTab] { tabs.filter { $0.accountID == account.id } }

    func pins(for account: Account) -> [WorkspacePin] { pins.filter { $0.accountID == account.id } }

    func closedServices(for account: Account) -> [GoogleService] {
        GoogleService.allCases.filter { !tabs.contains(WorkspaceTab(accountID: account.id, service: $0)) }
    }

    /// The page for a tab, made the first time it's shown.
    func browser(for tab: WorkspaceTab) -> MobileBrowser {
        if let browser = browsers[tab] { return browser }
        let browser = MobileBrowser(tab: tab, store: dataStore(for: tab.dataStoreIdentifier), loadsInitialPage: loadsPages)
        browser.onOpenInService = { [weak self] service, url in self?.open(service, url: url, accountID: tab.accountID) ?? false }
        browser.skipsYouTubeAds = skipsYouTubeAds
        browsers[tab] = browser
        return browser
    }

    func setSkipsYouTubeAds(_ enabled: Bool) {
        skipsYouTubeAds = enabled
        preferences.set(enabled, forKey: "youtubeAutoSkipAds")
        for browser in browsers.values { browser.skipsYouTubeAds = enabled }
    }

    // MARK: Accounts

    func save(_ account: Account) throws {
        guard storageAvailable else { throw CocoaError(.fileReadCorruptFile) }
        guard !removingAccountIDs.contains(account.id) else { throw CocoaError(.userCancelled) }
        let account = try account.validated()
        var updated = accounts
        if let index = updated.firstIndex(where: { $0.id == account.id }) { updated[index] = account } else { updated.append(account) }
        try accountStore.save(updated)
        let isNew = !accounts.contains { $0.id == account.id }
        accounts = updated
        if isNew {
            tabs.append(contentsOf: WorkspaceTab.pinnedTabs(for: [account]))
            persistTabs()
            selection = WorkspaceTab(accountID: account.id, service: .gmail)
        }
    }

    /// Removes the account and erases its sign-in and site data from this device.
    func remove(_ account: Account) {
        guard storageAvailable, accounts.contains(where: { $0.id == account.id }),
              removingAccountIDs.insert(account.id).inserted else { return }
        let previousSelection = selection
        if selection?.accountID == account.id { selection = nil }
        for tab in Array(browsers.keys) where tab.accountID == account.id {
            browsers.removeValue(forKey: tab)?.discard()
        }
        stores.removeValue(forKey: account.id)
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.removingAccountIDs.remove(account.id) }
            // Let the detail view release its WebView before removing the store.
            await withCheckedContinuation { continuation in
                DispatchQueue.main.async { continuation.resume() }
            }
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: account.id)
                let remaining = self.accounts.filter { $0.id != account.id }
                try self.accountStore.save(remaining)
                self.accounts = remaining
                self.tabs.removeAll { $0.accountID == account.id }
                self.pins.removeAll { $0.accountID == account.id }
                self.persistTabs(); self.persistPins()
                if self.selection == nil { self.selection = self.tabs.first }
            } catch {
                self.errorMessage = "MailPort couldn't finish removing \(account.name). Try Remove Account again. \(error.localizedDescription)"
                if self.selection == nil { self.selection = previousSelection }
            }
        }
    }

    // MARK: Services

    func open(_ service: GoogleService, in account: Account) {
        guard storageAvailable, !removingAccountIDs.contains(account.id), accounts.contains(where: { $0.id == account.id }) else { return }
        let tab = WorkspaceTab(accountID: account.id, service: service)
        if !tabs.contains(tab) {
            let last = tabs.lastIndex { $0.accountID == account.id }.map { $0 + 1 } ?? tabs.endIndex
            tabs.insert(tab, at: last)
            persistTabs()
        }
        selection = tab
    }

    /// Mail and Calendar stay; other services can be closed.
    func canClose(_ tab: WorkspaceTab) -> Bool { tab.service != .gmail && tab.service != .calendar }

    func close(_ tab: WorkspaceTab) {
        guard canClose(tab) else { return }
        let next = WorkspaceTab.selection(afterClosing: tab, in: tabs, selected: selection)
        tabs.removeAll { $0 == tab }
        browsers.removeValue(forKey: tab)?.discard()
        persistTabs()
        selection = next
    }

    // MARK: Pins

    /// Saves the page under its account. Nil when the page can't be pinned, such as a sign-in page.
    @discardableResult
    func pin(_ url: URL, named name: String, in tab: WorkspaceTab) -> WorkspacePin? {
        guard storageAvailable, !removingAccountIDs.contains(tab.accountID), tabs.contains(tab), let pin = WorkspacePin(accountID: tab.accountID, service: tab.service, name: name, url: url) else { return nil }
        let last = pins.lastIndex { $0.accountID == tab.accountID }.map { $0 + 1 } ?? pins.endIndex
        pins.insert(pin, at: last)
        persistPins()
        return pin
    }

    func openPin(_ pin: WorkspacePin) {
        guard let account = accounts.first(where: { $0.id == pin.accountID }) else { return }
        open(pin.service, in: account)
        browser(for: WorkspaceTab(accountID: account.id, service: pin.service)).load(pin.url)
    }

    func removePin(_ pin: WorkspacePin) {
        pins.removeAll { $0.id == pin.id }
        persistPins()
    }

    private func open(_ service: GoogleService, url: URL, accountID: UUID) -> Bool {
        guard !removingAccountIDs.contains(accountID), let account = accounts.first(where: { $0.id == accountID }) else { return false }
        open(service, in: account)
        browser(for: WorkspaceTab(accountID: accountID, service: service)).load(url)
        return true
    }

    // MARK: Memory

    /// iOS warns before it starts ending apps. Pages not on screen reload when next shown.
    func releaseBackgroundPages() {
        let released = browsers.filter { $0.key != selection && !$0.value.keepsBackgroundPage }
        logger.notice("Memory warning: releasing \(released.count) background pages")
        for (tab, browser) in released {
            browser.discard()
            browsers.removeValue(forKey: tab)
        }
    }

    // MARK: Persistence

    private func dataStore(for id: UUID) -> WKWebsiteDataStore {
        if let store = stores[id] { return store }
        let store = WKWebsiteDataStore(forIdentifier: id)
        stores[id] = store
        return store
    }

    private func persistTabs() {
        if let data = try? JSONEncoder().encode(tabs) { preferences.set(data, forKey: Keys.tabs) }
    }

    private func persistPins() {
        if let data = try? JSONEncoder().encode(pins) { preferences.set(data, forKey: Keys.pins) }
    }

    private func persistSelection() {
        if let selection, let data = try? JSONEncoder().encode(selection) {
            preferences.set(data, forKey: Keys.selection)
        } else {
            preferences.removeObject(forKey: Keys.selection)
        }
    }

    private enum Keys {
        static let tabs = "mobileTabs"
        static let selection = "mobileSelection"
        static let pins = "mobilePins"
    }
}
