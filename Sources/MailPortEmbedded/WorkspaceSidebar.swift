import SwiftUI
import MailPortCore

struct WorkspaceSidebar: View {
    @ObservedObject var model: EmbeddedWorkspace
    @ObservedObject private var notifications = MailPortNotifications.shared

    var body: some View {
        VStack(spacing: 0) {
            Button { model.showingQuickSwitch = true } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                    Text("Go to…")
                    Spacer()
                    Text("⌘T").font(.system(size: 11)).foregroundStyle(.tertiary)
                }
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .padding(.horizontal, 9).frame(height: 28)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
            }.buttonStyle(.plain).padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 10)
                .disabled(model.accounts.isEmpty)
                .help("Go to an account, service, or pinned page")
            ScrollView {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(model.accounts) { account in
                            SidebarAccount(model: model, account: account, now: context.date)
                        }
                    }.padding(.horizontal, 10).padding(.bottom, 12)
                }
            }.scrollIndicators(.hidden)
            Divider()
            VStack(alignment: .leading, spacing: 1) {
                SidebarAction(title: "Add Account", symbol: "plus") { model.addAccount() }.disabled(!model.storageAvailable)
                if notifications.permission != "granted" {
                    SidebarAction(title: "Turn On Reminders", symbol: "bell") { model.showingNotifications = true }
                }
                SidebarAction(title: "Settings", symbol: "gearshape") { model.openSecuritySettings() }
            }.padding(8)
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 232, max: 300)
    }
}

private struct RowFrames: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct SidebarAccount: View {
    @ObservedObject var model: EmbeddedWorkspace
    let account: Account
    let now: Date
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var draggingRow: String?
    private var rowSpace: String { "rows-\(account.id.uuidString)" }
    private var color: Color { Color(nsColor: account.nsColor) }
    private var accountTabs: [WorkspaceTab] { model.navigationTabs.filter { $0.accountID == account.id } }
    private var accountPins: [WorkspacePin] { model.pins.filter { $0.accountID == account.id } }
    private var collapsed: Bool { model.collapsedAccounts.contains(account.id) }
    private var needsSignIn: Bool { model.accountsNeedingSignIn.contains(account.id) }
    private var closedServices: [GoogleService] {
        GoogleService.allCases.filter { service in !accountTabs.contains { $0.service == service } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            header
            if !collapsed {
                if needsSignIn {
                    SidebarRow(title: "Sign In", symbol: "exclamationmark.triangle.fill", color: color, selected: false, dragging: false,
                        label: "Sign in to \(account.name)", tint: .orange) { model.open(.gmail, account: account) } trailing: { EmptyView() }
                        .help("This account is signed out. Open its Mail view to sign in.")
                }
                ForEach(accountTabs) { tab in tabRow(tab) }
                if !closedServices.isEmpty { openService }
                if !accountPins.isEmpty {
                    Text("PINNED").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                        .padding(.leading, 10).padding(.top, 8).padding(.bottom, 2)
                    ForEach(accountPins) { pin in pinRow(pin) }
                }
            }
        }
        .coordinateSpace(name: rowSpace)
        .onPreferenceChange(RowFrames.self) { rowFrames = $0 }
    }

    private func tabRow(_ tab: WorkspaceTab) -> some View {
        let name = "\(account.name) \(tab.service.shortTitle)"
        let above = WorkspaceTab.neighbor(of: tab, in: model.navigationTabs, offset: -1)
        let below = WorkspaceTab.neighbor(of: tab, in: model.navigationTabs, offset: 1)
        return SidebarRow(title: tab.service.shortTitle, symbol: tab.service.symbol, color: color, selected: model.selection == tab,
            dragging: draggingRow == tab.id, label: name) { model.select(tab) } trailing: {
            TabActivityBadge(activity: model.tabActivity[tab], service: tab.service, now: now)
            if let browser = model.videoBrowser(for: tab) { VideoPlayingBadge(browser: browser) }
            ShortcutHint(number: model.shortcutNumber(for: tab))
        }
        .contextMenu {
            Button("Move Up") { if let above { withAnimation(.easeInOut(duration: 0.15)) { model.moveTab(tab, over: above) } } }.disabled(above == nil)
            Button("Move Down") { if let below { withAnimation(.easeInOut(duration: 0.15)) { model.moveTab(tab, over: below) } } }.disabled(below == nil)
            Divider()
            Button("Remove from Sidebar") { model.close(tab) }
        }
        .modifier(DraggableRow(id: tab.id, space: rowSpace, dragging: $draggingRow) { location in
            guard let target = accountTabs.first(where: { $0 != tab && rowFrames[$0.id]?.contains(location) == true }) else { return }
            withAnimation(.easeInOut(duration: 0.15)) { model.moveTab(tab, over: target) }
        })
    }

