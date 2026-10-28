import AppKit
import SwiftUI
import MailPortCore

private let harborTeal = Color(nsColor: NSColor(name: "MailPortTeal") { appearance in
    let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return NSColor(srgbRed: dark ? 0.35 : 0.03, green: dark ? 0.82 : 0.43, blue: dark ? 0.77 : 0.41, alpha: 1)
})

struct WorkspaceView: View {
    @ObservedObject var model: WorkspaceModel
    @State private var removal: Account?

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 238)
            Divider()
            VStack(spacing: 0) {
                header
                Divider().opacity(0.5)
                ScrollView {
                    if let account = model.selectedAccount { dashboard(account) }
                    else { welcome }
                }
                footer
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(harborTeal)
        .sheet(isPresented: $model.showingAccountEditor) { AccountEditor(model: model, existing: model.editingAccount) }
        .sheet(isPresented: $model.showingNotifications) { NotificationSetup(model: model) }
        .sheet(isPresented: Binding(get: { model.pendingCompose != nil }, set: { if !$0 { model.pendingCompose = nil } })) {
            VStack(alignment: .leading, spacing: 20) {
                Label("Choose a sending account", systemImage: "envelope").font(.title2.bold())
                Text("The email link will open a draft in Gmail. You can review it before sending.").foregroundStyle(.secondary)
                ForEach(model.accounts) { account in
                    Button { model.openPendingCompose(account: account) } label: {
                        HStack { AccountAvatar(account: account); Text(account.name); Spacer(); Image(systemName: "arrow.up.right") }
                            .padding(8)
                    }.buttonStyle(.bordered)
                }
                if model.accounts.isEmpty { Text("Add an account to MailPort, then open the email link again.") }
                HStack { Spacer(); Button("Cancel") { model.pendingCompose = nil }.keyboardShortcut(.cancelAction) }
            }.padding(28).frame(width: 430)
        }
        .alert("MailPort needs attention", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .confirmationDialog("Remove \(removal?.name ?? "account") from MailPort?", isPresented: Binding(get: { removal != nil }, set: { if !$0 { removal = nil } })) {
            Button("Remove Account", role: .destructive) { if let removal { model.removeAccount(removal) }; removal = nil }
        } message: {
            Text("The account shortcut will be removed. Its Google sign-in stays stored on this Mac. Sign out in the Google window first if needed.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "envelope.fill").font(.system(size: 22)).foregroundStyle(harborTeal)
                Text("MailPort").font(.system(size: 22, weight: .semibold, design: .rounded))
            }.padding(.top, 49).padding(.horizontal, 23)
            Text("YOUR GOOGLE WORKSPACE").font(.system(size: 9, weight: .semibold)).tracking(1.4)
                .foregroundStyle(.secondary).padding(.top, 9).padding(.horizontal, 23)
            HStack {
                Text("ACCOUNTS").font(.system(size: 10, weight: .semibold)).tracking(1)
                Spacer()
                Text("\(model.accounts.count)").font(.caption.monospacedDigit())
            }.foregroundStyle(.secondary).padding(.horizontal, 23).padding(.top, 37).padding(.bottom, 13)
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(model.accounts) { account in
                        Button { model.selectedAccountID = account.id } label: {
                            HStack(spacing: 10) {
                                AccountAvatar(account: account)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(account.email.isEmpty ? "Google account" : account.email).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                if model.selectedAccountID == account.id { Circle().fill(harborTeal).frame(width: 6, height: 6) }
                            }.padding(11).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(model.selectedAccountID == account.id ? Color(nsColor: .controlBackgroundColor) : .clear, in: RoundedRectangle(cornerRadius: 12))
                        .contextMenu {
                            Button("Edit Account…") { model.editAccount(account) }
                            Button("Remove Account…", role: .destructive) { removal = account }
                        }
                    }
                }.padding(.horizontal, 12)
            }
            Button { model.addAccount() } label: { Label("Add account", systemImage: "plus.circle").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).padding(23).disabled(!model.storageAvailable)
            Divider().padding(.horizontal, 20)
            Button { model.showingNotifications = true } label: { Label("Notifications", systemImage: "bell").frame(maxWidth: .infinity, alignment: .leading) }
                .buttonStyle(.plain).padding(.horizontal, 23).padding(.top, 21)
            HStack(spacing: 6) {
                Image(systemName: "lock.shield").font(.system(size: 10))
                Text("Sign in directly with Google").font(.system(size: 10))
            }.foregroundStyle(.secondary).padding(.horizontal, 23).padding(.top, 14).padding(.bottom, 25)
        }
        .background(Color(nsColor: .underPageBackgroundColor).opacity(0.62))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.selectedAccount?.name ?? "Welcome aboard").font(.system(size: 14, weight: .semibold))
                Text(model.selectedAccount?.email.isEmpty == false ? model.selectedAccount!.email : "One home for your Google accounts")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.selectedAccount != nil {
                Button { model.compose() } label: { Label("Compose", systemImage: "square.and.pencil") }.buttonStyle(.bordered)
                Menu {
                    Button("Edit Account…") { if let account = model.selectedAccount { model.editAccount(account) } }
                    Button("Google Sign-in…") { model.signIn() }
                    Button("Notification Setup…") { model.showingNotifications = true }
                    Divider()
                    Button("Show Local Data Folder") { model.revealData() }
                    Button("Remove Account…", role: .destructive) { removal = model.selectedAccount }
                } label: { Image(systemName: "ellipsis.circle").font(.system(size: 17)) }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }.padding(.horizontal, 32).padding(.top, 27).padding(.bottom, 19)
    }

    private func dashboard(_ account: Account) -> some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("A little space to focus.").font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text("Your mail, your calendar, your day.").font(.system(size: 14)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "sun.horizon").font(.system(size: 42, weight: .ultraLight)).foregroundStyle(harborTeal.opacity(0.65))
            }.padding(.top, 8)
            HStack(spacing: 16) {
                serviceCard(.gmail, accent: harborTeal)
                serviceCard(.calendar, accent: Color(nsColor: .systemBlue))
            }
            Button { model.openWorkspace() } label: {
                HStack { Image(systemName: "rectangle.on.rectangle"); Text("Open Gmail & Calendar"); Spacer(); Text("⇧⌘O").foregroundStyle(.secondary) }
                    .font(.system(size: 12, weight: .medium)).padding(14)
                    .background(harborTeal.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            }.buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 14) {
                Text("THE REST OF YOUR WORKSPACE").font(.system(size: 10, weight: .semibold)).tracking(1.2).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach([GoogleService.drive, .contacts, .chat, .meet]) { service in
                        Button { model.open(service) } label: {
                            VStack(spacing: 10) {
                                Image(systemName: service.symbol).font(.system(size: 21, weight: .regular)).foregroundStyle(harborTeal)
                                Text(service.title).font(.system(size: 12, weight: .medium))
                            }.frame(maxWidth: .infinity).padding(.vertical, 19)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.primary.opacity(0.06)))
                        }.buttonStyle(.plain)
                    }
                }
            }
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "bell.badge").font(.system(size: 18)).foregroundStyle(harborTeal).padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Stay in the loop").font(.system(size: 13, weight: .semibold))
                    Text("Enable Gmail desktop alerts and Calendar notifications for this account.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Set up") { model.showingNotifications = true }.buttonStyle(.bordered)
            }.padding(18).background(Color(nsColor: .controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
            Text("Services open in focused Chrome windows. This account has its own sign-in, shared across its Google services.")
                .font(.system(size: 11)).foregroundStyle(.secondary).lineSpacing(4)
        }.padding(32)
    }

    private func serviceCard(_ service: GoogleService, accent: Color) -> some View {
        Button { model.open(service) } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: service.symbol).font(.system(size: 27, weight: .light)).foregroundStyle(accent)
                        .frame(width: 54, height: 54).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                    Spacer()
                    Text("⌘\(service.shortcutDigit)").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Text(service.title).font(.system(size: 23, weight: .semibold, design: .rounded)).padding(.top, 25)
                Text(service == .gmail ? "Your inbox, just as you like it." : "Make a little room in your day.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.top, 7)
                HStack { Text(service == .gmail ? "Open inbox" : "Open calendar"); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(accent).padding(.top, 25)
            }.padding(23).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(accent.opacity(0.16)))
        }.buttonStyle(.plain).help("Open \(service.title) in a focused window")
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            ZStack {
                RoundedRectangle(cornerRadius: 25).fill(harborTeal.opacity(0.08)).frame(width: 100, height: 100)
                Image(systemName: "envelope.open").font(.system(size: 44, weight: .ultraLight)).foregroundStyle(harborTeal)
            }.padding(.top, 24)
            Text("Your accounts.\nA calmer place to land.").font(.system(size: 38, weight: .semibold, design: .rounded)).lineSpacing(3)
            Text("Bring Gmail, Calendar, and the rest of Google together in a simple Mac workspace.")
                .font(.system(size: 15)).foregroundStyle(.secondary).lineSpacing(5).frame(maxWidth: 490, alignment: .leading)
            HStack(spacing: 22) {
                Label("Separate accounts", systemImage: "person.2")
                Label("Full Google interfaces", systemImage: "rectangle.on.rectangle")
            }.font(.system(size: 12)).foregroundStyle(.secondary)
            Button { model.addAccount() } label: {
                Label("Add your first account", systemImage: "plus").font(.system(size: 14, weight: .semibold)).padding(.horizontal, 10).padding(.vertical, 7)
            }.buttonStyle(.borderedProminent).controlSize(.large).padding(.top, 5).disabled(!model.storageAvailable)
            Text("Give the account a name, then sign in directly with Google. Gmail and Calendar open in focused Chrome windows; your sign-in is kept separate from everyday browsing.")
                .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(5).frame(maxWidth: 495, alignment: .leading)
            if model.chromeURL == nil {
                Link("Install Google Chrome to get started ↗", destination: URL(string: "https://www.google.com/chrome/")!).font(.system(size: 12, weight: .medium))
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(42)
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.up.right.square").foregroundStyle(harborTeal)
            Text(model.status).lineLimit(2)
            Spacer(minLength: 8)
            Text("APPLE SILICON").font(.system(size: 8, weight: .medium)).tracking(1).foregroundStyle(.tertiary)
        }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 30).padding(.vertical, 14)
    }
}

struct AccountAvatar: View {
    let account: Account
    var body: some View {
        Text(String(account.name.prefix(1)).uppercased()).font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(nsColor: account.color.nsColor))
            .frame(width: 33, height: 33)
            .background(Color(nsColor: account.color.nsColor).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
