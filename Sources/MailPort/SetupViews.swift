import SwiftUI
import MailPortCore

struct AccountEditor: View {
    @ObservedObject var model: WorkspaceModel
    let existing: Account?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var email: String
    @State private var color: AccountColor
    @State private var error: String?
    @FocusState private var focusName: Bool

    init(model: WorkspaceModel, existing: Account?) {
        self.model = model
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _email = State(initialValue: existing?.email ?? "")
        _color = State(initialValue: existing?.color ?? .teal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Image(systemName: existing == nil ? "person.crop.circle.badge.plus" : "person.crop.circle").font(.system(size: 28, weight: .light)).foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 5) {
                    Text(existing == nil ? "Add a Google account" : "Edit account").font(.title2.bold())
                    Text("A separate space for work, home, or anything else.").font(.callout).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Account name").font(.callout.weight(.medium))
                TextField("Personal, Work, …", text: $name).textFieldStyle(.roundedBorder).focused($focusName)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("Email address (optional)").font(.callout.weight(.medium))
                TextField("you@gmail.com", text: $email).textFieldStyle(.roundedBorder)
                Text("A label and sign-in hint. Google checks your identity in its own window.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Text("Color").font(.callout.weight(.medium))
                ForEach(AccountColor.allCases) { candidate in
                    Button { color = candidate } label: {
                        Circle().fill(Color(nsColor: candidate.nsColor)).frame(width: 23, height: 23)
                            .overlay { if color == candidate { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }
                            .padding(3).overlay(Circle().stroke(color == candidate ? Color(nsColor: candidate.nsColor) : .clear, lineWidth: 1))
                    }.buttonStyle(.plain).accessibilityLabel(candidate.rawValue.capitalized).accessibilityAddTraits(color == candidate ? .isSelected : [])
                }
            }
            if existing == nil {
                Label("After adding the account, open Gmail and sign in. Calendar and your other services share that account’s session.", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
            } else {
                Text("Changing the label or email hint keeps the existing browser session. To use a different Google identity, sign out in its service window or add a new account.")
                    .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add account" : "Save changes") {
                    do { try model.saveAccount(Account(id: existing?.id ?? UUID(), name: name, email: email, color: color)); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(30).frame(width: 480).onAppear { focusName = true }
    }
}

struct NotificationSetup: View {
    @ObservedObject var model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            Label("Keep up with your day", systemImage: "bell.badge").font(.title2.bold())
            Text("Set up notifications in each account’s Google windows. Chrome delivers the alerts while the services are running.")
                .font(.callout).foregroundStyle(.secondary).lineSpacing(4)
            if let account = model.selectedAccount {
                Label("Setting up \(account.name)", systemImage: "person.crop.circle").font(.callout.weight(.semibold))
            } else {
                Text("Add an account first, then return here to open its settings.").font(.callout).foregroundStyle(.secondary)
            }
            instruction("1", title: "Gmail desktop notifications", text: "In Gmail’s General settings, find Desktop notifications. Enable new mail or important mail alerts, use the permission link if shown, and save changes.") {
                Button("Open Gmail settings ↗") { model.openGmailSettings() }.disabled(model.selectedAccount == nil)
            }
            instruction("2", title: "Calendar event notifications", text: "In Calendar settings, choose General → Notification settings → Desktop notifications. Check the notification rules for each calendar and allow browser notifications when asked.") {
                Button("Open Calendar settings ↗") { model.openCalendarSettings() }.disabled(model.selectedAccount == nil)
            }
            instruction("3", title: "Allow alerts on your Mac", text: "In System Settings → Notifications, allow Google Chrome alerts. Focus settings can silence them. Keep your Gmail and Calendar windows open for dependable alerts.") {
                Link("Open macOS notification settings ↗", destination: URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            }
            Text("MailPort doesn’t yet have its own unread badge, background mail checker, or notification actions. Google and Chrome control the service alerts; availability can depend on your account and browser settings.")
                .font(.caption).foregroundStyle(.secondary).lineSpacing(4)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 565)
    }

    private func instruction<Action: View>(_ number: String, title: String, text: String, @ViewBuilder action: () -> Action) -> some View {
        HStack(alignment: .top, spacing: 13) {
            Text(number).font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26).background(.teal.opacity(0.10), in: Circle()).foregroundStyle(.teal)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(.callout.weight(.semibold))
                Text(text).font(.caption).foregroundStyle(.secondary).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                action().font(.caption).buttonStyle(.link)
            }
        }
    }
}
