import AppKit

extension NSWindow {
    func applyPromptProducerChrome(hidesStandardButtons: Bool = true) {
        title = ""
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        styleMask.insert(.fullSizeContentView)
        toolbar = nil
        toolbarStyle = .unifiedCompact
        isMovableByWindowBackground = true

        guard hidesStandardButtons else {
            return
        }

        hidePromptProducerStandardButtons()

        DispatchQueue.main.async { [weak self] in
            self?.hidePromptProducerStandardButtons()
        }
    }

    private func hidePromptProducerStandardButtons() {
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }
}
