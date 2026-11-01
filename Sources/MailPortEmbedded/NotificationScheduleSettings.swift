import SwiftUI
import MailPortCore

struct NotificationScheduleSettings: View {
    @ObservedObject var model: EmbeddedWorkspace
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notification schedules", systemImage: "bell.and.waves.left.and.right").font(.headline)
            Text("Choose when each account can send Mac alerts. Times follow this Mac’s local time zone. Manual mute takes priority; skipped alerts aren’t replayed later.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(model.accounts) { account in AccountScheduleEditor(model: model, account: account) }
        }
    }
}

private struct AccountScheduleEditor: View {
    @ObservedObject var model: EmbeddedWorkspace
    let account: Account
    private var schedule: NotificationSchedule { model.notificationSettings(for: account).schedule ?? NotificationSchedule(enabled: false) }
    private func change(_ edit: (inout NotificationSchedule) -> Void) {
        var value = schedule; edit(&value); model.setNotificationSchedule(value, for: account)
    }
    private func timeBinding(start: Bool) -> Binding<Date> {
        Binding(get: {
            let minutes = start ? schedule.startMinute : schedule.endMinute
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        }, set: { date in
            let minutes = Calendar.current.component(.hour, from: date) * 60 + Calendar.current.component(.minute, from: date)
            change { if start { $0.startMinute = minutes } else { $0.endMinute = minutes } }
        })
    }
    var body: some View {
        GroupBox(account.name) {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Use notification schedule", isOn: Binding(get: { schedule.enabled }, set: { enabled in change { $0.enabled = enabled } }))
                if schedule.enabled {
                    Picker("Rule", selection: Binding(get: { schedule.mode }, set: { mode in change { $0.mode = mode } })) {
                        Text("Notify only during these hours").tag(NotificationSchedule.Mode.notifyDuring)
                        Text("Mute during these hours").tag(NotificationSchedule.Mode.muteDuring)
                    }
                    HStack(spacing: 5) {
                        ForEach(Array(Calendar.current.weekdaySymbols.enumerated()), id: \.offset) { index, name in
                            let day = index + 1
                            Toggle(isOn: Binding(get: { schedule.weekdays.contains(day) }, set: { selected in
                                change { value in
                                    if selected { value.weekdays.insert(day) }
                                    else if value.weekdays.count > 1 { value.weekdays.remove(day) }
                                }
                            })) { Text(String(name.prefix(3))) }
                            .toggleStyle(.button).help(name).accessibilityLabel(name)
                        }
                    }.controlSize(.small)
                    HStack {
                        DatePicker("From", selection: timeBinding(start: true), displayedComponents: .hourAndMinute)
                        DatePicker("To", selection: timeBinding(start: false), displayedComponents: .hourAndMinute)
                    }
                    if schedule.startMinute > schedule.endMinute {
                        Text("Ends the following day. Select the days this window starts.").font(.caption).foregroundStyle(.secondary)
                    } else if schedule.startMinute == schedule.endMinute {
                        Text("Matching times mean all day on the selected days.").font(.caption).foregroundStyle(.secondary)
                    }
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        let settings = model.notificationSettings(for: account)
                        Text(settings.isManuallyMuted(at: context.date) ? "Currently muted manually. The schedule resumes when that mute ends." : (schedule.isMuted(at: context.date) ? "Currently muted by schedule." : "Currently allowed by schedule."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button("Work: weekdays 9–5") { model.setNotificationSchedule(NotificationSchedule(), for: account) }
                    Button("Personal: outside 9–5") { model.setNotificationSchedule(NotificationSchedule(mode: .muteDuring), for: account) }
                }.controlSize(.small)
            }.padding(6)
        }
    }
}
