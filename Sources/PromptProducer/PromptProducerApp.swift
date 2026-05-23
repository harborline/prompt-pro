import AppKit
import SwiftUI

@main
struct PromptProducerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model: PromptLibraryModel
    @StateObject private var coordinator: AppCoordinator
    @AppStorage(AppPreferenceKeys.theme) private var selectedTheme = AppTheme.system.rawValue
    @AppStorage(AppPreferenceKeys.hideMenuBarIcon) private var hideMenuBarIcon = false

    private var preferredColorScheme: ColorScheme? {
        AppTheme.resolved(from: selectedTheme).colorScheme
    }

    private var menuBarIconInserted: Binding<Bool> {
        Binding {
            !hideMenuBarIcon
        } set: { newValue in
            hideMenuBarIcon = !newValue
        }
    }

    init() {
        SentryObservability.start()
        let model = PromptLibraryModel()
        _model = StateObject(wrappedValue: model)
        _coordinator = StateObject(wrappedValue: AppCoordinator(model: model))
    }

    @SceneBuilder
    var body: some Scene {
        Window("Prompt Producer", id: "main") {
            MainLibrarySceneView(
                model: model,
                coordinator: coordinator,
                preferredColorScheme: preferredColorScheme
            )
        }
        .defaultSize(width: 980, height: 680)
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Prompt") {
                    model.addPrompt()
                    coordinator.showPromptLibraryWindow()
                }
            }

            CommandMenu("Prompt Producer") {
                Button("Open Command Bar") {
                    coordinator.showCommandBar()
                }

                Button("Preview Prompt") {
                    coordinator.showSelectedPromptPreview()
                }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(model.selectedPrompt == nil && model.searchResults.isEmpty)
            }
        }

        Settings {
            SettingsView(model: model, coordinator: coordinator)
                .preferredColorScheme(preferredColorScheme)
                .background(NordTheme.background)
                .background(WindowChromeHider())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)

        MenuBarExtra("Prompt Producer", systemImage: "text.quote", isInserted: menuBarIconInserted) {
            MenuBarExtraView(model: model, coordinator: coordinator)
        }
    }
}

private struct MainLibrarySceneView: View {
    @ObservedObject var model: PromptLibraryModel
    @ObservedObject var coordinator: AppCoordinator
    let preferredColorScheme: ColorScheme?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        LibraryView(model: model, onClose: closeKeyWindow) { preview in
            coordinator.showPromptPreview(preview)
        }
        .preferredColorScheme(preferredColorScheme)
        .background(NordTheme.background.ignoresSafeArea())
        .background(WindowChromeHider())
        .tint(NordTheme.accent)
        .toolbar(.hidden, for: .windowToolbar)
        .frame(minWidth: 820, minHeight: 560)
        .task {
            model.load()
            coordinator.start()
        }
        .onAppear {
            coordinator.setOpenPromptLibraryWindowAction {
                openWindow(id: "main")
            }
        }
    }

    private func closeKeyWindow() {
        NSApp.keyWindow?.close()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.lifecycle.info("Prompt Producer launched")
        AppVisibilityPreferences.applyDockIconPreference()
        if !UserDefaults.standard.bool(forKey: AppPreferenceKeys.hideDockIcon) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

private struct WindowChromeHider: NSViewRepresentable {
    func makeNSView(context: Context) -> ChromeHidingView {
        ChromeHidingView()
    }

    func updateNSView(_ nsView: ChromeHidingView, context: Context) {
        nsView.hideWindowChrome()
    }

    final class ChromeHidingView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            hideWindowChrome()
        }

        func hideWindowChrome() {
            guard let window else {
                return
            }

            window.applyPromptProducerChrome()
        }
    }
}
