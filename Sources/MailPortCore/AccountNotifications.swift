import Foundation

/// Per-account alert choices. These apply only to MailPort's Mac notifications;
/// Google's own reminder rules don't change.
public struct AccountNotificationSettings: Codable, Equatable, Sendable {
    public var mutedUntil: Date?
    public var hidesPreviews: Bool

    public init(mutedUntil: Date? = nil, hidesPreviews: Bool = false) {
        self.mutedUntil = mutedUntil
        self.hidesPreviews = hidesPreviews
    }

    public func isMuted(at now: Date) -> Bool { mutedUntil.map { now < $0 } ?? false }

    /// With previews hidden, an alert says only what kind it is, so subjects stay off the screen.
    public func alertText(title: String, body: String, service: GoogleService) -> (title: String, body: String) {
        let generic = service == .calendar ? "Calendar reminder" : "New mail"
        if hidesPreviews { return (generic, "") }
        return (title.isEmpty ? generic : title, body)
    }

    public static func tomorrowMorning(after now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now.addingTimeInterval(86_400)
        return calendar.date(bySettingHour: 8, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }
}
