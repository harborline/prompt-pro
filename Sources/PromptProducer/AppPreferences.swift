import AppKit
import Carbon
import KeyboardShortcuts
import SwiftUI

enum AppPreferenceKeys {
    static let theme = "theme"
    static let hotKeyShortcut = "hotKeyShortcut"
    static let promptSelectionBehavior = "promptSelectionBehavior"
    static let hideDockIcon = "hideDockIcon"
    static let hideMenuBarIcon = "hideMenuBarIcon"
    static let keepWindowsOnTop = "keepWindowsOnTop"
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .system:
            return "System"
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }

    static func resolved(from rawValue: String) -> AppTheme {
        AppTheme(rawValue: rawValue) ?? .system
    }
}

struct LocalAIConfig: Equatable, Sendable {
    var model: String = "Apple Foundation Models"
}

extension KeyboardShortcuts.Name {
    static let openCommandBar = Self(
        "openCommandBar",
        default: KeyboardShortcuts.Shortcut(.u, modifiers: [.command, .shift])
    )
    static let newPrompt = Self(
        "newPrompt",
        default: KeyboardShortcuts.Shortcut(.u, modifiers: [.option, .shift])
    )
}

@MainActor
enum AppVisibilityPreferences {
    static func applyDockIconPreference(defaults: UserDefaults = .standard) {
        applyDockIconPreference(
            defaults.bool(forKey: AppPreferenceKeys.hideDockIcon)
        )
    }

    static func applyDockIconPreference(_ hidesDockIcon: Bool) {
        NSApp.setActivationPolicy(hidesDockIcon ? .accessory : .regular)
    }
}

@MainActor
enum AppWindowLevelPreferences {
    static let commandBarWindowIdentifier = NSUserInterfaceItemIdentifier("commandBar")
    static let promptPreviewWindowIdentifier = NSUserInterfaceItemIdentifier("promptPreview")

    static func applyToOpenWindows(keepWindowsOnTop: Bool? = nil, defaults: UserDefaults = .standard) {
        for window in NSApp.windows {
            apply(to: window, keepWindowsOnTop: keepWindowsOnTop, defaults: defaults)
        }
    }

    static func apply(to window: NSWindow, keepWindowsOnTop: Bool? = nil, defaults: UserDefaults = .standard) {
        let shouldKeepOnTop = keepWindowsOnTop ?? defaults.bool(forKey: AppPreferenceKeys.keepWindowsOnTop)
        let level = shouldKeepOnTop
            ? .floating
            : defaultLevel(for: window)
        window.level = level

        // AppKit can reset levels while restoring or creating windows, so reapply once on the next run loop.
        DispatchQueue.main.async { [weak window] in
            window?.level = level
        }
    }

    private static func defaultLevel(for window: NSWindow) -> NSWindow.Level {
        switch window.identifier {
        case commandBarWindowIdentifier, promptPreviewWindowIdentifier:
            return .floating
        default:
            return .normal
        }
    }
}

enum PromptSelectionBehavior: String, CaseIterable, Identifiable {
    case copyAndPaste
    case copyOnly

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .copyAndPaste:
            return "Enter copies and pastes in the last app"
        case .copyOnly:
            return "Enter only copies"
        }
    }

    var enterPastesIntoPreviousApplication: Bool {
        self == .copyAndPaste
    }

    static func resolved(from rawValue: String) -> PromptSelectionBehavior {
        PromptSelectionBehavior(rawValue: rawValue) ?? .copyAndPaste
    }

    static func current(defaults: UserDefaults = .standard) -> PromptSelectionBehavior {
        resolved(from: defaults.string(forKey: AppPreferenceKeys.promptSelectionBehavior) ?? Self.copyAndPaste.rawValue)
    }
}

