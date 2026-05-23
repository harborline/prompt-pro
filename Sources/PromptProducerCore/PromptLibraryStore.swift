import Foundation

public struct PromptLibraryStore: Sendable {
    public let promptsURL: URL
    public let vectorsURL: URL
    private let insertsSeedPrompts: Bool

    public init(baseDirectory: URL? = nil, insertsSeedPrompts: Bool = true) {
        let directory = baseDirectory ?? FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("Prompt Producer", isDirectory: true)

        promptsURL = directory.appendingPathComponent("prompts.json")
        vectorsURL = directory.appendingPathComponent("prompt-vectors.json")
        self.insertsSeedPrompts = insertsSeedPrompts
    }

    public func loadPrompts() throws -> [Prompt] {
        guard FileManager.default.fileExists(atPath: promptsURL.path) else {
            let prompts = insertsSeedPrompts ? Self.seedPrompts : []
            try savePrompts(prompts)
            return prompts
        }

        let data = try Data(contentsOf: promptsURL)
        let prompts = try JSONDecoder.promptProducer.decode([Prompt].self, from: data)
        let mergedPrompts = insertsSeedPrompts ? Self.mergingMissingSeedPrompts(into: prompts) : prompts

        if mergedPrompts != prompts {
            try savePrompts(mergedPrompts)
        }

        return mergedPrompts
    }

    public func savePrompts(_ prompts: [Prompt]) throws {
        try ensureDirectory()
        let data = try JSONEncoder.promptProducer.encode(prompts)
        try data.write(to: promptsURL, options: [.atomic])
    }

    public func loadVectorRecords() throws -> [PromptVectorRecord] {
        guard FileManager.default.fileExists(atPath: vectorsURL.path) else {
            return []
        }

        let data = try Data(contentsOf: vectorsURL)
        return try JSONDecoder.promptProducer.decode([PromptVectorRecord].self, from: data)
    }

    public func saveVectorRecords(_ records: [PromptVectorRecord]) throws {
        try ensureDirectory()
        let data = try JSONEncoder.promptProducer.encode(records)
        try data.write(to: vectorsURL, options: [.atomic])
    }

    private func ensureDirectory() throws {
        try FileManager.default.createDirectory(
            at: promptsURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }

    public static let seedPrompts: [Prompt] = [
        Prompt(
            title: "Refine a rough idea",
            body: "Turn this rough idea into a clear, practical implementation plan. Call out assumptions, risks, and the smallest useful first version:\n\n",
            tags: ["planning", "product"]
        ),
        Prompt(
            title: "Code review checklist",
            body: "Review this code for correctness, maintainability, performance, and missing tests. Prioritize concrete bugs and behavioral risks over style comments:\n\n",
            tags: ["engineering", "review"]
        ),
        Prompt(
            title: "Summarize meeting notes",
            body: "Summarize these notes into decisions, open questions, owners, and next actions. Keep it concise and preserve dates and names exactly:\n\n",
            tags: ["summary", "work"]
        ),
        Prompt(
            title: "Rewrite for clarity",
            body: "Rewrite the following text so it is clear, direct, and easy to scan. Preserve the original meaning, names, dates, and technical constraints:\n\n",
            tags: ["writing", "editing"]
        ),
        Prompt(
            title: "Debug systematically",
            body: "Help me debug this issue systematically. Identify the likely failure points, the smallest useful reproduction, what evidence to gather, and the next commands or checks to run:\n\n",
            tags: ["debugging", "engineering"]
        ),
        Prompt(
            title: "Turn notes into tasks",
            body: "Turn these notes into a prioritized task list with owners, dependencies, and acceptance criteria. Separate confirmed work from assumptions:\n\n",
            tags: ["project", "planning"]
        ),
        Prompt(
            title: "Draft a product spec",
            body: "Create a concise product spec from the context below. Include goal, users, scope, non-goals, key flows, edge cases, telemetry, and acceptance criteria:\n\n",
            tags: ["product", "spec"]
        ),
        Prompt(
            title: "Generate test cases",
            body: "Generate focused test cases for this behavior. Cover the happy path, boundary conditions, failure modes, permissions, persistence, and regression risks:\n\n",
            tags: ["testing", "engineering"]
        ),
        Prompt(
            title: "Explain a codebase",
            body: "Explain this codebase or module for a new engineer. Cover architecture, important files, data flow, extension points, and the first places to inspect when debugging:\n\n",
            tags: ["engineering", "onboarding"]
        ),
        Prompt(
            title: "Create release notes",
            body: "Write release notes from these changes. Group them into user-facing improvements, fixes, technical changes, and any migration or rollout notes:\n\n",
            tags: ["release", "writing"]
        ),
        Prompt(
            title: "Compare options",
            body: "Compare the options below. Use a practical decision matrix with tradeoffs, risks, implementation cost, maintenance cost, and a recommended default:\n\n",
            tags: ["decision", "planning"]
        )
    ]

    private static func mergingMissingSeedPrompts(into prompts: [Prompt]) -> [Prompt] {
        let existingKeys = Set(prompts.map { seedKey(for: $0) })
        let missingSeedPrompts = seedPrompts.filter { !existingKeys.contains(seedKey(for: $0)) }
        return prompts + missingSeedPrompts
    }

    private static func seedKey(for prompt: Prompt) -> String {
        "\(prompt.title)\n\(prompt.body)"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}

private extension JSONEncoder {
    static var promptProducer: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

private extension JSONDecoder {
    static var promptProducer: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
