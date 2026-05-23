import Foundation
import Testing
@testable import PromptProducerCore

@Suite("Prompt library and search")
struct PromptProducerCoreTests {
    @Test("prompt store round trips prompts and vector records")
    func promptStoreRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PromptLibraryStore(baseDirectory: directory, insertsSeedPrompts: false)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let prompt = Prompt(
            title: "Debug crash",
            body: "Find the root cause of a Swift crash.",
            tags: ["debug"],
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let record = PromptVectorRecord(promptID: prompt.id, contentHash: "abc", vectorSpace: "test", vector: [0.1, 0.2], updatedAt: timestamp)

        try store.savePrompts([prompt])
        try store.saveVectorRecords([record])

        #expect(try store.loadPrompts() == [prompt])
        #expect(try store.loadVectorRecords() == [record])
    }

    @Test("store merges missing seed prompts without replacing existing prompts")
    func storeMergesMissingSeeds() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = PromptLibraryStore(baseDirectory: directory)
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let customPrompt = Prompt(
            title: "Custom",
            body: "Keep this prompt.",
            tags: ["personal"],
            createdAt: timestamp,
            updatedAt: timestamp
        )

        try store.savePrompts([customPrompt])

        let loadedPrompts = try store.loadPrompts()

        #expect(loadedPrompts.contains(customPrompt))
        #expect(loadedPrompts.count == PromptLibraryStore.seedPrompts.count + 1)
    }

    @Test("Fuse fuzzy search scores titles above body matches")
    func fuzzySearchScoring() {
        let prompts = [
            Prompt(title: "Refactor SwiftUI", body: "Improve layout.", tags: ["macos"]),
            Prompt(title: "Meeting summary", body: "Summarize SwiftUI layout risks.", tags: ["notes"])
        ]

        let results = PromptSearchEngine.fuzzyResults(query: "swiftui", prompts: prompts)

        #expect(results.map(\.prompt.title) == ["Refactor SwiftUI", "Meeting summary"])
    }

    @Test("Fuse fuzzy search checks titles, bodies, and tags")
    func fuzzySearchChecksPromptFields() {
        let titlePrompt = Prompt(title: "Plan onboarding", body: "Make it calm.", tags: ["people"])
        let bodyPrompt = Prompt(title: "Draft memo", body: "Turn onboarding notes into a checklist.", tags: ["writing"])
        let tagPrompt = Prompt(title: "Triage issue", body: "Find likely failure points.", tags: ["onboarding"])
        let results = PromptSearchEngine.fuzzyResults(query: "onboarding", prompts: [bodyPrompt, tagPrompt, titlePrompt])

        #expect(results.map(\.prompt.id).contains(titlePrompt.id))
        #expect(results.map(\.prompt.id).contains(bodyPrompt.id))
        #expect(results.map(\.prompt.id).contains(tagPrompt.id))
    }

    @Test("fuzzy search tolerates typo queries")
    func fuzzySearchToleratesTypoQueries() {
        let prompts = [
            Prompt(title: "Apple prompt", body: "Create a prompt for Apple platforms.", tags: ["macos"]),
            Prompt(title: "Banana prompt", body: "Write about fruit.", tags: ["food"])
        ]

        let results = PromptSearchEngine.fuzzyResults(query: "aple", prompts: prompts)

        #expect(results.first?.prompt.title == "Apple prompt")
        #expect(results.first?.reason == "Fuzzy")
    }

    @Test("prompt invocation appends captured page context")
    func promptInvocationAppendsCapturedPageContext() {
        let prompt = Prompt(title: "Summarize", body: "Summarize the relevant text.", tags: [])
        let context = PromptInvocationContext(source: "Safari", text: "A page about Mac App Store screenshots.")

        let body = PromptInvocationFormatter.compose(prompt: prompt, context: context)

        #expect(body.contains("Summarize the relevant text."))
        #expect(body.contains("Context from Safari:"))
        #expect(body.contains("A page about Mac App Store screenshots."))
    }

    @Test("prompt invocation omits empty context")
    func promptInvocationOmitsEmptyContext() {
        let prompt = Prompt(title: "Summarize", body: "Summarize the relevant text.", tags: [])

        #expect(PromptInvocationFormatter.compose(prompt: prompt, context: nil) == "Summarize the relevant text.")
        #expect(PromptInvocationFormatter.compose(prompt: prompt, context: PromptInvocationContext(text: "  \n")) == "Summarize the relevant text.")
    }
}
