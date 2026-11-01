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
    struct Receipt {
        var submitted: Date?
        var delivered: Date?
        var testSubmitted: Date?
        var testDelivered: Date?
        var error: String?
    }
    @Published private(set) var receipts: [UUID: Receipt] = [:]
    var onPermissionChanged: (() -> Void)?
    var onOpen: ((UUID, GoogleService, String?) -> Void)?
    var settingsForAccount: ((UUID) -> AccountNotificationSettings)?
    // Command-line XCTest has no application bundle proxy. The production
    // app always uses its real notification center; tests have no OS alerts.
    private let center: UNUserNotificationCenter? = Bundle.main.bundleURL.pathExtension == "app" ? .current() : nil
    private var activity: NSObjectProtocol?
    private var pendingOpen: (UUID, GoogleService, String?)?
    private var privacyLocked = true
    private var privacyGeneration = UUID()

    var permission: String {
        if privacyLocked { return "default" }
        if authorization == .denied { return "denied" }
        return enabled && (authorization == .authorized || authorization == .provisional) ? "granted" : "default"
    }

    private override init() {
        super.init()
        center?.delegate = self
        Task { await refresh() }
    }

    func refresh() async {
        authorization = await center?.notificationSettings().authorizationStatus ?? .denied
        await refreshDelivered()
        updateActivity()
        onPermissionChanged?()
    }

    func refreshDelivered() async {
        guard !privacyLocked, let center else { return }
        let generation = privacyGeneration
        let delivered = await center.deliveredNotifications()
        guard privacyGeneration == generation, !privacyLocked else { return }
        for notification in delivered {
            let info = notification.request.content.userInfo
            guard let rawID = info["accountID"] as? String, let id = UUID(uuidString: rawID) else { continue }
            var receipt = receipts[id] ?? Receipt()
            if info["test"] as? Bool == true { receipt.testDelivered = max(receipt.testDelivered ?? .distantPast, notification.date) }
            else if info["service"] as? String == GoogleService.calendar.rawValue { receipt.delivered = max(receipt.delivered ?? .distantPast, notification.date) }
            receipts[id] = receipt
        }
    }

    func reportError(_ message: String) { lastError = message }

    func setPrivacyLocked(_ locked: Bool, clearDelivered: Bool = true) {
        privacyLocked = locked
        if locked { privacyGeneration = UUID() }
        if locked && clearDelivered {
            center?.removeAllPendingNotificationRequests()
            center?.removeAllDeliveredNotifications()
            lastDelivery = nil; lastError = nil; pendingOpen = nil; receipts.removeAll()
        }
        updateActivity()
    }

    func clearForLocalReset() {
        setPrivacyLocked(true)
        enabled = false
        UserDefaults.standard.set(false, forKey: "notificationsEnabled")
    }

    func enable() async {
        lastError = nil
        do {
            guard let center else { throw CocoaError(.featureUnsupported) }
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

    func deliver(_ message: WebNotificationMessage, account: Account, service: GoogleService, test: Bool = false) async -> String? {
        guard permission == "granted", let center else { return nil }
        let generation = privacyGeneration
        let settings = settingsForAccount?(account.id) ?? AccountNotificationSettings()
        guard !settings.isMuted(at: Date()) else { return nil }
        let key = message.tag.isEmpty ? message.id : message.tag
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        let identifier = "mailport.\(account.id.uuidString).\(service.rawValue).\(digest)"
        let content = UNMutableNotificationContent()
        let text = settings.alertText(title: message.title, body: message.body, service: service)
        content.title = text.title
        content.subtitle = account.name
        content.body = text.body
        if !message.silent { content.sound = .default }
        content.threadIdentifier = "\(account.id.uuidString).\(service.rawValue)"
        content.userInfo = ["accountID": account.id.uuidString, "service": service.rawValue, "webID": message.id, "test": test]
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            guard !privacyLocked, privacyGeneration == generation else { center.removeDeliveredNotifications(withIdentifiers: [identifier]); return nil }
            var receipt = receipts[account.id] ?? Receipt()
            if test { receipt.testSubmitted = Date() }
            else if service == .calendar { receipt.submitted = Date() }
            receipt.error = nil; receipts[account.id] = receipt
            lastDelivery = "\(service.title) alert submitted for \(account.name) at \(Date().formatted(date: .omitted, time: .shortened))"
            return identifier
        } catch {
            guard !privacyLocked, privacyGeneration == generation else { return nil }
            lastError = error.localizedDescription
            var receipt = receipts[account.id] ?? Receipt(); receipt.error = error.localizedDescription; receipts[account.id] = receipt
            return nil
        }
    }

    func close(_ identifier: String) {
        center?.removePendingNotificationRequests(withIdentifiers: [identifier])
        center?.removeDeliveredNotifications(withIdentifiers: [identifier])
    }

    func sendTest(account: Account) async {
        guard permission == "granted" else { lastError = "Enable MailPort notifications first."; return }
        if settingsForAccount?(account.id).isMuted(at: Date()) == true { lastError = "\(account.name) is muted."; return }
        let message = WebNotificationMessage(["kind": "show", "id": UUID().uuidString,
            "title": "MailPort test reminder", "body": "Notifications are ready. Click to open \(account.name)’s Calendar."])!
        _ = await deliver(message, account: account, service: .calendar, test: true)
        // Delivery is asynchronous; verify actual Notification Center presence separately.
        try? await Task.sleep(for: .milliseconds(500))
        await refreshDelivered()
    }

    func attachOpenHandler(_ handler: @escaping (UUID, GoogleService, String?) -> Void) {
        onOpen = handler
        if let pendingOpen { handler(pendingOpen.0, pendingOpen.1, pendingOpen.2); self.pendingOpen = nil }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        Task { @MainActor in completionHandler(self.privacyLocked ? [] : [.banner, .sound, .list]) }
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
