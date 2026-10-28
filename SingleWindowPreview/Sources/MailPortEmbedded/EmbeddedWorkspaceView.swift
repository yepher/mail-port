import AppKit
import SwiftUI
import WebKit
import MailPortCore

struct EmbeddedWorkspaceView: View {
    @ObservedObject var model: EmbeddedWorkspace
    @State private var removing: Account?

    var body: some View {
        VStack(spacing: 0) {
            tabs
            Divider()
            if let browser = model.currentBrowser {
                BrowserPane(browser: browser)
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "rectangle.stack.badge.person.crop").font(.system(size: 42, weight: .light)).foregroundStyle(.teal)
                    Text("Every account. One window.").font(.system(size: 29, weight: .semibold, design: .rounded))
                    Text("Add a Google account to open Gmail and Calendar here.").foregroundStyle(.secondary)
                    Button("Add account…") { model.addAccount() }.buttonStyle(.borderedProminent).controlSize(.large)
                    Text("This preview uses an in-app WebKit browser. Google sign-in still needs verification.")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack {
                Label("Single-window preview", systemImage: "rectangle.inset.filled").font(.system(size: 10, weight: .medium))
                Text("Google compatibility is being tested. Background notifications aren’t implemented yet.").font(.system(size: 10)).foregroundStyle(.secondary)
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
                else { Text("MailPort Preview").font(.headline) }
            }
            ToolbarItemGroup(placement: .automatic) {
                Button { model.home() } label: { Label("Inbox / Calendar Home", systemImage: "house") }.disabled(model.selection == nil)
                Button { model.compose() } label: { Label("Compose", systemImage: "square.and.pencil") }.disabled(model.selectedAccount == nil)
                Menu {
                    ForEach(GoogleService.allCases) { service in
                        Button { model.open(service) } label: { Label(service.title, systemImage: service.symbol) }
                    }
                } label: { Label("Google Apps", systemImage: "square.grid.2x2") }.disabled(model.selectedAccount == nil)
                Button { model.addAccount() } label: { Label("Add Account", systemImage: "person.crop.circle.badge.plus") }.disabled(!model.storageAvailable)
            }
        }
        .sheet(isPresented: $model.showingAccountEditor) { EmbeddedAccountEditor(model: model, existing: model.editingAccount) }
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
        .alert("MailPort Preview", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Remove \(removing?.name ?? "account") from this preview?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove Account", role: .destructive) { if let removing { model.removeAccount(removing) }; removing = nil }
        } message: { Text("Its tabs will close. Its saved website session and the original MailPort app stay intact.") }
    }

    private var tabs: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal) {
                HStack(spacing: 4) {
                    ForEach(model.tabs) { tab in
                        if let account = model.accounts.first(where: { $0.id == tab.accountID }) {
                            Button { model.select(tab) } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: tab.service.symbol).foregroundStyle(Color(nsColor: account.color.nsColor)).font(.system(size: 13))
                                    Text(account.name).font(.system(size: 12, weight: model.selection == tab ? .semibold : .regular)).lineLimit(1)
                                    Text(tab.service == .gmail ? "Mail" : tab.service.title).font(.system(size: 10)).foregroundStyle(.secondary)
                                }.padding(.horizontal, 15).frame(height: 38)
                                    .background(model.selection == tab ? Color(nsColor: account.color.nsColor).opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                                    .overlay(alignment: .bottom) {
                                        if model.selection == tab { RoundedRectangle(cornerRadius: 1).fill(Color(nsColor: account.color.nsColor)).frame(height: 2).padding(.horizontal, 10) }
                                    }.contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("\(account.name) — \(tab.service.title)")
                            .contextMenu {
                                Button("Edit \(account.name)…") { model.editAccount(account) }
                                Button("Remove Account…", role: .destructive) { removing = account }
                            }
                        }
                    }
                }.padding(.horizontal, 8).padding(.vertical, 5)
            }.scrollIndicators(.hidden)
            Divider().frame(height: 26)
            Button { model.addAccount() } label: { Image(systemName: "plus").frame(width: 42, height: 42) }
                .buttonStyle(.plain).help("Add a Google account").disabled(!model.storageAvailable)
        }.background(.bar)
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
