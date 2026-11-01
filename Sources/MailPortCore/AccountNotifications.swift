import Foundation

/// Per-account alert choices. These apply only to MailPort's Mac notifications;
/// Google's own reminder rules don't change.
public struct AccountNotificationSettings: Codable, Equatable, Sendable {
    public var mutedUntil: Date?
    public var hidesPreviews: Bool
    public var schedule: NotificationSchedule?

    public init(mutedUntil: Date? = nil, hidesPreviews: Bool = false, schedule: NotificationSchedule? = nil) {
        self.mutedUntil = mutedUntil
        self.hidesPreviews = hidesPreviews
        self.schedule = schedule
    }

    public func isManuallyMuted(at now: Date) -> Bool { mutedUntil.map { now < $0 } ?? false }

    public func isMuted(at now: Date, calendar: Calendar = .current) -> Bool {
        isManuallyMuted(at: now) || (schedule?.isMuted(at: now, calendar: calendar) ?? false)
    }

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

/// A weekly wall-clock window in the Mac's current time zone. For overnight
/// windows, a selected day owns the window that starts on that day.
public struct NotificationSchedule: Codable, Equatable, Sendable {
    public enum Mode: String, Codable, CaseIterable, Sendable { case notifyDuring, muteDuring }
    public var enabled: Bool
    public var mode: Mode
    /// Calendar weekday numbers: Sunday = 1, Saturday = 7.
    public var weekdays: Set<Int>
    public var startMinute: Int
    public var endMinute: Int

    public init(enabled: Bool = true, mode: Mode = .notifyDuring, weekdays: Set<Int> = [2, 3, 4, 5, 6], startMinute: Int = 540, endMinute: Int = 1020) {
        self.enabled = enabled; self.mode = mode; self.weekdays = weekdays
        self.startMinute = startMinute; self.endMinute = endMinute
    }
    public var isValid: Bool {
        !weekdays.isEmpty && weekdays.isSubset(of: Set(1...7)) && (0..<1440).contains(startMinute) && (0..<1440).contains(endMinute)
    }
    public func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isValid else { return false }
        let weekday = calendar.component(.weekday, from: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if startMinute == endMinute { return weekdays.contains(weekday) }
        if startMinute < endMinute { return weekdays.contains(weekday) && minute >= startMinute && minute < endMinute }
        let yesterday = calendar.date(byAdding: .day, value: -1, to: date) ?? date.addingTimeInterval(-86400)
        return (weekdays.contains(weekday) && minute >= startMinute)
            || (weekdays.contains(calendar.component(.weekday, from: yesterday)) && minute < endMinute)
    }
    public func isMuted(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled, isValid else { return false }
        return mode == .notifyDuring ? !contains(date, calendar: calendar) : contains(date, calendar: calendar)
    }

    private enum CodingKeys: String, CodingKey { case enabled, mode, weekdays, startMinute, endMinute }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decode(Bool.self, forKey: .enabled)
        mode = try c.decode(Mode.self, forKey: .mode)
        weekdays = try c.decode(Set<Int>.self, forKey: .weekdays)
        startMinute = try c.decode(Int.self, forKey: .startMinute)
        endMinute = try c.decode(Int.self, forKey: .endMinute)
        guard isValid else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid notification schedule.")) }
    }
}
