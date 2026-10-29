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

    var body: some Scene {
        Window("MailPort", id: "mailport") {
            EmbeddedWorkspaceView(model: model)
                .frame(minWidth: 1000, minHeight: 700)
                .background(WindowReader { model.mainWindow = $0 })
                .onAppear { delegate.model = model; delegate.configureCloseShortcut() }
        }
        .defaultSize(width: 1380, height: 900)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
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
