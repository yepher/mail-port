import Foundation

public struct CalendarEventWindow: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init?(startMilliseconds: Double, endMilliseconds: Double) {
        guard startMilliseconds.isFinite, endMilliseconds.isFinite,
              startMilliseconds > 0, endMilliseconds > startMilliseconds,
              endMilliseconds - startMilliseconds <= 14 * 86_400_000 else { return nil }
        start = Date(timeIntervalSince1970: startMilliseconds / 1000)
        end = Date(timeIntervalSince1970: endMilliseconds / 1000)
    }

    public func contains(_ date: Date) -> Bool { start <= date && date < end }
}

public struct TabActivity: Equatable, Sendable {
    public let unreadCount: Int?
    public let events: [CalendarEventWindow]
    public let sampledAt: Date

    public init?(message: [String: Any], service: GoogleService, now: Date = Date()) {
        guard let kind = message["kind"] as? String else { return nil }
        switch (kind, service) {
        case ("unread", .gmail):
            guard let count = message["count"] as? Int, (0...1_000_000).contains(count) else { return nil }
            unreadCount = count
            events = []
        case ("calendar", .calendar):
            guard let values = message["events"] as? [[String: Double]], values.count <= 1000 else { return nil }
            var parsed: [CalendarEventWindow] = []
            for item in values {
                guard let start = item["start"], let end = item["end"],
                      let event = CalendarEventWindow(startMilliseconds: start, endMilliseconds: end) else { return nil }
                parsed.append(event)
            }
            unreadCount = nil
            events = parsed
        default: return nil
        }
        sampledAt = now
    }

    public func isFresh(at now: Date) -> Bool { (-60...300).contains(now.timeIntervalSince(sampledAt)) }
    public func hasCurrentEvent(at now: Date) -> Bool { isFresh(at: now) && events.contains { $0.contains(now) } }
    public func unreadBadge(at now: Date) -> String? {
        guard isFresh(at: now), let count = unreadCount, count > 0 else { return nil }
        return count > 999 ? "999+" : String(count)
    }
}