    private func pinRow(_ pin: WorkspacePin) -> some View {
        let above = WorkspacePin.neighbor(of: pin, in: model.pins, offset: -1)
        let below = WorkspacePin.neighbor(of: pin, in: model.pins, offset: 1)
        return SidebarRow(title: pin.name, symbol: pin.service.symbol, color: color, selected: false, dragging: draggingRow == pin.id.uuidString,
            label: "\(account.name) pinned \(pin.service.shortTitle) page \(pin.name)") { model.open(pin) } trailing: { EmptyView() }
        .help("\(pin.name) — \(pin.service.shortTitle)")
        .contextMenu {
            Button("Move Up") { if let above { withAnimation(.easeInOut(duration: 0.15)) { model.movePin(pin, over: above) } } }.disabled(above == nil)
            Button("Move Down") { if let below { withAnimation(.easeInOut(duration: 0.15)) { model.movePin(pin, over: below) } } }.disabled(below == nil)
            Divider()
            Button("Remove Pin") { model.removePin(pin) }
        }
        .modifier(DraggableRow(id: pin.id.uuidString, space: rowSpace, dragging: $draggingRow) { location in
            guard let target = accountPins.first(where: { $0 != pin && rowFrames[$0.id.uuidString]?.contains(location) == true }) else { return }
            withAnimation(.easeInOut(duration: 0.15)) { model.movePin(pin, over: target) }
        })
    }

    private var header: some View {
        Button { model.toggleCollapsed(account) } label: {
            HStack(spacing: 9) {
                Text(account.name.prefix(1).uppercased())
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color(nsColor: account.labelColor))
                    .frame(width: 28, height: 28).background(color, in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(account.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    if !account.email.isEmpty {
                        Text(account.email).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    }
                }
                Spacer(minLength: 4)
                if model.notificationSettings(for: account).isMuted(at: now) {
                    Image(systemName: "bell.slash").font(.system(size: 10)).foregroundStyle(.secondary)
                        .accessibilityLabel("Notifications muted").help("Notifications muted")
                }
                if collapsed, needsSignIn {
                    Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11)).foregroundStyle(.orange)
                        .accessibilityLabel("Sign-in needed").help("Sign-in needed")
                } else if collapsed, let mail = accountTabs.first(where: { $0.service == .gmail }) {
                    TabActivityBadge(activity: model.tabActivity[mail], service: .gmail, now: now)
                }
                if collapsed, let youtube = accountTabs.first(where: { $0.service == .youtube }),
                   let browser = model.videoBrowser(for: youtube) {
                    VideoPlayingBadge(browser: browser)
                }
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(collapsed ? 0 : 90))
            }.padding(.horizontal, 4).padding(.vertical, 3).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(account.name), \(collapsed ? "collapsed" : "expanded")")
        .contextMenu {
            Button("Edit \(account.name)…") { model.editAccount(account) }
            AccountNotificationMenu(model: model, account: account, now: now)
            Divider()
            Button("Remove \(account.name)…", role: .destructive) { model.accountPendingRemoval = account }
        }
    }

    private var openService: some View {
        Menu {
            ForEach(closedServices) { service in
                Button { model.open(service, account: account) } label: { Label(service.title, systemImage: service.symbol) }
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus").frame(width: 18)
                Text("Open Service")
                Spacer()
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .padding(.horizontal, 10).frame(height: 28).contentShape(Rectangle())
        }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden)
        .accessibilityLabel("Open a service for \(account.name)")
    }
}

