import AppKit
import Combine
import MailPortCore

@MainActor
final class WorkspaceModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published var selectedAccountID: UUID? {
        didSet { preferences.set(selectedAccountID?.uuidString, forKey: "selectedAccount") }
    }
    @Published var showingAccountEditor = false
    @Published var editingAccount: Account?
    @Published var showingNotifications = false
    @Published var errorMessage: String?
    @Published var status = "Choose a service to open a focused window."
    @Published var pendingCompose: URL?
    @Published private(set) var storageAvailable = true
    weak var mainWindow: NSWindow?

    let directory: URL
    let profilesDirectory: URL
    private let store: AccountStore
    private let preferences: UserDefaults
    private var processes: [UUID: Process] = [:]
    private var openingWorkspaces = Set<UUID>()

    var selectedAccount: Account? { accounts.first { $0.id == selectedAccountID } }
    var chromeURL: URL? {
        let candidates = [
            URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Google Chrome.app")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.appendingPathComponent("Contents/MacOS/Google Chrome").path) }
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome")
    }

    init() {
        let override = ProcessInfo.processInfo.environment["MAILPORT_DATA_DIR"]
        directory = override.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MailPort", isDirectory: true)
        profilesDirectory = directory.appendingPathComponent("BrowserProfiles", isDirectory: true)
        store = AccountStore(directory: directory)
        // The application's own bundle ID is not a separate preferences suite.
        // UserDefaults(suiteName:) can return nil for that domain on macOS.
        if override == nil { preferences = .standard }
        else { preferences = UserDefaults(suiteName: "com.chriswilson.mailport.testing") ?? .standard }
        selectedAccountID = preferences.string(forKey: "selectedAccount").flatMap(UUID.init(uuidString:))
        do {
            accounts = try store.load()
            if !accounts.contains(where: { $0.id == selectedAccountID }) { selectedAccountID = accounts.first?.id }
        } catch {
            storageAvailable = false
            errorMessage = "MailPort couldn’t read your account list. Your saved data has been preserved. \(error.localizedDescription)"
        }
    }

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
        try store.save(updated)
        accounts = updated
        selectedAccountID = validated.id
        showingAccountEditor = false
    }

    func removeAccount(_ account: Account) {
        do {
            let updated = accounts.filter { $0.id != account.id }
            try store.save(updated)
            accounts = updated
            if selectedAccountID == account.id { selectedAccountID = accounts.first?.id }
            status = "Account removed from the workspace. Its browser session is still stored on this Mac."
        } catch { errorMessage = error.localizedDescription }
    }

    func cycleAccount(_ offset: Int) {
        guard !accounts.isEmpty else { return }
        let index = accounts.firstIndex { $0.id == selectedAccountID } ?? 0
        selectedAccountID = accounts[(index + offset + accounts.count) % accounts.count].id
    }

    func open(_ service: GoogleService, account: Account? = nil) {
        guard let account = account ?? selectedAccount else { addAccount(); return }
        launch(service.url, account: account, description: service.title)
    }

    func openWorkspace() {
        guard let account = selectedAccount else { addAccount(); return }
        guard !openingWorkspaces.contains(account.id) else { return }
        guard chromeURL != nil else { open(.gmail); return }
        openingWorkspaces.insert(account.id)
        launch(GoogleService.gmail.url, account: account, description: "Gmail")
        // A fresh Chrome profile needs time to create its singleton socket before
        // another process can hand it a second app window.
        let socket = profilesDirectory.appendingPathComponent(account.id.uuidString).appendingPathComponent("SingletonSocket")
        Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.openingWorkspaces.remove(account.id) }
            for _ in 0..<40 {
                if FileManager.default.fileExists(atPath: socket.path) { break }
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
            guard self.accounts.contains(where: { $0.id == account.id }) else { return }
            self.launch(GoogleService.calendar.url, account: account, description: "Calendar")
        }
    }

    func compose() {
        guard let account = selectedAccount else { addAccount(); return }
        var components = URLComponents(url: GoogleService.gmail.url, resolvingAgainstBaseURL: false)!
        components.fragment = nil
        components.queryItems = [URLQueryItem(name: "view", value: "cm"), URLQueryItem(name: "fs", value: "1")]
        if let url = components.url { launch(url, account: account, description: "New message") }
    }

    func receive(_ url: URL) {
        if url.scheme?.lowercased() == "mailto" {
            do {
                _ = try GmailCompose(mailto: url)
                pendingCompose = url
            } catch { errorMessage = "This email link couldn’t be opened. \(error.localizedDescription)" }
        }
        showWorkspace()
    }

    func openPendingCompose(account: Account) {
        guard let url = pendingCompose else { return }
        do {
            let compose = try GmailCompose(mailto: url)
            launch(compose.url, account: account, description: "New message")
            pendingCompose = nil
        } catch { errorMessage = error.localizedDescription }
    }

    func signIn() {
        guard let account = selectedAccount else { return }
        var url = URLComponents(string: "https://accounts.google.com/ServiceLogin")!
        url.queryItems = [URLQueryItem(name: "continue", value: GoogleService.gmail.url.absoluteString)]
        if !account.email.isEmpty { url.queryItems?.append(URLQueryItem(name: "Email", value: account.email)) }
        if let url = url.url { launch(url, account: account, description: "Google sign-in") }
    }

    func openGmailSettings() {
        guard let account = selectedAccount else { return }
        launch(URL(string: "https://mail.google.com/mail/u/0/#settings/general")!, account: account, description: "Gmail settings")
    }

    func openCalendarSettings() {
        guard let account = selectedAccount else { return }
        launch(URL(string: "https://calendar.google.com/calendar/u/0/r/settings")!, account: account, description: "Calendar settings")
    }

    func revealData() { NSWorkspace.shared.open(directory) }

    func showWorkspace() {
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func launch(_ url: URL, account: Account, description: String) {
        guard let chromeURL else {
            errorMessage = "Install Google Chrome in Applications to open your Google services. MailPort uses Chrome for sign-in and focused service windows."
            return
        }
        do {
            let plan = try BrowserLaunchPlan(account: account, url: url, profilesDirectory: profilesDirectory)
            try FileManager.default.createDirectory(at: plan.profileDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let process = Process()
            process.executableURL = chromeURL.appendingPathComponent("Contents/MacOS/Google Chrome")
            process.arguments = plan.arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let launchID = UUID()
            process.terminationHandler = { [weak self] finished in
                let code = finished.terminationStatus
                Task { @MainActor in
                    self?.processes.removeValue(forKey: launchID)
                    if code != 0 { self?.errorMessage = "Chrome couldn’t open \(description) (exit \(code)). Check that Chrome opens normally, then try again." }
                }
            }
            try process.run()
            processes[launchID] = process
            status = "Opened \(description) for \(account.name). Sign in to Google in the service window if asked."
        } catch { errorMessage = "Couldn’t open \(description). \(error.localizedDescription)" }
    }
}

extension AccountColor {
    var nsColor: NSColor {
        switch self {
        case .blue: return .systemBlue
        case .teal: return .systemTeal
        case .orange: return .systemOrange
        case .purple: return .systemPurple
        case .rose: return .systemPink
        }
    }
}
