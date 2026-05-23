import Carbon
import Foundation

@MainActor
final class HotKeyController {
    private let identifier: UInt32
    private nonisolated(unsafe) var hotKeyRef: EventHotKeyRef?
    private nonisolated(unsafe) var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    init(identifier: UInt32 = 1) {
        self.identifier = identifier
    }

    func register(shortcut: AppHotKeyShortcut, action: @escaping () -> Void) throws {
        self.action = action
        unregisterHotKey()

        if eventHandler == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: OSType(kEventHotKeyPressed)
            )

            let selfPointer = Unmanaged.passUnretained(self).toOpaque()
            let handlerStatus = InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, userData in
                    guard let userData else {
                        return noErr
                    }

                    let controller = Unmanaged<HotKeyController>.fromOpaque(userData).takeUnretainedValue()
                    Task { @MainActor in
                        controller.action?()
                    }
                    return noErr
                },
                1,
                &eventType,
                selfPointer,
                &eventHandler
            )

            guard handlerStatus == noErr else {
                throw HotKeyError.registrationFailed("InstallEventHandler returned \(handlerStatus)")
            }
        }

        let hotKeyID = EventHotKeyID(signature: fourCharacterCode("PPrd"), id: identifier)
        let hotKeyStatus = RegisterEventHotKey(
            shortcut.keyCode,
            shortcut.modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        guard hotKeyStatus == noErr else {
            throw HotKeyError.registrationFailed("RegisterEventHotKey returned \(hotKeyStatus)")
        }
    }

    deinit {
        unregisterHotKey()

        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }

    private nonisolated func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func fourCharacterCode(_ string: String) -> OSType {
        string.utf8.reduce(0) { result, character in
            (result << 8) + OSType(character)
        }
    }
}

enum HotKeyError: LocalizedError {
    case registrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .registrationFailed(let message):
            return message
        }
    }
}
