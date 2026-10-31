import AppKit
import SwiftUI
import MailPortCore

struct EmbeddedAccountEditor: View {
    @ObservedObject var model: EmbeddedWorkspace
    let existing: Account?
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var email: String
    @State private var color: AccountColor
    @State private var customCode: String
    @State private var error: String?
    @FocusState private var focus: Bool

    init(model: EmbeddedWorkspace, existing: Account?) {
        self.model = model
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _email = State(initialValue: existing?.email ?? "")
        _color = State(initialValue: existing?.color ?? .teal)
        _customCode = State(initialValue: existing?.hexColor?.code ?? "")
    }

    private var customColor: HexColor? { HexColor(customCode) }
    private var customCodeIsBlank: Bool { customCode.trimmingCharacters(in: .whitespaces).isEmpty }
    private var customCodeIsInvalid: Bool { !customCodeIsBlank && customColor == nil }

    /// The panel works in any color space; saved colors are always sRGB.
    private var wheelColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: customColor?.nsColor ?? color.nsColor) },
            set: { value in
                guard let picked = NSColor(value).usingColorSpace(.sRGB) else { return }
                customCode = HexColor(red: picked.redComponent, green: picked.greenComponent, blue: picked.blueComponent).code
            })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label(existing == nil ? "Add a Google account" : "Edit account", systemImage: "person.crop.circle").font(.title2.bold())
            Text("Each account gets Mail and Calendar inside this window.").font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 7) {
                Text("Account name").font(.callout.weight(.medium))
                TextField("Personal, Work, …", text: $name).textFieldStyle(.roundedBorder).focused($focus)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text("Email label (optional)").font(.callout.weight(.medium))
                TextField("you@gmail.com", text: $email).textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 13) {
                Text("Color").font(.callout.weight(.medium))
                ForEach(AccountColor.allCases) { candidate in
                    Button { color = candidate; customCode = "" } label: {
                        Circle().fill(Color(nsColor: candidate.nsColor)).frame(width: 24, height: 24)
                            .overlay { if color == candidate && customColor == nil { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white) } }
                    }.buttonStyle(.plain).accessibilityLabel(candidate.rawValue.capitalized)
                }
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text("Custom").font(.callout.weight(.medium))
                    ColorPicker("Pick a custom color", selection: wheelColor, supportsOpacity: false).labelsHidden()
                    TextField("#1A73E8", text: $customCode).textFieldStyle(.roundedBorder).frame(width: 96)
                        .accessibilityLabel("HTML color code")
                    if !customCodeIsBlank { Button("Clear") { customCode = "" }.buttonStyle(.link).font(.callout) }
                }
                if customCodeIsInvalid {
                    Text("Enter an HTML color code, such as #1A73E8 or #F80.").font(.caption).foregroundStyle(.red)
                }
            }
            Text(existing == nil ? "After adding the account, sign in on Google’s page in its Mail view. The account label does not sign you in." : "Labels and colors don’t change the Google identity already signed in here.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(existing == nil ? "Add account" : "Save") {
                    do { try model.saveAccount(Account(id: existing?.id ?? UUID(), name: name, email: email, color: color, customColor: customColor?.code)); dismiss() }
                    catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || customCodeIsInvalid)
            }
        }.padding(28).frame(width: 465).onAppear { focus = true }
            .onDisappear { NSColorPanel.shared.close() }
    }
}

struct PreviewHelp: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("Single-window preview", systemImage: "rectangle.on.rectangle").font(.title2.bold())
            Text("This build tests the layout you asked for: every account and Google service inside one MailPort window.")
                .fixedSize(horizontal: false, vertical: true)
            Group {
                Label("Google sign-in has worked on this Mac", systemImage: "person.crop.circle.badge.checkmark").font(.headline)
                Text("Sign-in has succeeded for two accounts during testing. Each account still needs its own Google sign-in, and Google may request extra verification. Passkeys require an Apple browser entitlement that this preview does not have.")
                Label("WebKit compatibility", systemImage: "globe").font(.headline)
                Text("The preview adds a conservative Safari-compatible version suffix for a recognized system WebKit build while keeping its MailPort identity. This helps website feature detection; it does not grant official Google support or additional browser capabilities.")
                Label("Sessions are separate", systemImage: "lock.shield").font(.headline)
                Text("WebKit keeps each account’s website data separate; Mail and Calendar for that account share a session. Existing single-window account sessions and tab settings are preserved as MailPort becomes the main app.")
                Label("Calendar notifications", systemImage: "bell.badge").font(.headline)
                Text("Enable native alerts from MailPort > Notifications, then choose Desktop notifications in each account’s Google Calendar settings. MailPort keeps Calendar running for reminders while the app is open. Alerts cannot arrive while the app is quit or the Mac is asleep. Native unread badges and independent background mail checks remain unfinished.")
            }.font(.callout).fixedSize(horizontal: false, vertical: true)
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(30).frame(width: 550)
    }
}
