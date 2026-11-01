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
    @ObservedObject private var security: AppSecurity
    init(model: EmbeddedWorkspace) { self.model = model; self.security = model.security }
    @Environment(\.openWindow) private var openWindow
    @State private var sidebarVisibility = NavigationSplitViewVisibility.all
    @State private var tabFrames: [WorkspaceTab: CGRect] = [:]

    var body: some View {
        Group {
            if security.blocksAccess { PINLockScreen(security: security) }
            else { workspaceContent }
        }
        .transaction { $0.disablesAnimations = security.blocksAccess }
        .onAppear {
            let action = openWindow
            model.reopenWindow = { action(id: "mailport") }
        }
    }

    private var workspaceContent: some View {
        Group {
            if model.layout == .sidebar {
                NavigationSplitView(columnVisibility: $sidebarVisibility) {
                    WorkspaceSidebar(model: model)
                } detail: { detail }
            } else {
                VStack(spacing: 0) {
                    tabs
                    Divider()
                    detail
                }
            }
        }
        .onAppear {
            let action = openWindow
            model.reopenWindow = { action(id: "mailport") }
        }
        .sheet(isPresented: $model.showingSecuritySettings, onDismiss: { model.showPendingBackup() }) { SecuritySettingsView(model: model, security: security) }
        .sheet(isPresented: $model.showingAccountEditor) { EmbeddedAccountEditor(model: model, existing: model.editingAccount) }
        .sheet(isPresented: $model.showingNotifications) { NotificationsSetup(model: model) }
        .sheet(isPresented: $model.showingHelp) { PreviewHelp() }
        .sheet(isPresented: $model.showingBackupRestore, onDismiss: { model.cancelBackupRestore() }) { WorkspaceRestoreView(model: model) }
        .sheet(isPresented: $model.showingDownloads, onDismiss: { model.completeDownloadRetry() }) { DownloadsView(model: model) }
        .sheet(isPresented: $model.showingQuickSwitch) { QuickSwitcherView(model: model) }
        .sheet(isPresented: $model.showingPinEditor) { PinEditor(model: model) }
        .sheet(isPresented: $model.showingVideoOptions, onDismiss: { model.completeVideoOptions() }) {
            if let url = model.videoOptionsURL { YouTubeResolutionView(model: model, url: url) }
        }
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
        .confirmationDialog("Remove \(model.accountPendingRemoval?.name ?? "account") from MailPort?", isPresented: Binding(get: { model.accountPendingRemoval != nil }, set: { if !$0 { model.accountPendingRemoval = nil } })) {
            Button("Remove and Keep Sign-In", role: .destructive) { if let account = model.accountPendingRemoval { model.removeAccount(account) } }
            Button("Remove and Sign Out", role: .destructive) { if let account = model.accountPendingRemoval { Task { await model.signOutAndRemoveAccount(account) } } }
        } message: { Text("Its tabs and pins are removed either way. Keeping the sign-in leaves its website data on this Mac. Signing out deletes MailPort’s cookies and website data for it. Your Google account, email, and calendar are not affected.") }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if security.didReset {
                Text("MailPort was reset after 10 incorrect PIN entries. Its local accounts and saved sign-ins have been cleared.")
                    .font(.callout).padding(12).frame(maxWidth: .infinity).background(.orange.opacity(0.1))
            }
            if let status = model.mediaStatus {
                HStack {
                    if model.savingMedia { ProgressView().controlSize(.small) }
                    Text(status).font(.callout)
                    Spacer()
                    if model.savingMedia { Button("Cancel") { model.cancelMediaDownload() } }
                    else { Button("Dismiss") { model.mediaStatus = nil } }
                }.padding(10).background(.bar)
            }
            if model.poppedOutVideo != nil && model.poppedOutVideo == model.selection {
                VStack(spacing: 16) {
                    Image(systemName: "pip").font(.system(size: 40)).foregroundStyle(.secondary)
                    Text("Video is playing in a floating window").font(.headline)
                    Button("Return Video to Tab") { model.controlVideo("popOut") }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let browser = model.currentBrowser {
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
        }
        .navigationTitle("")
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
                if let browser = model.currentBrowser, let account = model.selectedAccount, let tab = model.selection {
                    WorkspaceIdentity(browser: browser, account: account, service: tab.service)
                } else { Text("MailPort").font(.headline) }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                if model.selection?.service == .youtube {
                    Button { model.controlVideo("popOut") } label: {
                        Label(model.poppedOutVideo != nil && model.poppedOutVideo == model.selection ? "Return Video" : "Pop Out Video", systemImage: "pip.enter")
                    }.disabled(model.currentBrowser?.videoPlayback.hasVideo != true)
                        .help("Watch in a floating window above other apps")
                    Menu {
                        if model.allowsYouTubeDownloads {
                            Button("Save Video…") { model.saveMedia(audio: false) }.disabled(!model.canSaveMedia)
                            Button("Save Audio…") { model.saveMedia(audio: true) }.disabled(!model.canSaveMedia)
                            Divider()
                        }
                        Button(model.savingTranscript ? "Reading Transcript…" : "Save Transcript…") { model.saveTranscript() }
                            .disabled(!model.canSaveTranscript)
                        Divider()
                        Button { model.openVideoInYouTube() } label: { Label("Open in YouTube", systemImage: "arrow.up.right.square") }
                            .disabled(model.shareableVideoURL == nil)
                        Button { model.copyVideoLink() } label: { Label("Copy Video Link", systemImage: "link") }
                            .disabled(model.shareableVideoURL == nil)
                    } label: {
                        Label(model.savingTranscript ? "Reading Transcript…" : "Save Media", systemImage: "arrow.down.circle")
                            .labelStyle(.titleAndIcon)
                    }.help("Save media, open in YouTube, or copy the video link")
                }
                Button { model.showingPinEditor = true } label: { Label("Pin Current Page", systemImage: "pin") }
                    .disabled(!model.canPinCurrentPage).help("Pin this page to the sidebar (⌘D)")
                // Gmail has its own Compose button, so this appears only on other services.
                if model.selection != nil, model.selection?.service != .gmail, model.selection?.service != .youtube {
                    Button { model.compose() } label: { Label("New Email", systemImage: "square.and.pencil").labelStyle(.titleAndIcon) }
                        .help("Compose in Gmail (⌘N)")
                }
            }
        }
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
                                    Image(systemName: tab.service.symbol).foregroundStyle(Color(nsColor: account.nsColor)).font(.system(size: 13))
                                    Text(account.name).font(.system(size: 12, weight: model.selection == tab ? .semibold : .regular)).lineLimit(1)
                                    Text(tab.service.shortTitle).font(.system(size: 10)).foregroundStyle(.secondary)
                                    TabActivityBadge(activity: model.tabActivity[tab], service: tab.service, now: now)
                                    if let browser = model.videoBrowser(for: tab) { VideoPlayingBadge(browser: browser) }
                                    if model.accountsNeedingSignIn.contains(account.id) {
                                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(.orange)
                                            .accessibilityLabel("Sign-in needed").help("Sign-in needed")
                                    }
                                    ShortcutHint(number: model.shortcutNumber(for: tab))
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
                            .background(model.selection == tab ? Color(nsColor: account.nsColor).opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                            .overlay(alignment: .bottom) {
                                if model.selection == tab { RoundedRectangle(cornerRadius: 1).fill(Color(nsColor: account.nsColor)).frame(height: 2).padding(.horizontal, 10) }
                            }
                            .contextMenu {
                                Button("Close Tab") { model.close(tab) }
                                Divider()
                                Button("Edit \(account.name)…") { model.editAccount(account) }
                                AccountNotificationMenu(model: model, account: account, now: now)
                                Button("Remove Account…", role: .destructive) { model.accountPendingRemoval = account }
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
            Menu {
                accountServices
                if !model.accounts.isEmpty { Divider() }
                Button("Add Account…") { model.addAccount() }.disabled(!model.storageAvailable)
            } label: { Image(systemName: "plus").frame(width: 42, height: 42).contentShape(Rectangle()) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).help("Open a service or add an account")
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

private struct WorkspaceIdentity: View {
    @ObservedObject var browser: BrowserTab
    let account: Account
    let service: GoogleService
    private var host: String { browser.url?.host ?? "Loading…" }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color(nsColor: account.nsColor)).frame(width: 9, height: 9)
            VStack(spacing: 0) {
                Text("\(account.name) · \(service.title)").font(.system(size: 12, weight: .semibold)).lineLimit(1)
                // The host stays visible so sign-in pages can be checked at a glance.
                HStack(spacing: 4) {
                    Image(systemName: browser.url?.scheme == "https" ? "lock" : "globe").font(.system(size: 8))
                    Text(account.email.isEmpty ? host : "\(account.email) · \(host)").font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                }.foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: 380)
        .help(browser.url?.absoluteString ?? "")
        .accessibilityElement(children: .combine)
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
            if browser.showingFind { FindBar(browser: browser) }
            WebContent(webView: browser.webView).id(ObjectIdentifier(browser.webView))
        }
    }
}

private struct FindBar: View {
    @ObservedObject var browser: BrowserTab
    @FocusState private var focus: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in page", text: $browser.findText).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                .focused($focus)
                .onSubmit { browser.find() }
                .onChange(of: browser.findText) { _, _ in browser.find() }
            if browser.findMissed { Text("Not found").font(.caption).foregroundStyle(.secondary) }
            Button { browser.find(backwards: true) } label: { Image(systemName: "chevron.up") }
                .help("Find Previous (⇧⌘G)").accessibilityLabel("Find Previous")
            Button { browser.find() } label: { Image(systemName: "chevron.down") }
                .help("Find Next (⌘G)").accessibilityLabel("Find Next")
            Spacer()
            Button("Done") { browser.closeFind() }.keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
        .onAppear { focus = true }
        .onChange(of: browser.findFocusRequest) { _, _ in focus = true }
    }
}

private struct WebContent: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WebViewHost { WebViewHost(webView: webView) }
    func updateNSView(_ view: WebViewHost, context: Context) {}
}

struct TabActivityBadge: View {
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
