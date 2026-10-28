import Foundation

/// A service tab keeps its identity while account labels or colors change.
public struct WorkspaceTab: Identifiable, Hashable, Codable, Sendable {
    public let accountID: UUID
    public let service: GoogleService

    public init(accountID: UUID, service: GoogleService) {
        self.accountID = accountID
        self.service = service
    }

    public var id: String { "\(accountID.uuidString):\(service.rawValue)" }

    /// All services for an account share cookies; different accounts do not.
    public var dataStoreIdentifier: UUID { accountID }

    /// Move to the hovered tab's index in either direction, retaining identities.
    public static func reordered(_ tabs: [WorkspaceTab], moving source: WorkspaceTab, over target: WorkspaceTab) -> [WorkspaceTab] {
        guard source != target, let from = tabs.firstIndex(of: source), let to = tabs.firstIndex(of: target) else { return tabs }
        var result = tabs
        result.remove(at: from)
        result.insert(source, at: to)
        return result
    }

    /// Keep background-tab closure from changing focus. When the selected tab
    /// closes, prefer its right-hand neighbor, then the tab on its left.
    public static func selection(afterClosing closed: WorkspaceTab, in tabs: [WorkspaceTab], selected: WorkspaceTab?) -> WorkspaceTab? {
        guard let index = tabs.firstIndex(of: closed), selected == closed else { return selected }
        if tabs.indices.contains(index + 1) { return tabs[index + 1] }
        if index > 0 { return tabs[index - 1] }
        return nil
    }

    public static func pinnedTabs(for accounts: [Account]) -> [WorkspaceTab] {
        accounts.flatMap { account in
            [
                WorkspaceTab(accountID: account.id, service: .gmail),
                WorkspaceTab(accountID: account.id, service: .calendar)
            ]
        }
    }
}
