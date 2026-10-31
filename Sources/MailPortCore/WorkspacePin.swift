import Foundation

/// A saved page inside one account's service, such as a Gmail search or Drive folder.
public struct WorkspacePin: Identifiable, Hashable, Codable, Sendable {
    public static let maximumNameLength = 60

    public let id: UUID
    public let accountID: UUID
    public let service: GoogleService
    public let name: String
    public let url: URL

    public init?(id: UUID = UUID(), accountID: UUID, service: GoogleService, name: String, url: URL) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maximumNameLength))
        guard !trimmed.isEmpty, Self.canPin(url, in: service) else { return nil }
        self.id = id
        self.accountID = accountID
        self.service = service
        self.name = trimmed
        self.url = url
    }

    /// Sign-in pages and other hosts stay out, so a pin always reopens its own service.
    public static func canPin(_ url: URL, in service: GoogleService) -> Bool {
        url.scheme?.lowercased() == "https" && url.user == nil && url.password == nil
            && url.host?.lowercased() == service.url.host?.lowercased()
    }

    /// Pins reorder only within their account; other accounts' pins keep their order.
    public static func reordered(_ pins: [WorkspacePin], moving source: WorkspacePin, over target: WorkspacePin) -> [WorkspacePin] {
        guard source != target, source.accountID == target.accountID,
              let from = pins.firstIndex(of: source), let to = pins.firstIndex(of: target) else { return pins }
        var result = pins
        result.remove(at: from)
        result.insert(source, at: to)
        return result
    }

    /// The pin one step away in the same account, for Move Up and Move Down.
    public static func neighbor(of pin: WorkspacePin, in pins: [WorkspacePin], offset: Int) -> WorkspacePin? {
        let siblings = pins.filter { $0.accountID == pin.accountID }
        guard let index = siblings.firstIndex(of: pin), siblings.indices.contains(index + offset) else { return nil }
        return siblings[index + offset]
    }

    /// Saved preferences are rechecked because they can be edited outside the app.
    public var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= Self.maximumNameLength
            && Self.canPin(url, in: service)
    }
}
