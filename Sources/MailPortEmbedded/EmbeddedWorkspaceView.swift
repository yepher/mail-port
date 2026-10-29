import AppKit
import SwiftUI
import WebKit
import MailPortCore
private struct TabFrames: PreferenceKey {
    static var defaultValue: [WorkspaceTab: CGRect] = [:]
    static func reduce(value: inout [WorkspaceTab: CGRect], nextValue: () -> [WorkspaceTab: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct EmbeddedWorkspaceView: View {
    @ObservedObject var model: EmbeddedWorkspace
    @ObservedObject private var notifications = MailPortNotifications.shared
    @Environment(\.openWindow) private var openWindow
    @State private var removing: Account?
    @State private var tabFrames: [WorkspaceTab: CGRect] = [:]

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider()
            if let browser = model.currentBrowser {
                BrowserPane(browser: browser)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "rectangle.stack.badge.person.crop").font(.system(size: 42, weight: .light)).foregroundStyle(.teal)
                    Text(model.accounts.isEmpty ? "Every account. One window." : "All tabs are closed.").font(.system(size: 29, weight: .semibold, design: .rounded))
                    if model.accounts.isEmpty {
                        Text("Add a Google account to open Gmail and Calendar here.").foregroundStyle(.secondary)
                        Button("Add account…") { model.addAccount() }.buttonStyle(.borderedProminent).controlSize(.large)
                    } else {
                        Text("Your accounts are still available. Choose a service to open a tab.").foregroundStyle(.secondary)
                        Menu("Open a tab") { accountServices }.menuStyle(.borderedButton).controlSize(.large)
                        if !model.recentlyClosed.isEmpty { Button("Reopen closed tab") { model.reopenClosedTab() } }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Label("Single-window preview", systemImage: "rectangle.inset.filled").font(.system(size: 10, weight: .medium))
                Text(notifications.permission == "granted" ? "Calendar reminders enabled while MailPort is running." : "Enable notifications for Calendar reminders.").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Details") { model.showingHelp = true }.buttonStyle(.link).font(.system(size: 10))
            }.padding(.horizontal, 14).padding(.vertical, 7).background(.bar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { model.currentBrowser?.back() } label: { Label("Back", systemImage: "chevron.left") }
                    .disabled(model.currentBrowser?.canGoBack != true)
                Button { model.currentBrowser?.forward() } label: { Label("Forward", systemImage: "chevron.right") }
                    .disabled(model.currentBrowser?.canGoForward != true)
                Button { model.currentBrowser?.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                    .disabled(model.currentBrowser == nil)
            }
            ToolbarItem(placement: .principal) {
                if let browser = model.currentBrowser { BrowserLocation(browser: browser) }
                else { Text("MailPort").font(.headline) }
            }
            ToolbarItemGroup(placement: .automatic) {
                Button { model.showingNotifications = true } label: { Label("Notifications", systemImage: notifications.permission == "granted" ? "bell.badge" : "bell") }
                Button { model.home() } label: { Label("Inbox / Calendar Home", systemImage: "house") }.disabled(model.selection == nil)
                Button { model.compose() } label: { Label("Compose", systemImage: "square.and.pencil") }.disabled(model.selectedAccount == nil)
                Menu {
                    if let account = model.selectedAccount {
                        ForEach(GoogleService.allCases) { service in
                            Button { model.open(service, account: account) } label: { Label(service.title, systemImage: service.symbol) }
                        }
                        Divider()
                    }
                    accountServices
                } label: { Label("Google Apps", systemImage: "square.grid.2x2") }.disabled(model.accounts.isEmpty)
                Button { model.addAccount() } label: { Label("Add Account", systemImage: "person.crop.circle.badge.plus") }.disabled(!model.storageAvailable)
            }
        }
        .onAppear {
            let action = openWindow
            model.reopenWindow = { action(id: "mailport") }
        }
        .sheet(isPresented: $model.showingAccountEditor) { EmbeddedAccountEditor(model: model, existing: model.editingAccount) }
        .sheet(isPresented: $model.showingNotifications) { NotificationsSetup(model: model) }
        .sheet(isPresented: $model.showingHelp) { PreviewHelp() }
        .sheet(isPresented: Binding(get: { model.pendingCompose != nil }, set: { if !$0 { model.pendingCompose = nil } })) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Choose a sending account").font(.title2.bold())
                Text("Open this email link as a draft. Gmail will let you review it before sending.").foregroundStyle(.secondary)
                ForEach(model.accounts) { account in
                    Button(account.name) { model.composePending(with: account) }.buttonStyle(.bordered)
                }
                if model.accounts.isEmpty { Text("Add an account, then open the link again.") }
                HStack { Spacer(); Button("Cancel") { model.pendingCompose = nil }.keyboardShortcut(.cancelAction) }
            }.padding(28).frame(width: 430)
        }
        .alert("MailPort", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Remove \(removing?.name ?? "account") from this preview?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove Account", role: .destructive) { if let removing { model.removeAccount(removing) }; removing = nil }
        } message: { Text("Its tabs will close. Its saved website session and the original MailPort app stay intact.") }
    }

