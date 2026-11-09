import MailPortCore
import SwiftUI
import WebKit

@main
struct MailPortMobileApp: App {
    @StateObject private var workspace = MobileWorkspace()

    var body: some Scene {
        WindowGroup { MobileRootView(workspace: workspace) }
    }
}

struct MobileRootView: View {
    @ObservedObject var workspace: MobileWorkspace
    @State private var editing: Account?
    @State private var removing: Account?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            if let tab = workspace.selection, let account = workspace.account(for: tab) {
                BrowserScreen(browser: workspace.browser(for: tab), account: account) { url, name in
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
        .sheet(item: $editing) { account in
            AccountEditor(account: account, isNew: workspace.account(forID: account.id) == nil) { try workspace.save($0) }
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
                        Label(tab.service.shortTitle, systemImage: tab.service.symbol)
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
                        Button { workspace.openPin(pin) } label: {
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
                        Menu {
                            ForEach(closed) { service in
                                Button(service.title, systemImage: service.symbol) { workspace.open(service, in: account) }
                            }
                        } label: {
                            Label("Open Service", systemImage: "plus.circle").foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    AccountHeader(account: account,
                                  edit: { editing = account },
                                  remove: { removing = account })
                }
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
    /// Saves a page under this account. False when the page can't be pinned.
    let pin: (URL, String) -> Bool
    @Environment(\.openURL) private var openURL
    @State private var pinning: URL?
    @State private var pinName = ""

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
