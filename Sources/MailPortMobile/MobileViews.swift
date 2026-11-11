import MailPortCore
import SwiftUI
import WebKit

@main
struct MailPortMobileApp: App {
    @StateObject private var workspace = makeWorkspace()

    private static func makeWorkspace() -> MobileWorkspace {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--mailport-ui-test") {
            let name = "MailPortSecurityTest-ui-" + UUID().uuidString
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            let model = MobileWorkspace(directory: directory, preferences: UserDefaults(suiteName: name)!)
            model.loadsPages = false
            return model
        }
        #endif
        return MobileWorkspace()
    }

    var body: some Scene {
        WindowGroup { MobileRootView(workspace: workspace) }
        #if os(visionOS)
        .defaultSize(width: 1100, height: 800)
        #endif
    }
}

struct MobileRootView: View {
    @ObservedObject var workspace: MobileWorkspace
    @State private var editing: Account?
    @State private var removing: Account?
    @State private var openingServicesFor: Account?
    @State private var showingSettings = false
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            sidebar
        } detail: {
            if let tab = workspace.selection, let account = workspace.account(for: tab) {
                BrowserScreen(browser: workspace.browser(for: tab), account: account, showSettings: { showingSettings = true }) { url, name in
                    workspace.pin(url, named: name, in: tab) != nil
                }
                .id(tab)
            } else {
                ContentUnavailableView {
                    Label("No Accounts", systemImage: "person.crop.circle.badge.plus")
                } description: {
                    Text("Add an account, then sign in on Google's page.")
                } actions: {
                    Button("Add Account") { editing = Account(name: "") }.buttonStyle(.borderedProminent)
                }
            }
        }
        .onChange(of: workspace.selection) { _, selection in
            compactColumn = selection == nil ? .sidebar : .detail
        }
        .sheet(isPresented: $showingSettings) { MobileSettingsView(workspace: workspace) }
        .sheet(item: $editing) { account in
            AccountEditor(account: account, isNew: workspace.account(forID: account.id) == nil) { try workspace.save($0) }
        }
        .sheet(item: $openingServicesFor) { account in
            ServicePicker(account: account, services: workspace.closedServices(for: account)) { service in
                workspace.open(service, in: account)
                compactColumn = .detail
            }
        }
        .confirmationDialog("Remove \(removing?.name ?? "")?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible, presenting: removing) { account in
            Button("Remove Account", role: .destructive) { workspace.remove(account) }
        } message: { _ in
            Text("This signs the account out on this device and erases its saved pages. Your Google account isn't changed.")
        }
        .alert("MailPort", isPresented: Binding(get: { workspace.errorMessage != nil }, set: { if !$0 { workspace.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(workspace.errorMessage ?? "") }
    }

    private var sidebar: some View {
        List(selection: $workspace.selection) {
            ForEach(workspace.accounts) { account in
                Section {
                    ForEach(workspace.tabs(for: account)) { tab in
                        NavigationLink(value: tab) {
                            Label(tab.service.shortTitle, systemImage: tab.service.symbol)
                        }
                            .tag(tab)
                            .swipeActions {
                                if workspace.canClose(tab) {
                                    Button("Close", role: .destructive) { workspace.close(tab) }
                                }
                            }
                            .contextMenu {
                                if workspace.canClose(tab) {
                                    Button("Close \(tab.service.shortTitle)", systemImage: "xmark") { workspace.close(tab) }
                                }
                            }
                    }
                    ForEach(workspace.pins(for: account)) { pin in
                        Button { workspace.openPin(pin); compactColumn = .detail } label: {
                            Label {
                                Text(pin.name).foregroundStyle(.primary)
                            } icon: {
                                Image(systemName: pin.service.symbol).foregroundStyle(account.swiftUIColor)
                            }
                        }
                        .swipeActions {
                            Button("Remove", role: .destructive) { workspace.removePin(pin) }
                        }
                        .contextMenu {
                            Button("Remove Pin", systemImage: "pin.slash", role: .destructive) { workspace.removePin(pin) }
                        }
                    }
                    let closed = workspace.closedServices(for: account)
                    if !closed.isEmpty {
                        Button {
                            openingServicesFor = account
                        } label: {
                            Label("Open Service", systemImage: "plus.circle").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    AccountHeader(account: account,
                                  edit: { editing = account },
                                  remove: { removing = account })
                }
                .disabled(workspace.removingAccountIDs.contains(account.id))
            }
            Section {
                Button("Settings", systemImage: "gearshape") { showingSettings = true }
            }
        }
        .navigationTitle("MailPort")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add Account", systemImage: "person.crop.circle.badge.plus") { editing = Account(name: "") }
            }
        }
    }
}

private struct ServicePicker: View {
    let account: Account
    let services: [GoogleService]
    let open: (GoogleService) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(services.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { service in
                Button {
                    open(service)
                    dismiss()
                } label: {
                    Label(service.title, systemImage: service.symbol)
                }
            }
            .searchable(text: $search, prompt: "Find a service")
            .navigationTitle("Open Service")
            .safeAreaInset(edge: .top) { Text(account.name).font(.headline).padding(8) }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private extension MobileWorkspace {
    func account(forID id: UUID) -> Account? { accounts.first { $0.id == id } }
}

private struct AccountHeader: View {
    let account: Account
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(account.swiftUIColor).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(account.name)
                if !account.email.isEmpty { Text(account.email).font(.caption2).textCase(nil).foregroundStyle(.secondary) }
            }
            Spacer()
            Menu {
                Button("Edit Account", systemImage: "pencil", action: edit)
                Button("Remove Account", systemImage: "trash", role: .destructive, action: remove)
            } label: {
                Image(systemName: "ellipsis.circle").accessibilityLabel("\(account.name) options")
            }
        }
    }
}

