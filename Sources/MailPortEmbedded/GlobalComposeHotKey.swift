import Carbon.HIToolbox
import Foundation

/// ⌃⌥⌘N from any app. Carbon's hot keys need no Accessibility permission,
/// because the app only learns that its own shortcut was pressed.
@MainActor
final class GlobalComposeHotKey {
    static let shared = GlobalComposeHotKey()
    var onPress: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func setEnabled(_ enabled: Bool) {
        if enabled { register() } else { unregister() }
    }

    private func register() {
        guard hotKey == nil else { return }
        if handler == nil {
            var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { GlobalComposeHotKey.shared.onPress?() } }
                return noErr
            }, 1, &event, nil, &handler)
        }
        let identifier = EventHotKeyID(signature: OSType(0x4D50_6F72), id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_N), UInt32(controlKey | optionKey | cmdKey), identifier,
            GetApplicationEventTarget(), 0, &hotKey)
    }

    private func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = nil
    }
}
