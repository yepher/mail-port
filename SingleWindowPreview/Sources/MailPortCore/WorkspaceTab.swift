import Foundation

/// A service tab keeps its identity while account labels or colors change.
public struct WorkspaceTab: Identifiable, Hashable, Sendable {
    public let accountID: UUID
    public let service: GoogleService

    public init(accountID: UUID, service: GoogleService) {
        self.accountID = accountID
        self.service = service
    }

    public var id: String { "\(accountID.uuidString):\(service.rawValue)" }

    /// All services for an account share cookies; different accounts do not.
    public var dataStoreIdentifier: UUID { accountID }

    public static func pinnedTabs(for accounts: [Account]) -> [WorkspaceTab] {
        accounts.flatMap { account in
            [
                WorkspaceTab(accountID: account.id, service: .gmail),
                WorkspaceTab(accountID: account.id, service: .calendar)
            ]
        }
    }
}
