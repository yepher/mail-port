import SwiftUI
import MailPortSecurity

struct PINLockScreen: View {
    @ObservedObject var security: AppSecurity
    @State private var pin = ""
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.shield.fill").font(.system(size: 44)).foregroundStyle(.teal)
            Text(security.erasing ? "Clearing MailPort’s local data" : "MailPort is locked").font(.title.bold())
            if security.checking { ProgressView("Checking security settings…") }
            else if security.erasing {
                if security.error == nil { ProgressView() }
                Text("The limit of 10 consecutive incorrect PINs was reached. Accounts, saved sign-ins, website data, and settings are being removed from this Mac.")
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                if security.error != nil { Button("Retry clearing local data") { security.retryErase() }.disabled(security.busy) }
            } else if !security.unavailable {
                Text("Enter your six-digit PIN to continue.").foregroundStyle(.secondary)
                SecureField("PIN", text: $pin).textFieldStyle(.roundedBorder).frame(width: 220)
                    .focused($focused).disabled(security.busy)
                            .onSubmit { unlock() }
                Button(security.busy ? "Checking…" : "Unlock") { unlock() }
                    .buttonStyle(.borderedProminent).disabled(pin.count != 6 || security.busy)
                Text(security.failures >= 9 ? "One attempt remains. Another incorrect PIN will erase all MailPort accounts and saved sign-ins on this Mac." : "10 consecutive incorrect PINs erase MailPort’s local accounts, saved sign-ins, and cached data.")
                    .font(.callout).foregroundStyle(security.failures >= 7 ? .red : .secondary).multilineTextAlignment(.center)
            }
            if let error = security.error { Text(error).font(.callout).foregroundStyle(.red).multilineTextAlignment(.center) }
            if security.unavailable { Button("Retry Keychain access") { Task { await security.reload() } }.disabled(security.busy) }
        }.padding(40).frame(maxWidth: 530).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .onAppear { focused = true }
            .onChange(of: security.isLocked) { _, _ in pin = ""; focused = true }
    }
    private func unlock() {
        guard pin.count == 6, !security.busy else { return }
        let value = pin; pin = ""
        Task { await security.unlock(pin: value); focused = true }
    }
}

struct SecuritySettingsView: View {
    @ObservedObject var model: EmbeddedWorkspace
    @ObservedObject var security: AppSecurity
    @ObservedObject private var updates = AppUpdates.shared
    @Environment(\.dismiss) private var dismiss
    @State private var wantsPIN = false
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var currentPIN = ""
    @State private var acknowledged = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("MailPort settings", systemImage: "gearshape").font(.title2.bold())
            Toggle("Show keyboard shortcuts next to views", isOn: Binding(get: { model.showsShortcutHints }, set: { model.setShowsShortcutHints($0) }))
            if updates.isAvailable {
                Toggle("Check for updates automatically", isOn: $updates.checksAutomatically)
            }
            Divider()
            Label("Security", systemImage: "lock.shield").font(.headline)
            Text("Require a PIN after your Mac sleeps and whenever MailPort launches.")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if security.enabled { enabledControls } else { setupControls }
            GroupBox {
                Text("After 10 consecutive failures, MailPort removes its local account list, Google sessions, cookies, cached website data, tab history, and settings. Your Google accounts, emails, calendar events, and files saved outside MailPort are not deleted.")
                    .font(.callout).fixedSize(horizontal: false, vertical: true).padding(8)
            }
            Text("The failure count survives restarts and resets after a correct PIN. Notifications and account pages are paused while MailPort is locked.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Text("This is an app privacy lock. It does not encrypt website data or replace macOS login security and FileVault.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error = security.error { Text(error).font(.callout).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 530)
    }
    private var enabledControls: some View {
        VStack(alignment: .leading, spacing: 12) {
                Label("PIN lock is enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                PINDigitsField(title: "Current PIN", text: $currentPIN)
                HStack {
                    Button("Turn off PIN lock") { let value = currentPIN; currentPIN = ""; Task { _ = await security.disable(pin: value) } }
                        .disabled(currentPIN.count != 6 || security.busy)
                    Button("Lock now") { security.lock() }.disabled(security.busy)
                }
        }
    }
    private var setupControls: some View {
        VStack(alignment: .leading, spacing: 12) {
                Toggle("Require a PIN after sleep", isOn: $wantsPIN)
                if wantsPIN {
                    PINDigitsField(title: "New six-digit PIN", text: $pin)
                    PINDigitsField(title: "Confirm PIN", text: $confirmation)
                    Toggle("I understand that 10 consecutive incorrect PIN entries erase MailPort’s local accounts and saved sign-ins.", isOn: $acknowledged)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(security.busy ? "Enabling…" : "Enable PIN lock") {
                        let value = pin; pin = ""; confirmation = ""
                        Task { _ = await security.enable(pin: value) }
                    }.buttonStyle(.borderedProminent)
                        .disabled(!PINCredential.isValidPIN(pin) || pin != confirmation || !acknowledged || security.busy)
                }
        }
    }

}

private struct PINDigitsField: View {
    let title: String
    @Binding var text: String
    var body: some View {
        SecureField(title, text: $text).textFieldStyle(.roundedBorder)
            .onChange(of: text) { (_: String, value: String) in
                text = String(value.filter { $0.isASCII && $0.isNumber }.prefix(6))
            }
    }
}
