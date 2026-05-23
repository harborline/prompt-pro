import AppKit
import SwiftUI

struct MenuBarExtraView: View {
    @ObservedObject var model: PromptLibraryModel
    @ObservedObject var coordinator: AppCoordinator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Command Bar") {
            coordinator.showCommandBar()
        }

        Button("Preview Prompt") {
            coordinator.showSelectedPromptPreview()
        }
        .disabled(model.selectedPrompt == nil && model.searchResults.isEmpty)

        Button("Open Prompt Library") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("New Prompt") {
            openWindow(id: "main")
            model.addPrompt()
            coordinator.showPromptLibraryWindow()
        }

        Divider()

        Text(model.searchStatus)

        SettingsLink {
            Text("Settings")
        }

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
    }
}
