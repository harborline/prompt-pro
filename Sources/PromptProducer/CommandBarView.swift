import PromptProducerCore
import SwiftUI

struct CommandBarView: View {
    @ObservedObject var model: PromptLibraryModel
    let onPreview: () -> Void
    let onAccept: () -> Void
    let onCopy: (Prompt) -> Void
    let onClose: () -> Void
    @AppStorage(AppPreferenceKeys.promptSelectionBehavior) private var promptSelectionBehavior = PromptSelectionBehavior.copyAndPaste.rawValue
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchHeader

            Divider().overlay(NordTheme.separator)

            if model.searchResults.isEmpty {
                ContentUnavailableView(
                    "No matching prompts",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different phrase or add a prompt in the library.")
                )
                .foregroundStyle(NordTheme.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    List(model.searchResults) { result in
                        Button {
                            copyAndClose(result.prompt)
                        } label: {
                            CommandResultRow(
                                result: result,
                                isSelected: result.prompt.id == model.selectedPromptID
                            )
                        }
                        .buttonStyle(.plain)
                        .id(result.prompt.id)
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .onChange(of: model.selectedPromptID) { _, selectedPromptID in
                        guard let selectedPromptID else {
                            return
                        }

                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(selectedPromptID, anchor: .center)
                        }
                    }
                }
            }

            Divider().overlay(NordTheme.separator)

            HStack {
                Text(model.searchStatus)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer()

                Button {
                    onPreview()
                } label: {
                    Label("Preview", systemImage: "info.circle")
                }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(model.selectedPrompt == nil && model.searchResults.isEmpty)

                Text(returnBehaviorLabel)
            }
            .font(.caption)
            .foregroundStyle(NordTheme.secondaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                Rectangle().fill(NordTheme.background.opacity(0.74))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NordTheme.commandBarWindowRadius, style: .continuous))
        .foregroundStyle(NordTheme.text)
        .tint(NordTheme.accent)
        .onAppear {
            searchFocused = true
            if model.searchResults.isEmpty {
                model.searchQuery = ""
            }
        }
        .onSubmit {
            onAccept()
        }
        .onMoveCommand { direction in
            switch direction {
            case .down:
                model.selectNextResult()
            case .up:
                model.selectPreviousResult()
            default:
                break
            }
        }
        .onExitCommand {
            onClose()
        }
        .frame(width: 760, height: 480)
    }

    private var returnBehaviorLabel: String {
        PromptSelectionBehavior
            .resolved(from: promptSelectionBehavior)
            .enterPastesIntoPreviousApplication
            ? "Return pastes"
            : "Return copies"
    }

    private var searchHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.title3)
                .foregroundStyle(NordTheme.secondaryText)

            TextField("Search saved prompts", text: $model.searchQuery)
                .font(.title3)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .foregroundStyle(NordTheme.text)

            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(NordTheme.secondaryText)
            .help("Close")
        }
        .padding(16)
    }

    private func copyAndClose(_ prompt: Prompt) {
        onCopy(prompt)
    }
}

private struct CommandResultRow: View {
    let result: PromptSearchResult
    var isSelected = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "text.quote")
                .font(.title3)
                .foregroundStyle(isSelected ? NordTheme.frost0 : NordTheme.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(result.prompt.title)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(NordTheme.text)

                    Spacer()

                    Text(result.reason)
                        .font(.caption)
                        .foregroundStyle(isSelected ? NordTheme.frost1 : NordTheme.secondaryText)
                }

                Text(result.prompt.preview)
                    .font(.subheadline)
                    .foregroundStyle(NordTheme.secondaryText)
                    .lineLimit(2)

                if !result.prompt.tags.isEmpty {
                    Text(result.prompt.tags.joined(separator: "  "))
                        .font(.caption)
                        .foregroundStyle(NordTheme.tertiaryText)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: NordTheme.radius, style: .continuous)
                    .strokeBorder(NordTheme.selectedStroke)
            }
        }
        .contentShape(Rectangle())
    }
}
