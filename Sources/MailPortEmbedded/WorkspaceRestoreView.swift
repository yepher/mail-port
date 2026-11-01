import SwiftUI

struct WorkspaceRestoreView: View {
    @ObservedObject var model: EmbeddedWorkspace
    @State private var includeAppearance = false
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("Restore workspace", systemImage: "arrow.counterclockwise").font(.title2.bold())
            if let backup = model.pendingBackup {
                Text("Add \(backup.accounts.count) accounts, \(backup.tabs.count) services and \(backup.pins.count) pins as new profiles.")
                ScrollView { VStack(alignment: .leading) {
                    ForEach(backup.accounts) { account in Text(account.email.isEmpty ? account.name : "\(account.name) · \(account.email)") }
                }.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 160)
                Text("Existing accounts stay in place. Restored accounts require signing in again. Account reminder preferences and badge choices are restored; macOS permissions and YouTube opt-ins stay as they are.")
                    .font(.callout).foregroundStyle(.secondary)
                Toggle("Also restore layout, shortcut hints, zoom and video opacity", isOn: $includeAppearance)
            }
            HStack { Spacer(); Button("Cancel") { model.cancelBackupRestore() }.keyboardShortcut(.cancelAction)
                Button("Restore") { model.restoreWorkspace(includeAppearance: includeAppearance) }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 530)
    }
}
