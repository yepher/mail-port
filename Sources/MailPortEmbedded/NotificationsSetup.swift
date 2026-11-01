import SwiftUI
import MailPortCore

struct NotificationsSetup: View {
    @ObservedObject var model: EmbeddedWorkspace
    @ObservedObject private var notifications = MailPortNotifications.shared
    @Environment(\.dismiss) private var dismiss
    @State private var accountID: UUID?
    @State private var enabling = false
    @State private var checkedAt = Date()

    private var account: Account? { model.accounts.first { $0.id == accountID } ?? model.selectedAccount ?? model.accounts.first }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text("Checked \(checkedAt.formatted(date: .omitted, time: .shortened))").font(.caption).foregroundStyle(.secondary)
            Label("Calendar reminders", systemImage: "bell.badge").font(.title2.bold())
            Text("Receive Google Calendar reminders as native Mac notifications. Clicking an alert opens the right account’s Calendar tab.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label(notifications.permission == "granted" ? "MailPort alerts are enabled" : "1. Allow MailPort alerts", systemImage: notifications.permission == "granted" ? "checkmark.circle.fill" : "bell")
                        .font(.headline)
                    HStack {
                        if notifications.permission == "granted" {
                            Button("Disable alerts") { notifications.disable() }
                        } else {
                            Button(enabling ? "Requesting permission…" : "Enable notifications") {
                                enabling = true
                                Task { await notifications.enable(); enabling = false }
                            }.buttonStyle(.borderedProminent).disabled(enabling)
                        }
                        Link("macOS settings ↗", destination: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
                    }
                    Text("Allow MailPort in the macOS prompt. You can choose alert style and sound in System Settings → Notifications.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Text("2. Enable desktop reminders in Google Calendar").font(.headline)
                    if !model.accounts.isEmpty {
                        Picker("Account", selection: $accountID) {
                            ForEach(model.accounts) { account in Text(account.name).tag(Optional(account.id)) }
                        }
                    }
                    Text("For each account, choose General → Notification settings → Desktop notifications. Check that the calendars and events you care about have reminder rules.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Button("Open Calendar settings") {
                        if let account { model.openCalendarNotificationSettings(account: account); dismiss() }
                    }.disabled(account == nil)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
            }
            HStack {
                Button("Send test reminder") { if let account { Task { await notifications.sendTest(account: account) } } }
                    .disabled(notifications.permission != "granted" || account == nil)
                Text("Tests Mac delivery; a real event verifies Google Calendar.").font(.caption).foregroundStyle(.secondary)
            }
            GroupBox("Account diagnostics") {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(model.accounts) { account in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(account.name).font(.headline)
                            Text(model.calendarReminderReadiness(account: account))
                            let settings = model.notificationSettings[account.id] ?? AccountNotificationSettings()
                            Text(settings.isMuted(at: Date()) ? "Reminders are muted for this account." : "Account reminders are not muted.")
                            if let receipt = notifications.receipts[account.id] {
                                if let date = receipt.submitted { Text("Calendar alert submitted: \(date.formatted())") }
                                if let date = receipt.delivered { Text("Calendar alert seen in Notification Center: \(date.formatted())") }
                                if let date = receipt.testSubmitted { Text("Test submitted: \(date.formatted())") }
                                if let date = receipt.testDelivered { Text("Test seen in Notification Center: \(date.formatted())") }
                                if let error = receipt.error { Text(error).foregroundStyle(.red) }
                            } else { Text("No alerts observed this session.") }
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Button("Refresh diagnostics") { Task { await notifications.refresh() } }
                    Text("A submitted alert is accepted by macOS; it does not prove a banner appeared. Notification Center confirmation is checked separately. Tests verify Mac delivery, not Google’s event rules. Focus can suppress banners.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(9)
            }
            if let error = notifications.lastError { Text(error).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if let delivered = notifications.lastDelivery { Text(delivered).font(.caption).foregroundStyle(.secondary) }
            Text("Calendar pages stay loaded for all saved accounts while alerts are enabled, even when a Calendar tab is closed. Keep MailPort running and signed in. Quitting, sleep, offline periods, or Focus settings can delay or prevent reminders.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28) }.frame(width: 620, height: 740)
            .task {
                while !Task.isCancelled {
                    await notifications.refreshDelivered()
                    checkedAt = Date()
                    try? await Task.sleep(for: .seconds(2))
                }
            }
            .onAppear { accountID = model.selectedAccount?.id ?? model.accounts.first?.id; Task { await notifications.refresh() } }
    }
}