struct BrowserScreen: View {
    @ObservedObject var browser: MobileBrowser
    let account: Account
    let showSettings: () -> Void
    /// Saves a page under this account. False when the page can't be pinned.
    let pin: (URL, String) -> Bool
    @Environment(\.openURL) private var openURL
    @State private var pinning: URL?
    @State private var pinName = ""
    @State private var showingDownloads = false

    var body: some View {
        WebViewContainer(webView: browser.webView)
            .ignoresSafeArea(.container, edges: .bottom)
            .overlay(alignment: .top) {
                if browser.isLoading {
                    ProgressView(value: browser.progress).progressViewStyle(.linear).tint(account.swiftUIColor)
                }
            }
            .overlay {
                if let message = browser.errorMessage {
                    ContentUnavailableView {
                        Label("Page Didn't Load", systemImage: "wifi.exclamationmark")
                    } description: { Text(message) } actions: {
                        Button("Try Again") { browser.reload() }.buttonStyle(.borderedProminent)
                    }
                    .background(.background)
                }
            }
            .navigationTitle("\(account.name) · \(browser.service.shortTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Back", systemImage: "chevron.backward") { browser.webView.goBack() }.disabled(!browser.canGoBack)
                    Button("Forward", systemImage: "chevron.forward") { browser.webView.goForward() }.disabled(!browser.canGoForward)
                    Menu {
                        Button("Reload", systemImage: "arrow.clockwise") { browser.reload() }
                        Button("Go to \(browser.service.shortTitle) Home", systemImage: "house") { browser.goHome() }
                        Button("Downloads", systemImage: "arrow.down.circle") { showingDownloads = true }
                        Button("Settings", systemImage: "gearshape", action: showSettings)
                        if let url = browser.url, WorkspacePin.canPin(url, in: browser.service) {
                            Button("Pin This Page", systemImage: "pin") {
                                pinName = String(browser.title.prefix(WorkspacePin.maximumNameLength))
                                pinning = url
                            }
                        }
                        if let url = browser.url {
                            Button("Open in Browser", systemImage: "safari") { openURL(url) }
                            ShareLink(item: url)
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .onChange(of: browser.savedDownloads.count) { old, new in if new > old { showingDownloads = true } }
            .sheet(isPresented: $showingDownloads) { MobileDownloadsView(browser: browser) }
            .alert("Download Failed", isPresented: Binding(get: { browser.downloadError != nil }, set: { if !$0 { browser.downloadError = nil } })) {
                Button("OK", role: .cancel) { browser.downloadError = nil }
            } message: { Text(browser.downloadError ?? "") }
            .alert("Pin This Page", isPresented: Binding(get: { pinning != nil }, set: { if !$0 { pinning = nil } })) {
                TextField("Name", text: $pinName)
                Button("Cancel", role: .cancel) {}
                Button("Pin") { if let url = pinning { _ = pin(url, pinName) } }
                    .disabled(pinName.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text("It appears under \(account.name) in the sidebar.")
            }
    }
}

/// Hosts a page that outlives this view, so switching services never reloads it.
struct MobileDownloadsView: View {
    @ObservedObject var browser: MobileBrowser
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if browser.activeDownloadCount > 0 {
                    ProgressView("Downloading \(browser.activeDownloadCount) files…")
                    Button("Cancel Downloads", role: .destructive) { browser.cancelDownloads() }
                }
                ForEach(browser.savedDownloads) { file in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(file.url.lastPathComponent).font(.headline)
                        ShareLink("Save or Share…", item: file.url)
                    }.swipeActions {
                        Button("Remove", role: .destructive) { browser.removeDownload(file) }
                    }
                }
                if browser.savedDownloads.isEmpty && browser.activeDownloadCount == 0 {
                    Text("Files you download from this view appear here.").foregroundStyle(.secondary)
                }
                Text("Use Save or Share to keep a file in Files. Temporary downloads are removed when you close this service or remove its account.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle("Downloads")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ container: UIView, context: Context) {
        guard webView.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        webView.removeFromSuperview()
        webView.frame = container.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        container.addSubview(webView)
    }
}

struct AccountEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var account: Account
    @State private var error: String?
    let isNew: Bool
    let save: (Account) throws -> Void

    init(account: Account, isNew: Bool, save: @escaping (Account) throws -> Void) {
        _account = State(initialValue: account)
        self.isNew = isNew
        self.save = save
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, such as Work", text: $account.name).textInputAutocapitalization(.words)
                    TextField("Email (optional)", text: $account.email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                } footer: {
                    Text("These are labels only. The Google account is whichever one you sign in to.")
                }
                Section("Color") {
                    HStack(spacing: 16) {
                        ForEach(AccountColor.allCases) { color in
                            Button {
                                account.color = color
                                account.customColor = nil
                            } label: {
                                Circle().fill(color.swiftUIColor).frame(width: 30, height: 30)
                                    .overlay { if account.customColor == nil && account.color == color { Image(systemName: "checkmark").foregroundStyle(.white).bold() } }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(color.rawValue.capitalized)
                        }
                    }
                }
                if let error { Section { Text(error).foregroundStyle(.red) } }
            }
            .navigationTitle(isNew ? "Add Account" : "Edit Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNew ? "Add" : "Save") {
                        do { try save(account); dismiss() } catch { self.error = error.localizedDescription }
                    }
                    .disabled(account.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

extension AccountColor {
    var swiftUIColor: Color {
        switch self {
        case .blue: .blue
        case .teal: .teal
        case .orange: .orange
        case .purple: .purple
        case .rose: .pink
        }
    }
}

extension Account {
    var swiftUIColor: Color {
        guard let hex = hexColor else { return color.swiftUIColor }
        return Color(red: Double(hex.red) / 255, green: Double(hex.green) / 255, blue: Double(hex.blue) / 255)
    }
}

private struct MobileSettingsView: View {
    @ObservedObject var workspace: MobileWorkspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Automatically skip skippable ads", isOn: Binding(
                        get: { workspace.skipsYouTubeAds }, set: { workspace.setSkipsYouTubeAds($0) }))
                        .accessibilityIdentifier("youtubeAutoSkipAds")
                } header: {
                    Text("YouTube · Experimental")
                } footer: {
                    Text("Tries YouTube’s Skip button when it becomes available. Some players require a manual tap on iPhone, iPad, and Apple Vision Pro. Unskippable ads still play. This setting applies to all accounts on this device.")
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
