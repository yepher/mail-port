import Foundation

public struct AccountStore: Sendable {
    public let directory: URL
    public var fileURL: URL { directory.appendingPathComponent("accounts.json") }

    public init(directory: URL) { self.directory = directory }

    public func load() throws -> [Account] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        let accounts = try JSONDecoder().decode([Account].self, from: Data(contentsOf: fileURL))
        return try validated(accounts.map { $0.repaired() })
    }

    public func save(_ accounts: [Account]) throws {
        let accounts = try validated(accounts)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(accounts).write(to: fileURL, options: .atomic)
    }

    private func validated(_ accounts: [Account]) throws -> [Account] {
        guard Set(accounts.map(\.id)).count == accounts.count else { throw AccountError.duplicateAccount }
        return try accounts.map { try $0.validated() }
    }
}
