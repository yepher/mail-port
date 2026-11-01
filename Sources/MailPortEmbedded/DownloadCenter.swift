import AppKit
import Combine

@MainActor
final class DownloadCenter: ObservableObject {
    enum State: String { case running, completed, failed, cancelled }
    struct Entry: Identifiable {
        let id: UUID
        let owner: UUID?
        let account: String
        let source: String
        let destination: URL
        let started: Date
        var state = State.running
        var progress: Double?
        var detail = "Starting…"
        var error: String?
        var canRetry: Bool
    }
    @Published private(set) var entries: [Entry] = []
    private var cancellations: [UUID: () -> Void] = [:]
    private var retries: [UUID: () -> Void] = [:]
    var runningCount: Int { entries.filter { $0.state == .running }.count }

    func begin(account: String, source: String, destination: URL, owner: UUID? = nil, cancel: @escaping () -> Void, retry: (() -> Void)? = nil) -> UUID {
        let id = UUID()
        entries.append(Entry(id: id, owner: owner, account: account, source: source, destination: destination, started: Date(), canRetry: retry != nil))
        cancellations[id] = cancel
        retries[id] = retry
        while entries.count > 100, let old = entries.first(where: { $0.state != .running }) { remove(old.id) }
        return id
    }
    func update(_ id: UUID, progress: Double?, detail: String) {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.state == .running }) else { return }
        entries[index].progress = progress.flatMap { $0.isFinite && (0...1).contains($0) ? $0 : nil }
        entries[index].detail = detail
    }
    func complete(_ id: UUID) { finish(id, state: .completed, error: nil) }
    func fail(_ id: UUID, error: String) { finish(id, state: .failed, error: error) }
    private func finish(_ id: UUID, state: State, error: String?) {
        guard let index = entries.firstIndex(where: { $0.id == id && $0.state == .running }) else { return }
        entries[index].state = state; entries[index].error = error
        entries[index].detail = state == .completed ? "Saved" : state.rawValue.capitalized
        cancellations.removeValue(forKey: id)
        if state == .completed { retries.removeValue(forKey: id); entries[index].canRetry = false }
    }
    func cancel(_ id: UUID) {
        let action = cancellations[id]
        finish(id, state: .cancelled, error: nil)
        action?()
    }
    func retry(_ id: UUID) {
        guard entries.contains(where: { $0.id == id && ($0.state == .failed || $0.state == .cancelled) }) else { return }
        retries[id]?()
    }
    func retire(owner: UUID) {
        for id in entries.filter({ $0.owner == owner }).map(\.id) {
            cancel(id)
            retries.removeValue(forKey: id)
            if let index = entries.firstIndex(where: { $0.id == id }) { entries[index].canRetry = false }
        }
    }
    func clearFinished() { for entry in entries where entry.state != .running { remove(entry.id) } }
    private func remove(_ id: UUID) {
        entries.removeAll { $0.id == id }; cancellations.removeValue(forKey: id); retries.removeValue(forKey: id)
    }
    func clearForLock() {
        let actions = Array(cancellations.values)
        entries.removeAll(); cancellations.removeAll(); retries.removeAll()
        actions.forEach { $0() }
    }
}
