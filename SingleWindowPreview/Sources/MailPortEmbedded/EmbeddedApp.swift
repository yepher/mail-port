import AppKit
import SwiftUI
import WebKit
import MailPortCore

@MainActor
final class EmbeddedDelegate: NSObject, NSApplicationDelegate {
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
        Window("MailPort Preview", id: "mailport") {
            EmbeddedWorkspaceView(model: model)
                .frame(minWidth: 1000, minHeight: 700)
                .background(WindowReader { model.mainWindow = $0 })
                .onAppear { delegate.model = model; delegate.configureCloseShortcut() }
        }
        .defaultSize(width: 1380, height: 900)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") { model.compose() }.keyboardShortcut("n")
                Button("Add Account…") { model.addAccount() }.keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                Button("Close Tab") { model.closeCurrentTab() }.keyboardShortcut("w").disabled(model.selection == nil)
                Button("Reopen Closed Tab") { model.reopenClosedTab() }.keyboardShortcut("t", modifiers: [.command, .shift]).disabled(model.recentlyClosed.isEmpty)
            }
            CommandGroup(replacing: .appSettings) {
                Button("Preview Information…") { model.showingHelp = true }.keyboardShortcut(",")
            }
            CommandMenu("Tabs") {
                Button("Next Tab") { model.nextTab(1) }.keyboardShortcut("]", modifiers: [.command, .shift])
                Button("Previous Tab") { model.nextTab(-1) }.keyboardShortcut("[", modifiers: [.command, .shift])
                Divider()
                ForEach(1...9, id: \.self) { number in
                    Button("Select Tab \(number)") { model.selectTab(number: number) }
                        .keyboardShortcut(KeyEquivalent(String(number).first!), modifiers: .command)
                }
            }
            CommandMenu("Navigate") {
                Button("Reload Page") { model.currentBrowser?.reload() }.keyboardShortcut("r")
                Button("Service Home") { model.home() }.keyboardShortcut("h", modifiers: [.command, .shift])
                Divider()
                ForEach(GoogleService.allCases) { service in
                    Button("Open \(service.title)") { model.open(service) }
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