    private var tabs: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            tabStrip(at: context.date)
        }
    }

    private func tabStrip(at now: Date) -> some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(model.tabs) { tab in
                        if let account = model.accounts.first(where: { $0.id == tab.accountID }) {
                            HStack(spacing: 0) {
                              HStack(spacing: 8) {
                                    Image(systemName: tab.service.symbol).foregroundStyle(Color(nsColor: account.color.nsColor)).font(.system(size: 13))
                                    Text(account.name).font(.system(size: 12, weight: model.selection == tab ? .semibold : .regular)).lineLimit(1)
                                    Text(tab.service == .gmail ? "Mail" : tab.service.title).font(.system(size: 10)).foregroundStyle(.secondary)
                                    TabActivityBadge(activity: model.tabActivity[tab], service: tab.service, now: now)
                              }.padding(.leading, 13).padding(.trailing, 8).frame(height: 38).contentShape(Rectangle())
                                .onTapGesture { model.select(tab) }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { model.select(tab) }
                                .help("\(account.name) — \(tab.service.title)")
                              Button { model.close(tab) } label: {
                                  Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                                      .foregroundStyle(.secondary).frame(width: 26, height: 30).contentShape(Rectangle())
                              }.buttonStyle(.plain).padding(.trailing, 4)
                                  .help("Close \(account.name) — \(tab.service.title)")
                                  .accessibilityLabel("Close \(account.name) \(tab.service.title) tab")
                            }
                            .background(model.selection == tab ? Color(nsColor: account.color.nsColor).opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .bottom) {
                                if model.selection == tab { RoundedRectangle(cornerRadius: 1).fill(Color(nsColor: account.color.nsColor)).frame(height: 2).padding(.horizontal, 10) }
                            }
                            .contextMenu {
                                Button("Close Tab") { model.close(tab) }
                                Divider()
                                Button("Edit \(account.name)…") { model.editAccount(account) }
                                Button("Remove Account…", role: .destructive) { removing = account }
                            }
                            .background(GeometryReader { proxy in
                                Color.clear.preference(key: TabFrames.self, value: [tab: proxy.frame(in: .named("tabStrip"))])
                            })
                            .highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named("tabStrip"))
                                .onChanged { value in
                                    guard abs(value.translation.width) > abs(value.translation.height),
                                          let target = model.tabs.first(where: { $0 != tab && tabFrames[$0]?.contains(value.location) == true }) else { return }
                                    withAnimation(.easeInOut(duration: 0.15)) { model.moveTab(tab, over: target) }
                                })
                        }
                    }
                }.padding(.horizontal, 8).padding(.vertical, 5)
            }.scrollIndicators(.hidden)
                .coordinateSpace(name: "tabStrip")
                .onPreferenceChange(TabFrames.self) { tabFrames = $0 }
            Divider().frame(height: 26)
            Button { model.addAccount() } label: { Image(systemName: "plus").frame(width: 42, height: 42) }
                .buttonStyle(.plain).help("Add a Google account").disabled(!model.storageAvailable)
        }.background(.bar)
    }

    @ViewBuilder private var accountServices: some View {
        ForEach(model.accounts) { account in
            Menu(account.name) {
                ForEach(GoogleService.allCases) { service in
                    Button { model.open(service, account: account) } label: { Label(service.title, systemImage: service.symbol) }
                }
            }
        }
    }
}

private struct BrowserLocation: View {
    @ObservedObject var browser: BrowserTab
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: browser.url?.scheme == "https" ? "lock" : "globe").font(.system(size: 10))
            Text(browser.url?.host ?? "Loading…").font(.system(size: 11)).lineLimit(1)
        }.foregroundStyle(.secondary).help(browser.url?.absoluteString ?? "")
    }
}

private struct BrowserPane: View {
    @ObservedObject var browser: BrowserTab
    var body: some View {
        VStack(spacing: 0) {
            if browser.isLoading { ProgressView(value: browser.estimatedProgress).progressViewStyle(.linear).frame(height: 2) }
            if let error = browser.errorMessage {
                HStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                    Text(error).font(.caption).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("Reload") { browser.reload() }
                }.padding(12).background(.orange.opacity(0.08))
            }
            WebContent(webView: browser.webView).id(ObjectIdentifier(browser.webView))
        }
    }
}

private struct WebContent: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}

private struct TabActivityBadge: View {
    let activity: TabActivity?
    let service: GoogleService
    let now: Date
    private var unreadLabel: String {
        let count = activity?.unreadCount ?? 0
        return "\(count) unread \(count == 1 ? "message" : "messages")"
    }

    var body: some View {
        if service == .gmail, let badge = activity?.unreadBadge(at: now) {
            Text(badge).font(.system(size: 10, weight: .bold)).monospacedDigit()
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.primary.opacity(0.14), in: Capsule())
                .accessibilityLabel(unreadLabel)
                .help(unreadLabel + " in inbox")
        } else if service == .calendar, activity?.hasCurrentEvent(at: now) == true {
            Circle().fill(.green).frame(width: 7, height: 7)
                .accessibilityLabel("Event in progress")
                .help("An event is happening now")
        }
    }
}