/// Reports a row's position and passes vertical drags to `onDrag`, which decides what can be swapped.
private struct DraggableRow: ViewModifier {
    let id: String
    let space: String
    @Binding var dragging: String?
    let onDrag: (CGPoint) -> Void

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear.preference(key: RowFrames.self, value: [id: proxy.frame(in: .named(space))])
            })
            .highPriorityGesture(DragGesture(minimumDistance: 6, coordinateSpace: .named(space))
                .onChanged { value in
                    dragging = id
                    if abs(value.translation.height) > abs(value.translation.width) { onDrag(value.location) }
                }
                .onEnded { _ in dragging = nil })
    }
}

struct AccountNotificationMenu: View {
    @ObservedObject var model: EmbeddedWorkspace
    let account: Account
    let now: Date
    private var settings: AccountNotificationSettings { model.notificationSettings(for: account) }

    var body: some View {
        Menu("Notifications") {
            if settings.isMuted(at: now) {
                Button("Unmute") { model.muteNotifications(for: account, until: nil) }
            } else {
                Button("Mute for 1 Hour") { model.muteNotifications(for: account, until: now.addingTimeInterval(3600)) }
                Button("Mute Until Tomorrow") { model.muteNotifications(for: account, until: AccountNotificationSettings.tomorrowMorning(after: now)) }
                Button("Mute Until I Unmute") { model.muteNotifications(for: account, until: .distantFuture) }
            }
            Divider()
            Toggle("Hide Message Previews", isOn: Binding(get: { settings.hidesPreviews }, set: { model.setHidesPreviews($0, for: account) }))
        }
    }
}

struct ShortcutHint: View {
    let number: Int?
    var body: some View {
        if let number {
            Text("⌘\(number)").font(.system(size: 10)).monospacedDigit().foregroundStyle(.tertiary)
                .accessibilityLabel("Command \(number)")
        }
    }
}

private struct SidebarRow<Trailing: View>: View {
    let title: String
    let symbol: String
    let color: Color
    let selected: Bool
    let dragging: Bool
    let label: String
    var tint: Color?
    let action: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        // A tap gesture, not a Button, so the row's drag can start anywhere on it.
        HStack(spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: symbol).foregroundStyle(tint ?? (selected ? color : .secondary)).frame(width: 18)
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
                Spacer(minLength: 0)
            }
            trailing()
        }
        .padding(.leading, 10).padding(.trailing, 8).frame(height: 28)
        .background(selected || dragging ? color.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(label)
        .accessibilityAction { action() }
    }
}

private struct SidebarAction: View {
    let title: String
    let symbol: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 18)
                Text(title)
                Spacer()
            }
            .font(.system(size: 12)).foregroundStyle(.secondary)
            .padding(.horizontal, 6).frame(height: 26).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

struct PinEditor: View {
    @ObservedObject var model: EmbeddedWorkspace
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var focus: Bool
    private var trimmed: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Pin this page").font(.title3.bold())
            Text("It appears under \(model.selectedAccount?.name ?? "this account") in the sidebar.").font(.callout).foregroundStyle(.secondary)
            TextField("Name, such as Project Atlas", text: $name).textFieldStyle(.roundedBorder).focused($focus)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Pin") { model.pinCurrentPage(named: trimmed); dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(trimmed.isEmpty)
            }
        }.padding(24).frame(width: 380).onAppear { focus = true }
    }
}

/// Observe the page itself, so background accounts update without waiting for selection.
struct VideoPlayingBadge: View {
    @ObservedObject var browser: BrowserTab
    var body: some View {
        if browser.videoPlayback.isPlaying {
            Image(systemName: "play.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)
                .help("Playing: " + browser.title.replacingOccurrences(of: " - YouTube", with: ""))
                .accessibilityLabel("YouTube video playing: " + browser.title.replacingOccurrences(of: " - YouTube", with: ""))
        }
    }
}
