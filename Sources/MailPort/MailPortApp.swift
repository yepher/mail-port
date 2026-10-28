import AppKit
import SwiftUI
import MailPortCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: WorkspaceModel? {
        didSet { queuedURLs.forEach { model?.receive($0) }; queuedURLs.removeAll() }
    }
    private var queuedURLs: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) { NSApp.setActivationPolicy(.regular) }
    func application(_ application: NSApplication, open urls: [URL]) {
        if let model { urls.forEach { model.receive($0) } }
        else { queuedURLs.append(contentsOf: urls) }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model?.showWorkspace()
        return true
    }
}

@main
struct MailPortApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = WorkspaceModel()

    var body: some Scene {
        Window("MailPort", id: "workspace") {
            WorkspaceView(model: model)
                .frame(minWidth: 920, minHeight: 650)
                .background(WindowCapture { window in model.mainWindow = window })
                .onAppear { delegate.model = model }
        }
        .defaultSize(width: 1100, height: 760)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Message") { model.compose() }.keyboardShortcut("n")
                Button("Add Account…") { model.addAccount() }.keyboardShortcut("a", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Notification Setup…") { model.showWorkspace(); model.showingNotifications = true }.keyboardShortcut(",")
            }
            CommandMenu("Workspace") {
                Button("Show MailPort") { model.showWorkspace() }.keyboardShortcut("0")
                Button("Open Gmail & Calendar") { model.openWorkspace() }.keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                ForEach(GoogleService.allCases) { service in
                    Button("Open \(service.title)") { model.open(service) }
                        .keyboardShortcut(KeyEquivalent(service.shortcutDigit.first!), modifiers: .command)
                }
                Divider()
                Button("Next Account") { model.cycleAccount(1) }.keyboardShortcut("]", modifiers: [.command, .option])
                Button("Previous Account") { model.cycleAccount(-1) }.keyboardShortcut("[", modifiers: [.command, .option])
            }
            CommandGroup(replacing: .help) {
                Button("MailPort Help") {
                    if let readme = Bundle.main.url(forResource: "README", withExtension: "md") { NSWorkspace.shared.open(readme) }
                }
            }
        }

        MenuBarExtra("MailPort", systemImage: "envelope.badge") {
            Button("Show MailPort") { model.showWorkspace() }
            Divider()
            ForEach(model.accounts) { account in
                Menu(account.name) {
                    Button("Gmail") { model.open(.gmail, account: account) }
                    Button("Calendar") { model.open(.calendar, account: account) }
                    Button("Drive") { model.open(.drive, account: account) }
                }
            }
            if model.accounts.isEmpty { Button("Add Account…") { model.showWorkspace(); model.addAccount() } }
            Divider()
            Button("Quit MailPort") { NSApp.terminate(nil) }
        }
    }
}

private struct WindowCapture: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
