import Combine
import Foundation
#if canImport(Sparkle) && !DEBUG
import Sparkle
#endif

/// Sparkle runs only in signed release builds. Their Info.plist carries the
/// update feed, so debug and local builds are never offered a release.
@MainActor
final class AppUpdates: ObservableObject {
    static let shared = AppUpdates()

    @Published private(set) var isAvailable = false
    @Published private(set) var canCheck = false
    @Published var checksAutomatically = false {
        didSet { applyAutomaticChecks() }
    }

    #if canImport(Sparkle) && !DEBUG
    private var controller: SPUStandardUpdaterController?
    private var changes: AnyCancellable?

    private init() {
        guard Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        isAvailable = true
        checksAutomatically = controller.updater.automaticallyChecksForUpdates
        changes = controller.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).sink { [weak self] in self?.canCheck = $0 }
    }

    func check() { controller?.checkForUpdates(nil) }

    private func applyAutomaticChecks() {
        guard let updater = controller?.updater, updater.automaticallyChecksForUpdates != checksAutomatically else { return }
        updater.automaticallyChecksForUpdates = checksAutomatically
    }
    #else
    private init() {}
    func check() {}
    private func applyAutomaticChecks() {}
    #endif
}
