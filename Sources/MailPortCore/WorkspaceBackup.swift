import Foundation

/// Explicit configuration allowlist. Never serializes website stores or security preferences.
public struct WorkspaceBackup: Codable, Sendable {
    public var version = 1
    public var accounts: [Account]
    public var tabs: [WorkspaceTab]
    public var pins: [WorkspacePin]
    public var collapsed: Set<UUID>
    public var badgeExcluded: Set<UUID>
    public var notifications: [UUID: AccountNotificationSettings]
    public var defaultMailAccount: UUID?
    public var layout: String
    public var shortcutHints: Bool
    public var zoom: [String: Double]
    public var videoOpacity: Double

    public init(accounts: [Account], tabs: [WorkspaceTab], pins: [WorkspacePin], collapsed: Set<UUID> = [], badgeExcluded: Set<UUID> = [], notifications: [UUID: AccountNotificationSettings] = [:], defaultMailAccount: UUID? = nil, layout: String = "sidebar", shortcutHints: Bool = true, zoom: [String: Double] = [:], videoOpacity: Double = 1) {
        self.accounts = accounts; self.tabs = tabs; self.pins = pins; self.collapsed = collapsed
        self.badgeExcluded = badgeExcluded; self.notifications = notifications; self.defaultMailAccount = defaultMailAccount
        self.layout = layout; self.shortcutHints = shortcutHints; self.zoom = zoom; self.videoOpacity = videoOpacity
    }

    public enum Invalid: LocalizedError {
        case configuration
        public var errorDescription: String? { "This isn’t a supported MailPort workspace backup, or it contains invalid configuration." }
    }
    public func validate() throws {
        let ids = Set(accounts.map(\.id))
        guard version == 1, accounts.count <= 100, tabs.count <= 1000, pins.count <= 10000,
              ids.count == accounts.count, Set(tabs).count == tabs.count, Set(pins.map(\.id)).count == pins.count,
              tabs.allSatisfy({ ids.contains($0.accountID) }),
              pins.allSatisfy({ ids.contains($0.accountID) && $0.isValid && $0.url.absoluteString.utf8.count < 16384 }),
              collapsed.isSubset(of: ids), badgeExcluded.isSubset(of: ids), Set(notifications.keys).isSubset(of: ids),
              defaultMailAccount.map({ ids.contains($0) }) ?? true,
              ["sidebar", "tabBar"].contains(layout), videoOpacity.isFinite, (0.15...1).contains(videoOpacity),
              zoom.allSatisfy({ GoogleService(rawValue: $0.key) != nil && PageZoom.isValid($0.value) }) else { throw Invalid.configuration }
        for account in accounts {
            _ = try account.validated()
            guard account.name.count <= 200, account.email.count <= 320 else { throw Invalid.configuration }
        }
    }
    public static func decode(_ data: Data) throws -> Self {
        guard data.count <= 5_000_000 else { throw Invalid.configuration }
        let value = try JSONDecoder().decode(Self.self, from: data)
        try value.validate()
        return value
    }
    public func encoded() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        guard data.count <= 5_000_000 else { throw Invalid.configuration }
        return data
    }
    /// Restore into new profiles, never into an existing cookie store.
    public func importing(alongside existing: [Account]) throws -> Self {
        try validate()
        var result = self
        let mapping = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, UUID()) })
        var names = Set(existing.map { $0.name.lowercased() })
        result.accounts = try accounts.map { original in
            var account = try original.validated()
            account.id = mapping[original.id]!
            var name = account.name; var suffix = 1
            while names.contains(name.lowercased()) {
                name = String(account.name.prefix(170)) + (suffix == 1 ? " (restored)" : " (restored \(suffix))"); suffix += 1
            }
            account.name = name; names.insert(name.lowercased()); return account
        }
        result.tabs = tabs.map { WorkspaceTab(accountID: mapping[$0.accountID]!, service: $0.service) }
        result.pins = pins.map { WorkspacePin(accountID: mapping[$0.accountID]!, service: $0.service, name: $0.name, url: $0.url)! }
        result.collapsed = Set(collapsed.map { mapping[$0]! })
        result.badgeExcluded = Set(badgeExcluded.map { mapping[$0]! })
        result.notifications = Dictionary(uniqueKeysWithValues: notifications.map { (mapping[$0.key]!, $0.value) })
        result.defaultMailAccount = defaultMailAccount.flatMap { mapping[$0] }
        return result
    }
}