struct AppHotKeyShortcut: Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let `default` = AppHotKeyShortcut(keyCode: UInt32(kVK_ANSI_U), modifiers: UInt32(cmdKey | shiftKey))
    static let newPromptDefault = AppHotKeyShortcut(keyCode: UInt32(kVK_ANSI_U), modifiers: UInt32(optionKey | shiftKey))

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(storageValue: String) {
        let parts = storageValue.split(separator: ":").compactMap { UInt32($0) }
        guard parts.count == 2 else {
            return nil
        }

        keyCode = parts[0]
        modifiers = parts[1]
    }

    init?(event: NSEvent) {
        let shortcutModifiers = Self.carbonModifiers(from: event.modifierFlags)
        guard Self.isValid(modifiers: shortcutModifiers), !Self.modifierOnlyKeyCodes.contains(UInt32(event.keyCode)) else {
            return nil
        }

        keyCode = UInt32(event.keyCode)
        modifiers = shortcutModifiers
    }

    var storageValue: String {
        "\(keyCode):\(modifiers)"
    }

    var displayName: String {
        var parts: [String] = []
        if modifiers & UInt32(cmdKey) != 0 {
            parts.append("Command")
        }
        if modifiers & UInt32(optionKey) != 0 {
            parts.append("Option")
        }
        if modifiers & UInt32(shiftKey) != 0 {
            parts.append("Shift")
        }
        if modifiers & UInt32(controlKey) != 0 {
            parts.append("Control")
        }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined(separator: "-")
    }

    func matches(_ event: NSEvent) -> Bool {
        UInt32(event.keyCode) == keyCode && Self.carbonModifiers(from: event.modifierFlags) == modifiers
    }

    static func current(defaults: UserDefaults = .standard) -> AppHotKeyShortcut {
        guard let rawValue = defaults.string(forKey: AppPreferenceKeys.hotKeyShortcut),
              let shortcut = AppHotKeyShortcut(storageValue: rawValue) else {
            return .default
        }

        return shortcut
    }

    private static let modifierOnlyKeyCodes: Set<UInt32> = [
        UInt32(kVK_Command),
        UInt32(kVK_Shift),
        UInt32(kVK_CapsLock),
        UInt32(kVK_Option),
        UInt32(kVK_Control),
        UInt32(kVK_RightCommand),
        UInt32(kVK_RightShift),
        UInt32(kVK_RightOption),
        UInt32(kVK_RightControl),
        UInt32(kVK_Function)
    ]

    private static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        let deviceFlags = flags.intersection(.deviceIndependentFlagsMask)

        if deviceFlags.contains(.command) {
            modifiers |= UInt32(cmdKey)
        }
        if deviceFlags.contains(.shift) {
            modifiers |= UInt32(shiftKey)
        }
        if deviceFlags.contains(.option) {
            modifiers |= UInt32(optionKey)
        }
        if deviceFlags.contains(.control) {
            modifiers |= UInt32(controlKey)
        }

        return modifiers
    }

    private static func isValid(modifiers: UInt32) -> Bool {
        modifiers & UInt32(cmdKey | controlKey | optionKey) != 0
    }

    private static func keyName(for keyCode: UInt32) -> String {
        let keyNames: [UInt32: String] = [
            UInt32(kVK_ANSI_A): "A",
            UInt32(kVK_ANSI_B): "B",
            UInt32(kVK_ANSI_C): "C",
            UInt32(kVK_ANSI_D): "D",
            UInt32(kVK_ANSI_E): "E",
            UInt32(kVK_ANSI_F): "F",
            UInt32(kVK_ANSI_G): "G",
            UInt32(kVK_ANSI_H): "H",
            UInt32(kVK_ANSI_I): "I",
            UInt32(kVK_ANSI_J): "J",
            UInt32(kVK_ANSI_K): "K",
            UInt32(kVK_ANSI_L): "L",
            UInt32(kVK_ANSI_M): "M",
            UInt32(kVK_ANSI_N): "N",
            UInt32(kVK_ANSI_O): "O",
            UInt32(kVK_ANSI_P): "P",
            UInt32(kVK_ANSI_Q): "Q",
            UInt32(kVK_ANSI_R): "R",
            UInt32(kVK_ANSI_S): "S",
            UInt32(kVK_ANSI_T): "T",
            UInt32(kVK_ANSI_U): "U",
            UInt32(kVK_ANSI_V): "V",
            UInt32(kVK_ANSI_W): "W",
            UInt32(kVK_ANSI_X): "X",
            UInt32(kVK_ANSI_Y): "Y",
            UInt32(kVK_ANSI_Z): "Z",
            UInt32(kVK_ANSI_0): "0",
            UInt32(kVK_ANSI_1): "1",
            UInt32(kVK_ANSI_2): "2",
            UInt32(kVK_ANSI_3): "3",
            UInt32(kVK_ANSI_4): "4",
            UInt32(kVK_ANSI_5): "5",
            UInt32(kVK_ANSI_6): "6",
            UInt32(kVK_ANSI_7): "7",
            UInt32(kVK_ANSI_8): "8",
            UInt32(kVK_ANSI_9): "9",
            UInt32(kVK_Space): "Space",
            UInt32(kVK_Escape): "Escape",
            UInt32(kVK_Return): "Return",
            UInt32(kVK_Tab): "Tab"
        ]

        return keyNames[keyCode] ?? "Key \(keyCode)"
    }
}
