import Foundation

public struct PromptInvocationContext: Equatable, Sendable {
    public var source: String?
    public var text: String

    public init(source: String? = nil, text: String) {
        self.source = source
        self.text = text
    }
}

public enum PromptInvocationFormatter {
    public static let maximumContextLength = 12_000

    public static func compose(prompt: Prompt, context: PromptInvocationContext?) -> String {
        compose(promptBody: prompt.body, context: context)
    }

    public static func compose(promptBody: String, context: PromptInvocationContext?) -> String {
        let trimmedPrompt = promptBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let context,
              !context.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return trimmedPrompt
        }

        let trimmedContext = truncated(context.text.trimmingCharacters(in: .whitespacesAndNewlines))
        let source = context.source?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        let contextHeading = source.map { "Context from \($0)" } ?? "Context from the current page or input"

        return """
        \(trimmedPrompt)

        ---

        \(contextHeading):
        \(trimmedContext)
        """
    }

    private static func truncated(_ value: String) -> String {
        guard value.count > maximumContextLength else {
            return value
        }

        return "\(value.prefix(maximumContextLength))\n[Context truncated]"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
