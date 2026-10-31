import Foundation

public struct QuickSwitchItem: Identifiable, Hashable, Sendable {
    public enum Destination: Hashable, Sendable {
        case tab(WorkspaceTab)
        case pin(WorkspacePin)
    }

    public let destination: Destination
    public let accountID: UUID
    public let title: String
    public let subtitle: String
    public let symbol: String

    public var id: String {
        switch destination {
        case .tab(let tab): "tab:\(tab.id)"
        case .pin(let pin): "pin:\(pin.id.uuidString)"
        }
    }
}

public enum QuickSwitch {
    /// Open tabs come first, then pins, then services that aren't open yet.
    /// An empty query lists only tabs and pins; every typed word must match.
    public static func items(accounts: [Account], tabs: [WorkspaceTab], pins: [WorkspacePin], query: String) -> [QuickSwitchItem] {
        let terms = query.split(whereSeparator: \.isWhitespace).map(normalized)
        let open = tabs.compactMap { tab in accounts.first { $0.id == tab.accountID }.map { item(for: tab, account: $0) } }
        let saved = pins.compactMap { pin in accounts.first { $0.id == pin.accountID }.map { item(for: pin, account: $0) } }
        guard !terms.isEmpty else { return open + saved }
        let closed = accounts.flatMap { account in
            GoogleService.allCases.map { WorkspaceTab(accountID: account.id, service: $0) }
                .filter { !tabs.contains($0) }.map { item(for: $0, account: account) }
        }
        return (open + saved + closed).filter { item in
            let words = normalized(keywords(for: item, accounts: accounts))
            return terms.allSatisfy(words.contains)
        }
    }

    private static func item(for tab: WorkspaceTab, account: Account) -> QuickSwitchItem {
        QuickSwitchItem(destination: .tab(tab), accountID: account.id, title: tab.service.shortTitle,
            subtitle: account.name, symbol: tab.service.symbol)
    }

    private static func item(for pin: WorkspacePin, account: Account) -> QuickSwitchItem {
        QuickSwitchItem(destination: .pin(pin), accountID: account.id, title: pin.name,
            subtitle: "\(account.name) · \(pin.service.shortTitle)", symbol: "pin")
    }

    private static func keywords(for item: QuickSwitchItem, accounts: [Account]) -> String {
        let account = accounts.first { $0.id == item.accountID }
        let service: GoogleService
        switch item.destination {
        case .tab(let tab): service = tab.service
        case .pin(let pin): service = pin.service
        }
        return [item.title, account?.name ?? "", account?.email ?? "", service.title, service.shortTitle].joined(separator: " ")
    }

    private static func normalized<S: StringProtocol>(_ text: S) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
