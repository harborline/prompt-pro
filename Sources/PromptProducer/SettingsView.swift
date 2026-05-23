import AppKit
import KeyboardShortcuts
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: PromptLibraryModel
    @ObservedObject var coordinator: AppCoordinator
    @AppStorage(AppPreferenceKeys.theme) private var selectedTheme = AppTheme.system.rawValue
    @AppStorage(AppPreferenceKeys.promptSelectionBehavior) private var promptSelectionBehavior = PromptSelectionBehavior.copyAndPaste.rawValue
    @AppStorage(AppPreferenceKeys.hideDockIcon) private var hideDockIcon = false
    @AppStorage(AppPreferenceKeys.hideMenuBarIcon) private var hideMenuBarIcon = false
    @AppStorage(AppPreferenceKeys.keepWindowsOnTop) private var keepWindowsOnTop = false
    private let settingsWindowSize = NSSize(width: 420, height: 760)

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Form {
                Section("General") {
                    Picker("Theme", selection: $selectedTheme) {
                        ForEach(AppTheme.allCases) { theme in
                            Text(theme.title).tag(theme.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Hide Dock icon", isOn: $hideDockIcon)
                    Toggle("Hide menu bar icon", isOn: $hideMenuBarIcon)
                    Toggle("Keep windows on top", isOn: $keepWindowsOnTop)
                }

                Section("App Behavior") {
                    KeyboardShortcuts.Recorder("Default hotkey", name: .openCommandBar)

                    Text(coordinator.hotKeyStatus)
                        .font(.caption)
                        .foregroundStyle(NordTheme.secondaryText)

                    KeyboardShortcuts.Recorder("New prompt hotkey", name: .newPrompt)

                    Text(coordinator.newPromptHotKeyStatus)
                        .font(.caption)
                        .foregroundStyle(NordTheme.secondaryText)

                    Picker("Enter key behavior", selection: $promptSelectionBehavior) {
                        ForEach(PromptSelectionBehavior.allCases) { behavior in
                            Text(behavior.title).tag(behavior.rawValue)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }

                Section("Local AI") {
                    LabeledContent("Editor AI", value: "Apple Foundation Models")
                    LabeledContent("Prompt search", value: "Fuse.js fuzzy search")

                    Button {
                        model.reloadSearch()
                    } label: {
                        Label("Refresh Search", systemImage: "checkmark.circle")
                    }

                    Text("Prompt search uses Fuse.js locally across titles, prompt bodies, and tags. No vectorization or remote search endpoint is used.")
                        .font(.caption)
                        .foregroundStyle(NordTheme.secondaryText)
                }

                Section {
                    SettingsFooter()
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.top, 10)

            Button {
                NSApp.keyWindow?.close()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NordTheme.secondaryText)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help("Close Window")
            .padding(.top, 12)
            .padding(.trailing, 18)
        }
        .background(NordTheme.background)
        .foregroundStyle(NordTheme.text)
        .tint(NordTheme.accent)
        .toolbar(.hidden, for: .windowToolbar)
        .ignoresSafeArea(.container, edges: .top)
        .frame(width: settingsWindowSize.width, height: settingsWindowSize.height)
        .background(SettingsWindowSizer(size: settingsWindowSize, keepWindowsOnTop: keepWindowsOnTop))
        .onAppear {
            AppWindowLevelPreferences.applyToOpenWindows(keepWindowsOnTop: keepWindowsOnTop)
        }
        .onChange(of: hideDockIcon) { _, newValue in
            AppVisibilityPreferences.applyDockIconPreference(newValue)
        }
        .onChange(of: keepWindowsOnTop) { _, newValue in
            AppWindowLevelPreferences.applyToOpenWindows(keepWindowsOnTop: newValue)
        }
    }
}

private struct SettingsFooter: View {
    private let supportURL = URL(string: "mailto:help@pdx.software")!
    private let privacyURL = URL(string: "https://pdx.software/privacy")!
    private let termsURL = URL(string: "https://pdx.software/terms")!
    private let githubURL = URL(string: "https://github.com/harborline")!
    private let iconAttributionURL = URL(string: "https://www.flaticon.com/free-icons/command")!

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 14) {
                footerLink("Support", systemImage: "envelope", destination: supportURL)
                footerLink("Privacy", systemImage: "lock", destination: privacyURL)
                footerLink("Terms", systemImage: "doc.text", destination: termsURL)
            }

            HStack(spacing: 10) {
                Text("Copyright © 2026 Harborline")
                    .foregroundStyle(NordTheme.secondaryText)

                Link(destination: githubURL) {
                    Image(systemName: "chevron.left.forwardslash.chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NordTheme.accent)
                        .frame(width: 28, height: 24)
                        .background(NordTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: NordTheme.radius, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("Open Harborline on GitHub")
                .accessibilityLabel("GitHub")
            }
            .font(.caption)

            Link("App Icon created by RIkas Dzihab - Flaticon", destination: iconAttributionURL)
                .font(.caption2)
                .foregroundStyle(NordTheme.secondaryText)
                .buttonStyle(.plain)
                .help("Command icons on Flaticon")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func footerLink(_ title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(NordTheme.accent)
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsWindowSizer: NSViewRepresentable {
    let size: NSSize
    let keepWindowsOnTop: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            applySize(from: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            applySize(from: nsView)
        }
    }

    private func applySize(from view: NSView) {
        guard let window = view.window else {
            return
        }

        AppWindowLevelPreferences.apply(to: window, keepWindowsOnTop: keepWindowsOnTop)
        window.minSize = size
        window.maxSize = NSSize(width: size.width, height: 1200)

        if abs(window.contentLayoutRect.width - size.width) > 1 ||
            window.contentLayoutRect.height < size.height - 1 {
            window.setContentSize(size)
            window.center()
        }
    }
}
