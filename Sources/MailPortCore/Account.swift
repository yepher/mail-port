import Foundation

public enum AccountColor: String, Codable, CaseIterable, Identifiable, Sendable {
    case blue, teal, orange, purple, rose
    public var id: String { rawValue }
}

public struct Account: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var email: String
    public var color: AccountColor
    /// An HTML color code that overrides `color`. It's a separate field so older
    /// builds can still read the account list and show the preset instead.
    public var customColor: String?
    /// Bundle identifier of the browser for this account's outside links. Nil uses the default.
    /// Optional, so older builds can still read the account list.
    public var linkBrowser: String?

    public init(id: UUID = UUID(), name: String, email: String = "", color: AccountColor = .blue, customColor: String? = nil, linkBrowser: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
        self.color = color
        self.customColor = customColor
        self.linkBrowser = linkBrowser
    }

    public var hexColor: HexColor? { customColor.flatMap(HexColor.init) }

    /// One bad saved label shouldn't hide every account or strand this account's sign-in.
    public func repaired() -> Account {
        if (try? validated()) != nil { return self }
        var account = self
        if account.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { account.name = "Account" }
        if (try? account.validated()) == nil { account.email = "" }
        return account
    }

    public func validated() throws -> Account {
        var account = self
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        // A bad saved color falls back to the preset rather than failing the whole account list.
        account.customColor = hexColor?.code
        guard !account.name.isEmpty else { throw AccountError.nameRequired }
        if !account.email.isEmpty {
            let pattern = #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#
            guard account.email.range(of: pattern, options: .regularExpression) != nil else {
                throw AccountError.invalidEmail
            }
        }
        return account
    }
}

public enum AccountError: LocalizedError, Equatable {
    case nameRequired, invalidEmail, duplicateAccount

    public var errorDescription: String? {
        switch self {
        case .nameRequired: "Give this account a name."
        case .invalidEmail: "Enter a valid email address, or leave the email field empty."
        case .duplicateAccount: "The saved account list contains duplicate account identifiers."
        }
    }
}
