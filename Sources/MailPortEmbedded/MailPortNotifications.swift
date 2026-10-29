import AppKit
import Combine
import CryptoKit
import MailPortCore
import UserNotifications

@MainActor
final class MailPortNotifications: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = MailPortNotifications()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "notificationsEnabled")
    @Published private(set) var authorization: UNAuthorizationStatus = .notDetermined
    @Published private(set) var lastError: String?
    @Published private(set) var lastDelivery: String?
    var onPermissionChanged: (() -> Void)?
    var onOpen: ((UUID, GoogleService, String?) -> Void)?
    private let center = UNUserNotificationCenter.current()
    private var activity: NSObjectProtocol?
    private var pendingOpen: (UUID, GoogleService, String?)?

    var permission: String {
        if authorization == .denied { return "denied" }
        return enabled && (authorization == .authorized || authorization == .provisional) ? "granted" : "default"
    }

    private override init() {
        super.init()
        center.delegate = self
        Task { await refresh() }
    }

    func refresh() async {
        authorization = await center.notificationSettings().authorizationStatus
        updateActivity()
        onPermissionChanged?()
    }

    func reportError(_ message: String) { lastError = message }

    func enable() async {
        lastError = nil
        do {
            let allowed = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            enabled = allowed
            UserDefaults.standard.set(allowed, forKey: "notificationsEnabled")
            if !allowed { lastError = "Allow MailPort notifications in System Settings → Notifications." }
        } catch { lastError = error.localizedDescription }
        await refresh()
    }

    func disable() {
        enabled = false
        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
        updateActivity()
        onPermissionChanged?()
    }

    private func updateActivity() {
        if permission == "granted", activity == nil {
            activity = ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Deliver Google Calendar reminders while MailPort is running")
        } else if permission != "granted", let token = activity {
            ProcessInfo.processInfo.endActivity(token)
            activity = nil
        }
    }

    func deliver(_ message: WebNotificationMessage, account: Account, service: GoogleService) async -> String? {
        guard permission == "granted" else { return nil }
        let key = message.tag.isEmpty ? message.id : message.tag
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let identifier = "mailport.\(account.id.uuidString).\(service.rawValue).\(digest)"
        let content = UNMutableNotificationContent()
        content.title = message.title.isEmpty ? (service == .calendar ? "Calendar reminder" : "New mail") : message.title
        content.subtitle = account.name
        content.body = message.body
        if !message.silent { content.sound = .default }
        content.threadIdentifier = "\(account.id.uuidString).\(service.rawValue)"
        content.userInfo = ["accountID": account.id.uuidString, "service": service.rawValue, "webID": message.id]
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            lastDelivery = "\(service.title) alert for \(account.name) at \(Date().formatted(date: .omitted, time: .shortened))"
            return identifier
        } catch { lastError = error.localizedDescription; return nil }
    }

    func close(_ identifier: String) {
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        center.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func sendTest(account: Account) async {
        guard permission == "granted" else { lastError = "Enable MailPort notifications first."; return }
        let message = WebNotificationMessage(["kind": "show", "id": UUID().uuidString,
            "title": "MailPort test reminder", "body": "Notifications are ready. Click to open \(account.name)’s Calendar."])!
        _ = await deliver(message, account: account, service: .calendar)
    }

    func attachOpenHandler(_ handler: @escaping (UUID, GoogleService, String?) -> Void) {
        onOpen = handler
        if let pendingOpen { handler(pendingOpen.0, pendingOpen.1, pendingOpen.2); self.pendingOpen = nil }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let accountID = (info["accountID"] as? String).flatMap(UUID.init(uuidString:))
        let service = (info["service"] as? String).flatMap(GoogleService.init(rawValue:))
        let webID = info["webID"] as? String
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let accountID, let service, service == .calendar || service == .gmail {
            Task { @MainActor in
                if let handler = self.onOpen { handler(accountID, service, webID) }
                else { self.pendingOpen = (accountID, service, webID) }
            }
        }
        completionHandler()
    }
}
