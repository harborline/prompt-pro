import AppKit
import Combine
import Foundation
import PromptProducerCore

@MainActor
final class PromptLibraryModel: ObservableObject {
    @Published private(set) var prompts: [Prompt] = []
    @Published var searchQuery = "" {
        didSet {
            refreshSearch()
        }
    }
    @Published private(set) var searchResults: [PromptSearchResult] = []
    @Published var selectedPromptID: UUID?
    @Published private(set) var statusMessage = "Ready"
    @Published private(set) var searchStatus = "Using Fuse.js fuzzy search"
    @Published private(set) var isIndexing = false

    private let store: PromptLibraryStore

    init(store: PromptLibraryStore = PromptLibraryStore()) {
        self.store = store
    }

    var selectedPrompt: Prompt? {
        guard let selectedPromptID else {
            return nil
        }

        return prompts.first { $0.id == selectedPromptID }
    }

    func load() {
        do {
            prompts = try store.loadPrompts().sorted { $0.updatedAt > $1.updatedAt }
            selectedPromptID = selectedPromptID ?? prompts.first?.id
            refreshSearch()
            AppLog.storage.info("Loaded \(self.prompts.count) prompts")
        } catch {
            statusMessage = "Could not load prompts: \(error.localizedDescription)"
            AppLog.storage.error("Load failed: \(error.localizedDescription, privacy: .public)")
            SentryObservability.capture(error, context: "prompt_library_load")
        }
    }

    func addPrompt() {
        let prompt = Prompt(
            title: "Untitled prompt",
            body: "",
            tags: []
        )
        prompts.insert(prompt, at: 0)
        selectedPromptID = prompt.id
        persistPrompts()
    }

    func updatePrompt(id: UUID, title: String, body: String, tagsText: String) {
        guard let index = prompts.firstIndex(where: { $0.id == id }) else {
            return
        }

        prompts[index].title = title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Untitled prompt"
            : title.trimmingCharacters(in: .whitespacesAndNewlines)
        prompts[index].body = body
        prompts[index].tags = tagsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        prompts[index].updatedAt = Date()
        prompts.sort { $0.updatedAt > $1.updatedAt }
        persistPrompts()
    }

    func deleteSelectedPrompt() {
        guard let selectedPromptID else {
            return
        }

        prompts.removeAll { $0.id == selectedPromptID }
        self.selectedPromptID = prompts.first?.id
        persistPrompts()
    }

    func copyPrompt(_ prompt: Prompt, context: PromptInvocationContext? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(PromptInvocationFormatter.compose(prompt: prompt, context: context), forType: .string)
        statusMessage = context == nil
            ? "Copied \(prompt.title)"
            : "Copied \(prompt.title) with context"
    }

    func reloadSearch() {
        searchStatus = "Using Fuse.js fuzzy search"
        refreshSearch()
    }

    func selectNextResult() {
        moveSelection(delta: 1)
    }

    func selectPreviousResult() {
        moveSelection(delta: -1)
    }

    private func moveSelection(delta: Int) {
        guard !searchResults.isEmpty else {
            return
        }

        let currentIndex = selectedPromptID.flatMap { id in
            searchResults.firstIndex { $0.prompt.id == id }
        } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), searchResults.count - 1)
        selectedPromptID = searchResults[nextIndex].prompt.id
    }

    private func persistPrompts() {
        do {
            try store.savePrompts(prompts)
            refreshSearch()
            statusMessage = "Saved"
        } catch {
            statusMessage = "Could not save prompts: \(error.localizedDescription)"
            AppLog.storage.error("Save failed: \(error.localizedDescription, privacy: .public)")
            SentryObservability.capture(error, context: "prompt_library_save")
        }
    }

    private func refreshSearch() {
        let query = searchQuery
        let currentPrompts = prompts
        searchResults = PromptSearchEngine.fuzzyResults(query: query, prompts: currentPrompts)
        searchStatus = "Using Fuse.js fuzzy search"

        if selectedPromptID == nil || !searchResults.contains(where: { $0.prompt.id == selectedPromptID }) {
            selectedPromptID = searchResults.first?.prompt.id
        }
    }
}
