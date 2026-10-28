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

    public init(id: UUID = UUID(), name: String, email: String = "", color: AccountColor = .blue) {
        self.id = id
        self.name = name
        self.email = email
        self.color = color
    }

    public func validated() throws -> Account {
        var account = self
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.email = email.trimmingCharacters(in: .whitespacesAndNewlines)
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
