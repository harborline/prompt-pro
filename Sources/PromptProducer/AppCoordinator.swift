import AppKit
import ApplicationServices
import CoreGraphics
import KeyboardShortcuts
import PromptProducerCore
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, ObservableObject, NSWindowDelegate {
    private let model: PromptLibraryModel
    private var commandPanel: NSPanel?
    private var previewPanel: NSPanel?
    private var openPromptLibraryWindow: (() -> Void)?
    private var previousApplication: NSRunningApplication?
    private var invocationContext: PromptInvocationContext?
    private var didRegisterKeyboardShortcuts = false
    private var didStart = false
    @Published private(set) var hotKeyStatus = "Command-Shift-U active"
    @Published private(set) var newPromptHotKeyStatus = "Option-Shift-U active"

    init(model: PromptLibraryModel) {
        self.model = model
        super.init()
    }

    func start() {
        guard !didStart else {
            return
        }

        didStart = true
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.bundleIdentifier != Bundle.main.bundleIdentifier else {
                return
            }

            Task { @MainActor in
                self?.previousApplication = application
            }
        }

        registerKeyboardShortcuts()
    }

    func setOpenPromptLibraryWindowAction(_ action: @escaping () -> Void) {
        openPromptLibraryWindow = action
    }

    private func registerKeyboardShortcuts() {
        guard !didRegisterKeyboardShortcuts else {
            updateShortcutStatuses()
            return
        }

        didRegisterKeyboardShortcuts = true

        KeyboardShortcuts.onKeyUp(for: .openCommandBar) { [weak self] in
            Task { @MainActor in
                self?.showCommandBar()
            }
        }

        KeyboardShortcuts.onKeyUp(for: .newPrompt) { [weak self] in
            Task { @MainActor in
                self?.createNewPromptFromHotKey()
            }
        }

        updateShortcutStatuses()
        AppLog.lifecycle.info("Registered KeyboardShortcuts global hotkeys")
    }

    private func updateShortcutStatuses() {
        hotKeyStatus = "\(Self.shortcutDisplayName(for: .openCommandBar, fallback: "Command-Shift-U")) active"
        newPromptHotKeyStatus = "\(Self.shortcutDisplayName(for: .newPrompt, fallback: "Option-Shift-U")) active"
    }

    private static func shortcutDisplayName(for name: KeyboardShortcuts.Name, fallback: String) -> String {
        guard let shortcut = KeyboardShortcuts.getShortcut(for: name) else {
            return fallback
        }

        return shortcut.description
    }

    func reloadHotKey() {
        updateShortcutStatuses()
    }

    func reloadNewPromptHotKey() {
        updateShortcutStatuses()
    }

    func createNewPromptFromHotKey() {
        model.addPrompt()
        showPromptLibraryWindow()
        AppLog.commands.info("Created prompt from global hotkey")
    }

    func showCommandBar() {
        if let frontmostApplication = NSWorkspace.shared.frontmostApplication,
           frontmostApplication.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApplication = frontmostApplication
        }
        invocationContext = Self.captureInvocationContext(from: previousApplication)

        let panel = commandPanel ?? makeCommandPanel()
        commandPanel = panel

        model.searchQuery = ""
        positionCommandPanel(panel)
        hideNonCommandWindows(except: panel)
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        hideNonCommandWindows(except: panel)
        panel.orderFrontRegardless()
        AppLog.commands.info("Opened command bar")
    }

    func hideCommandBar() {
        commandPanel?.orderOut(nil)
        AppLog.commands.info("Closed command bar")
    }

    func toggleCommandBar() {
        if commandPanel?.isVisible == true {
            hideCommandBar()
        } else {
            showCommandBar()
        }
    }

    func showPromptLibraryWindow() {
        openPromptLibraryWindow?()
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.async {
            let promptProducerWindow = NSApp.windows.first { window in
                window.identifier?.rawValue == "main" || window.title == "Prompt Producer"
            }
            promptProducerWindow?.makeKeyAndOrderFront(nil)
        }
    }

    func showSelectedPromptPreview() {
        guard let prompt = model.selectedPrompt ?? model.searchResults.first?.prompt else {
            return
        }

        showPromptPreview(PromptPreview(prompt: prompt))
    }

    func showPromptPreview(_ preview: PromptPreview) {
        let panel = previewPanel ?? makePreviewPanel()
        previewPanel = panel

        panel.contentViewController = NSHostingController(
            rootView: PromptPreviewView(preview: preview) { [weak self] in
                self?.hidePromptPreview()
            }
        )
        panel.title = preview.title.isEmpty ? "Prompt Preview" : preview.title
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        AppLog.commands.info("Opened prompt preview")
    }

    func hidePromptPreview() {
        previewPanel?.orderOut(nil)
        AppLog.commands.info("Closed prompt preview")
    }

    func copySelectedPromptAndClose(pasteIntoPreviousApplication shouldPaste: Bool) {
        guard let prompt = model.selectedPrompt ?? model.searchResults.first?.prompt else {
            return
        }

        copyPromptAndClose(prompt, pasteIntoPreviousApplication: shouldPaste)
    }

    func copyPromptAndClose(_ prompt: Prompt, pasteIntoPreviousApplication shouldPaste: Bool) {
        model.copyPrompt(prompt, context: invocationContext)
        hideCommandBar()
        AppLog.commands.info(
            "Copied prompt from command bar; paste requested: \(shouldPaste, privacy: .public), context captured: \(self.invocationContext != nil, privacy: .public)"
        )

        if shouldPaste {
            pasteIntoPreviousApplication()
        }
    }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === commandPanel {
            AppLog.commands.info("Command bar window closed")
        } else if notification.object as? NSWindow === previewPanel {
            AppLog.commands.info("Prompt preview window closed")
        }
    }

    private func makeCommandPanel() -> NSPanel {
        let rootView = CommandBarView(model: model) { [weak self] in
            self?.showSelectedPromptPreview()
        } onAccept: { [weak self] in
            self?.copySelectedPromptAndClose(
                pasteIntoPreviousApplication: PromptSelectionBehavior.current().enterPastesIntoPreviousApplication
            )
        } onCopy: { [weak self] prompt in
            self?.copyPromptAndClose(prompt, pasteIntoPreviousApplication: false)
        } onClose: { [weak self] in
            self?.hideCommandBar()
        }
        let hostingController = NSHostingController(rootView: rootView)
        let panel = CommandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 480),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.title = "Prompt Producer"
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = NordTheme.commandBarWindowRadius
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.masksToBounds = true
        panel.contentViewController = hostingController
        panel.delegate = self
        panel.onMoveSelection = { [weak model] delta in
            if delta > 0 {
                model?.selectNextResult()
            } else {
                model?.selectPreviousResult()
            }
        }
        panel.onPasteSelectedPrompt = { [weak self] in
            self?.copySelectedPromptAndClose(
                pasteIntoPreviousApplication: PromptSelectionBehavior.current().enterPastesIntoPreviousApplication
            )
        }
        panel.onPreviewSelectedPrompt = { [weak self] in
            self?.showSelectedPromptPreview()
        }
        return panel
    }

    private func hideNonCommandWindows(except commandPanel: NSPanel) {
        for window in NSApp.windows where window !== commandPanel && window.isVisible {
            window.orderOut(nil)
        }
    }

    private func positionCommandPanel(_ panel: NSPanel) {
        let containerFrame = NSScreen.screenContainingMouse?.visibleFrame
            ?? NSScreen.main?.visibleFrame

        guard let containerFrame else {
            panel.center()
            return
        }

        let panelSize = panel.frame.size
        let origin = NSPoint(
            x: containerFrame.midX - panelSize.width / 2,
            y: containerFrame.midY - panelSize.height / 2
        )
        panel.setFrameOrigin(origin)
    }

    private func makePreviewPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Prompt Preview"
        panel.applyPromptProducerChrome()
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView?.wantsLayer = true
        panel.contentView?.layer?.cornerRadius = NordTheme.windowRadius
        panel.contentView?.layer?.cornerCurve = .continuous
        panel.contentView?.layer?.masksToBounds = true
        panel.delegate = self
        return panel
    }

    private func pasteIntoPreviousApplication() {
        guard let previousApplication else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            NSApp.hide(nil)
            previousApplication.activate(options: [.activateAllWindows])

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                Self.postPasteShortcut()
            }
        }
    }

    private static func postPasteShortcut() {
        ensureAccessibilityPrompt()

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            runSystemEventsPasteShortcut()
        }
    }

    private static func ensureAccessibilityPrompt() {
        guard !AXIsProcessTrusted() else {
            return
        }

        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        AppLog.commands.info("Requested Accessibility permission for paste shortcut delivery")
    }

    private static func runSystemEventsPasteShortcut() {
        let script = NSAppleScript(source: "tell application \"System Events\" to keystroke \"v\" using command down")
        var error: NSDictionary?
        script?.executeAndReturnError(&error)

        if let error {
            AppLog.commands.error("System Events paste shortcut failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func captureInvocationContext(from application: NSRunningApplication?) -> PromptInvocationContext? {
        guard let application,
              application.processIdentifier > 0 else {
            return nil
        }

        guard AXIsProcessTrusted() else {
            requestAccessibilityPermission(reason: "read current page context")
            return nil
        }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let source = application.localizedName
        let focusedElement = axElementAttribute(applicationElement, kAXFocusedUIElementAttribute)

        if let focusedElement,
           let selectedText = normalizedContextText(axStringAttribute(focusedElement, kAXSelectedTextAttribute)) {
            AppLog.commands.info("Captured selected text context from previous application")
            return PromptInvocationContext(source: source, text: selectedText)
        }

        if let focusedElement,
           let focusedText = normalizedContextText(textValue(from: focusedElement)) {
            AppLog.commands.info("Captured focused element context from previous application")
            return PromptInvocationContext(source: source, text: focusedText)
        }

        let windowElement = axElementAttribute(applicationElement, kAXFocusedWindowAttribute)
        if let windowElement,
           let windowText = normalizedContextText(collectReadableText(from: windowElement)) {
            AppLog.commands.info("Captured window context from previous application")
            return PromptInvocationContext(source: source, text: windowText)
        }

        AppLog.commands.info("No readable invocation context found in previous application")
        return nil
    }

    private static func requestAccessibilityPermission(reason: StaticString) {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        AppLog.commands.info("Requested Accessibility permission to \(reason, privacy: .public)")
    }

    private static func axElementAttribute(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        return (value as! AXUIElement)
    }

    private static func axStringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }

        if let stringValue = value as? String {
            return stringValue
        }

        return nil
    }

    private static func axElementsAttribute(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let elements = value as? [AXUIElement] else {
            return []
        }

        return elements
    }

    private static func textValue(from element: AXUIElement) -> String? {
        let role = axStringAttribute(element, kAXRoleAttribute) ?? ""
        guard readableRoles.contains(role) else {
            return nil
        }

        if let value = axStringAttribute(element, kAXValueAttribute) {
            return value
        }

        return axStringAttribute(element, kAXDescriptionAttribute)
            ?? axStringAttribute(element, kAXTitleAttribute)
    }

    private static func collectReadableText(
        from element: AXUIElement,
        depth: Int = 0,
        collected: inout [String]
    ) {
        guard depth <= 8,
              collected.joined(separator: "\n").count < PromptInvocationFormatter.maximumContextLength else {
            return
        }

        if let text = textValue(from: element)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            collected.append(text)
        }

        let visibleChildren = axElementsAttribute(element, kAXVisibleChildrenAttribute)
        let children = visibleChildren.isEmpty
            ? axElementsAttribute(element, kAXChildrenAttribute)
            : visibleChildren

        for child in children {
            collectReadableText(from: child, depth: depth + 1, collected: &collected)
        }
    }

    private static func collectReadableText(from element: AXUIElement) -> String? {
        var collected: [String] = []
        collectReadableText(from: element, collected: &collected)

        var seen = Set<String>()
        let deduped = collected.filter { text in
            let normalized = text
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else {
                return false
            }

            seen.insert(normalized)
            return true
        }

        return deduped.joined(separator: "\n")
    }

    private static func normalizedContextText(_ value: String?) -> String? {
        guard let value else {
            return nil
        }

        let collapsed = value
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard collapsed.count >= 3 else {
            return nil
        }

        return String(collapsed.prefix(PromptInvocationFormatter.maximumContextLength))
    }

    private static let readableRoles: Set<String> = [
        kAXStaticTextRole,
        kAXTextAreaRole,
        kAXTextFieldRole,
        kAXComboBoxRole,
        "AXWebArea",
        "AXHeading",
        "AXParagraph",
        "AXDocument"
    ]
}

private extension NSScreen {
    static var screenContainingMouse: NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return screens.first { screen in
            screen.frame.contains(mouseLocation)
        }
    }
}

private final class CommandPanel: NSPanel {
    var onMoveSelection: ((Int) -> Void)?
    var onPasteSelectedPrompt: (() -> Void)?
    var onPreviewSelectedPrompt: (() -> Void)?

    override var canBecomeKey: Bool {
        true
    }

    override var canBecomeMain: Bool {
        true
    }

    override func sendEvent(_ event: NSEvent) {
        guard event.type == .keyDown else {
            super.sendEvent(event)
            return
        }

        switch event.keyCode {
        case 125:
            onMoveSelection?(1)
        case 126:
            onMoveSelection?(-1)
        case 36, 76:
            onPasteSelectedPrompt?()
        case 34 where event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command):
            onPreviewSelectedPrompt?()
        default:
            super.sendEvent(event)
        }
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 125:
            onMoveSelection?(1)
        case 126:
            onMoveSelection?(-1)
        case 36, 76:
            onPasteSelectedPrompt?()
        case 34 where event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command):
            onPreviewSelectedPrompt?()
        default:
            super.keyDown(with: event)
        }
    }
}
