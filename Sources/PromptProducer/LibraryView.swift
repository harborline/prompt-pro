import PromptProducerCore
import SwiftUI

struct LibraryView: View {
    @ObservedObject var model: PromptLibraryModel
    let onClose: () -> Void
    let onPreview: (PromptPreview) -> Void
    private let outerPadding: CGFloat = 14

    var body: some View {
        ZStack(alignment: .topTrailing) {
            NavigationSplitView {
                VStack(spacing: 12) {
                    HStack {
                        Label("Prompt Producer", systemImage: "text.quote")
                            .font(.headline)
                            .foregroundStyle(NordTheme.text)

                        Spacer()

                        Button {
                            model.addPrompt()
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 48, height: 28)
                                .background(NordTheme.elevatedPanel, in: RoundedRectangle(cornerRadius: NordTheme.controlRadius, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: NordTheme.controlRadius, style: .continuous)
                                        .strokeBorder(NordTheme.separator)
                                }
                        }
                        .buttonStyle(.plain)
                        .help("New Prompt")
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(NordTheme.secondaryText)

                        TextField("Search prompts", text: $model.searchQuery)
                            .textFieldStyle(.plain)
                            .foregroundStyle(NordTheme.text)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(NordTheme.field, in: RoundedRectangle(cornerRadius: NordTheme.controlRadius, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: NordTheme.controlRadius, style: .continuous)
                            .strokeBorder(NordTheme.separator)
                    }

                    List(model.searchResults, selection: $model.selectedPromptID) { result in
                        PromptResultRow(result: result, isSelected: result.prompt.id == model.selectedPromptID)
                            .listRowBackground(
                                result.prompt.id == model.selectedPromptID
                                    ? NordTheme.selectedFill
                                    : NordTheme.panel
                            )
                    }
                    .listStyle(.sidebar)
                    .scrollContentBackground(.hidden)
                    .background(NordTheme.panel)

                    StatusFooter(model: model)
                }
                .padding(.horizontal, outerPadding)
                .padding(.top, outerPadding)
                .padding(.bottom, outerPadding)
                .background(NordTheme.panel)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
            } detail: {
                if let prompt = model.selectedPrompt {
                    PromptEditorView(prompt: prompt) { title, body, tags in
                        model.updatePrompt(id: prompt.id, title: title, body: body, tagsText: tags)
                    } onDelete: {
                        model.deleteSelectedPrompt()
                    } onCopy: {
                        model.copyPrompt(prompt)
                    } onPreview: { preview in
                        onPreview(preview)
                    }
                    .id(prompt.id)
                } else {
                    ContentUnavailableView(
                        "No Prompt Selected",
                        systemImage: "text.quote",
                        description: Text("Create a prompt or choose one from the library.")
                    )
                    .foregroundStyle(NordTheme.secondaryText)
                    .background(NordTheme.background)
                }
            }

            CloseWindowButton(onClose: onClose)
                .padding(.top, 24)
                .padding(.trailing, 22)
        }
        .background(NordTheme.background)
        .tint(NordTheme.accent)
        .ignoresSafeArea(.container, edges: .top)
    }
}

private struct StatusFooter: View {
    @ObservedObject var model: PromptLibraryModel

    var body: some View {
        HStack(spacing: 8) {
            if model.isIndexing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(NordTheme.secondaryText)
            }

            Text(model.searchStatus)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()
        }
        .font(.caption)
        .foregroundStyle(NordTheme.secondaryText)
    }
}

private struct CloseWindowButton: View {
    let onClose: () -> Void

    var body: some View {
        Button {
            onClose()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(NordTheme.secondaryText)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help("Close Window")
    }
}

struct PromptResultRow: View {
    let result: PromptSearchResult
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(result.prompt.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .foregroundStyle(NordTheme.text)

                Spacer()

                Text(result.reason)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? NordTheme.frost1 : NordTheme.secondaryText)
            }

            Text(result.prompt.preview)
                .font(.caption)
                .foregroundStyle(NordTheme.secondaryText)
                .lineLimit(2)

            if !result.prompt.tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(result.prompt.tags.prefix(3), id: \.self) { tag in
                        Text(tag)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .foregroundStyle(NordTheme.snow1)
                            .background(NordTheme.polarNight3.opacity(0.72), in: Capsule())
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct PromptEditorView: View {
    @Environment(\.colorScheme) private var colorScheme
    let prompt: Prompt
    let onSave: (String, String, String) -> Void
    let onDelete: () -> Void
    let onCopy: () -> Void
    let onPreview: (PromptPreview) -> Void

    @State private var title: String
    @State private var bodyText: String
    @State private var tagsText: String

    init(
        prompt: Prompt,
        onSave: @escaping (String, String, String) -> Void,
        onDelete: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onPreview: @escaping (PromptPreview) -> Void
    ) {
        self.prompt = prompt
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCopy = onCopy
        self.onPreview = onPreview
        _title = State(initialValue: prompt.title)
        _bodyText = State(initialValue: prompt.body)
        _tagsText = State(initialValue: prompt.tags.joined(separator: ", "))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("Prompt title", text: $title)
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                    .foregroundStyle(NordTheme.text)

                Spacer()

                Button {
                    onPreview(draftPreview)
                } label: {
                    Image(systemName: "info.circle")
                }
                .keyboardShortcut("i", modifiers: [.command])
                .help("Preview Prompt")

                Button {
                    onCopy()
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .help("Delete Prompt")
            }

            TextField("Tags, comma separated", text: $tagsText)
                .textFieldStyle(.roundedBorder)
                .foregroundStyle(NordTheme.text)

            VStack(alignment: .leading, spacing: 0) {
                BlockNoteEditorView(markdown: $bodyText, colorScheme: colorScheme, aiConfig: aiConfig)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NordTheme.background, in: RoundedRectangle(cornerRadius: NordTheme.radius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: NordTheme.radius, style: .continuous)
                        .strokeBorder(NordTheme.separator)
                }

            HStack {
                Text("Updated \(prompt.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(NordTheme.secondaryText)

                Spacer()

                Button {
                    onSave(title, bodyText, tagsText)
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .keyboardShortcut("s", modifiers: [.command])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .background(NordTheme.background)
        .foregroundStyle(NordTheme.text)
        .tint(NordTheme.accent)
    }

    private var aiConfig: LocalAIConfig {
        LocalAIConfig()
    }

    private var draftPreview: PromptPreview {
        PromptPreview(
            id: prompt.id,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Untitled prompt"
                : title.trimmingCharacters(in: .whitespacesAndNewlines),
            body: bodyText,
            tags: parsedTags,
            updatedAt: prompt.updatedAt
        )
    }

    private var parsedTags: [String] {
        tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
