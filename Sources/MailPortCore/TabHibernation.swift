import Foundation

/// Decides which background pages can unload to save memory, and how often an
/// unloaded page is briefly reopened so its counts and alerts keep working.
public enum TabHibernation {
    public static let defaultIdleMinutes = 30
    public static let idleChoices = [15, 30, 60, 120]
    /// How soon idle pages unload while macOS reports memory pressure.
    public static let pressuredIdleLimit: TimeInterval = 5 * 60
    /// A check needs long enough for the page to render its real counts.
    public static let checkDuration: TimeInterval = 45

    public struct PageState: Sendable {
        public var isSelected = false
        public var isDetached = false
        public var isPlaying = false
        public var isCapturing = false
        public var isDownloading = false
        public var isLoading = false
        public var needsSignIn = false
        /// Calendar reminders only fire from a loaded page.
        public var deliversReminders = false
        public init() {}
    }

    public static func shouldHibernate(_ service: GoogleService, idleFor idle: TimeInterval,
        limit: TimeInterval, state: PageState) -> Bool {
        canHibernate(service, state: state) && idle >= limit
    }

    /// Whatever is on screen or in use stays, however long it has been idle.
    public static func canHibernate(_ service: GoogleService, state: PageState) -> Bool {
        service.canHibernate && !state.isSelected && !state.isDetached && !state.isPlaying
            && !state.isCapturing && !state.isDownloading && !state.isLoading
            && !state.needsSignIn && !state.deliversReminders
    }

    /// Mail is checked more often than the day's events change. Low Power Mode doubles both.
    public static func checkInterval(for service: GoogleService, lowPower: Bool) -> TimeInterval {
        (service == .calendar ? 15 * 60 : 5 * 60) * (lowPower ? 2 : 1)
    }

    public static func isCheckDue(lastCheck: Date?, interval: TimeInterval, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval
    }

    /// Mail that arrived while unloaded. The first count has nothing to compare with.
    public static func newMessages(previous: Int?, current: Int?) -> Int {
        guard let previous, let current else { return 0 }
        return max(0, current - previous)
    }

    public static func newMailTitle(_ count: Int) -> String {
        count == 1 ? "1 new message" : "\(count) new messages"
    }
}
