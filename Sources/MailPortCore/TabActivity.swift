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
    /// How long a sample can be trusted. Pages that are watched live stay near the default.
    public private(set) var lifetime: TimeInterval = 300

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

    public func isFresh(at now: Date) -> Bool { (-60...lifetime).contains(now.timeIntervalSince(sampledAt)) }

    /// The same sample, trusted until the next periodic check of an unloaded page.
    public func lasting(_ lifetime: TimeInterval) -> TabActivity {
        var sample = self
        sample.lifetime = max(lifetime, self.lifetime)
        return sample
    }
    public func hasCurrentEvent(at now: Date) -> Bool { isFresh(at: now) && events.contains { $0.contains(now) } }
    public func unreadBadge(at now: Date) -> String? { Self.badge(for: isFresh(at: now) ? (unreadCount ?? 0) : 0) }

    /// The Dock total. Stale and unknown counts are left out rather than guessed.
    public static func totalBadge(_ activity: [TabActivity], at now: Date) -> String? {
        badge(for: activity.filter { $0.isFresh(at: now) }.compactMap(\.unreadCount).reduce(0, +))
    }

    private static func badge(for count: Int) -> String? {
        guard count > 0 else { return nil }
        return count > 999 ? "999+" : String(count)
    }
}
