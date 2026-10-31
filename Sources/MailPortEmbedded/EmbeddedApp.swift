import AppKit
import SwiftUI
import WebKit
import MailPortCore

@MainActor
final class EmbeddedDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationDidBecomeActive(_ notification: Notification) {
        Task { await MailPortNotifications.shared.refresh() }
    }
    func applicationWillTerminate(_ notification: Notification) {
        if model?.security.enabled == true { model?.security.lock() }
    }
    func configureCloseShortcut() {
        // Reserve Command-W for the tab command; keep window closing available.
        DispatchQueue.main.async {
            func update(_ menu: NSMenu) {
                for item in menu.items {
                    if item.keyEquivalent == "w", item.title != "Close Tab" {
                        item.keyEquivalentModifierMask = [.command, .shift]
                    }
                    if let submenu = item.submenu { update(submenu) }
                }
            }
            if let menu = NSApp.mainMenu { update(menu) }
        }
    }
    var model: EmbeddedWorkspace? {
        didSet { queued.forEach { model?.receive($0) }; queued.removeAll() }
    }
    private var queued: [URL] = []
    func application(_ application: NSApplication, open urls: [URL]) {
        if let model { urls.forEach { model.receive($0) } } else { queued.append(contentsOf: urls) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.showWindow()
        return true
    }
}

@main
struct EmbeddedApp: App {
    @NSApplicationDelegateAdaptor(EmbeddedDelegate.self) private var delegate
    @StateObject private var model = EmbeddedWorkspace()
    @ObservedObject private var updates = AppUpdates.shared
    private var canUsePage: Bool { !model.security.blocksAccess && model.currentBrowser != nil }

    var body: some Scene {
        Window("MailPort", id: "mailport") {
            EmbeddedWorkspaceView(model: model)
                .frame(minWidth: 800, minHeight: 560)
                .background(WindowReader { window in
                    window.titleVisibility = .hidden
                    model.mainWindow = window
                })
                .onAppear { delegate.model = model; delegate.configureCloseShortcut() }
        }
        .defaultSize(width: 1380, height: 900)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            SidebarCommands()
            CommandGroup(after: .appInfo) {
                if updates.isAvailable {
                    Button("Check for Updates…") { updates.check() }.disabled(!updates.canCheck)
                }
            }
            CommandGroup(after: .sidebar) {
                Toggle("Use Tab Bar", isOn: Binding(get: { model.layout == .tabBar }, set: { model.layout = $0 ? .tabBar : .sidebar }))
                    .disabled(model.security.blocksAccess)
                Divider()
                Button("Zoom In") { model.zoom(by: 1) }.keyboardShortcut("=").disabled(!canUsePage)
                Button("Zoom Out") { model.zoom(by: -1) }.keyboardShortcut("-").disabled(!canUsePage)
                Button("Actual Size") { model.resetZoom() }.keyboardShortcut("0").disabled(!canUsePage)
            }
            CommandGroup(after: .pasteboard) {
                Divider()
                Button("Find…") { model.currentBrowser?.showFind() }.keyboardShortcut("f").disabled(!canUsePage)
                Button("Find Next") { model.currentBrowser?.find() }.keyboardShortcut("g").disabled(!canUsePage)
                Button("Find Previous") { model.currentBrowser?.find(backwards: true) }.keyboardShortcut("g", modifiers: [.command, .shift]).disabled(!canUsePage)
            }
            CommandGroup(replacing: .help) {
                Button("MailPort Help") { NSWorkspace.shared.open(URL(string: "https://github.com/yepher/mail-port#readme")!) }
            }
            CommandGroup(replacing: .printItem) {
                Button("Print…") { model.currentBrowser?.printPage() }.keyboardShortcut("p").disabled(!canUsePage)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Message") { model.compose() }.keyboardShortcut("n").disabled(model.security.blocksAccess)
                Button("Add Account…") { model.addAccount() }.keyboardShortcut("a", modifiers: [.command, .shift]).disabled(model.security.blocksAccess)
                Divider()
                Button("Close Tab") { model.closeCurrentTab() }.keyboardShortcut("w").disabled(model.security.blocksAccess || model.selection == nil)
                Button("Reopen Closed Tab") { model.reopenClosedTab() }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(model.security.blocksAccess || model.recentlyClosed.isEmpty)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { model.openSecuritySettings() }.keyboardShortcut(",")
                Button("Lock MailPort") { model.security.lock() }.keyboardShortcut("l", modifiers: [.command, .control])
                    .disabled(!model.security.enabled || model.security.blocksAccess)
                Divider()
                Button("Notifications…") { model.showWindow(); model.showingNotifications = true }.disabled(model.security.blocksAccess)
                Button("Preview Information…") { model.showingHelp = true }.disabled(model.security.blocksAccess)
            }
            CommandMenu("Tabs") {
                Button("Next Tab") { model.nextTab(1) }.keyboardShortcut("]", modifiers: [.command, .shift]).disabled(model.security.blocksAccess)
                Button("Previous Tab") { model.nextTab(-1) }.keyboardShortcut("[", modifiers: [.command, .shift]).disabled(model.security.blocksAccess)
                Divider()
                ForEach(1...9, id: \.self) { number in
                    Button("Select Tab \(number)") { model.selectTab(number: number) }
                        .keyboardShortcut(KeyEquivalent(String(number).first!), modifiers: .command).disabled(model.security.blocksAccess)
                }
            }
            CommandMenu("Navigate") {
                Button("Go To…") { model.showingQuickSwitch = true }.keyboardShortcut("t")
                    .disabled(model.security.blocksAccess || model.accounts.isEmpty)
                Button("Pin Current Page…") { model.showingPinEditor = true }.keyboardShortcut("d")
                    .disabled(model.security.blocksAccess || !model.canPinCurrentPage)
                Divider()
                Button("Reload Page") { model.currentBrowser?.reload() }.keyboardShortcut("r").disabled(model.security.blocksAccess)
                Button("Service Home") { model.home() }.keyboardShortcut("h", modifiers: [.command, .shift]).disabled(model.security.blocksAccess)
                Divider()
                ForEach(GoogleService.allCases) { service in
                    Button("Open \(service.title)") { model.open(service) }.disabled(model.security.blocksAccess)
                }
            }
        }
    }
}

private struct WindowReader: NSViewRepresentable {
    let callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { callback(window) } }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
}
