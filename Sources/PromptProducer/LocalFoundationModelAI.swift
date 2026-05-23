import Foundation
import FoundationModels

enum LocalFoundationModelAI {
    private enum PromptAIIntent {
        case create(topic: String)
        case edit
    }

    static func respond(to prompt: String, context: String) async throws -> String {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            throw LocalFoundationModelAIError.emptyPrompt
        }

        guard #available(macOS 26.0, *) else {
            throw LocalFoundationModelAIError.unavailable("Foundation Models requires macOS 26 or newer.")
        }

        return try await respondWithFoundationModels(to: trimmedPrompt, context: context)
    }

    @available(macOS 26.0, *)
    private static func respondWithFoundationModels(to prompt: String, context: String) async throws -> String {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            throw LocalFoundationModelAIError.unavailable(availabilityMessage(for: model.availability))
        }

        AppLog.ai.info("Foundation Models availability=available promptLen=\(prompt.count, privacy: .public) contextLen=\(context.count, privacy: .public)")

        let session = LanguageModelSession(model: model) {
            """
            You are Prompt Producer's on-device prompt writer.
            You create and revise reusable prompts that the user will paste into an LLM.
            You are not a conversational AI. You do not respond directly to the user but simply provide them with the prompt they requested without quotes or commentary.
            Treat the user's request as instructions for what prompt to write or how to edit the current prompt.
            Write direct instruction text for the future AI that will perform the task.
            The future AI is the performer. Do not make the future AI a prompt writer unless the topic is explicitly prompt writing.
            Never return the user's request unchanged.
            Never output a prompt that asks another AI to write a prompt. Output the prompt that makes another AI perform the requested topic or task.
            Never begin with "Write a prompt", "Create a prompt", "Generate a prompt", or "Prompt Writer".
            Return only the final prompt text.
            Do not include assistant conversation, speaker labels, surrounding quotes, markdown code fences, explanations, summaries, or prefaces.
            """
        }

        let request = generationRequest(for: prompt, context: context)
        AppLog.ai.info("Foundation Models generation request len=\(request.count, privacy: .public)")
        let response = try await session.respond(
            to: request,
            options: GenerationOptions(temperature: 0.55, maximumResponseTokens: 900)
        )
        AppLog.ai.info("Foundation Models raw response len=\(response.content.count, privacy: .public)")
        let content = try normalizedPromptOutput(response.content)
        AppLog.ai.info("Foundation Models normalized response len=\(content.count, privacy: .public) needsRegeneration=\(responseNeedsRegeneration(content, request: prompt), privacy: .public)")
        guard responseNeedsRegeneration(content, request: prompt) else {
            return content
        }

        AppLog.ai.info("Local AI response echoed or meta-described the request; retrying with stricter generation instructions.")
        let retryResponse = try await session.respond(
            to: repairRequest(for: prompt, context: context, echoedOutput: content),
            options: GenerationOptions(temperature: 0.6, maximumResponseTokens: 900)
        )
        AppLog.ai.info("Foundation Models retry raw response len=\(retryResponse.content.count, privacy: .public)")
        let retryContent = try normalizedPromptOutput(retryResponse.content)
        AppLog.ai.info("Foundation Models retry normalized response len=\(retryContent.count, privacy: .public) needsRegeneration=\(responseNeedsRegeneration(retryContent, request: prompt), privacy: .public)")
        guard responseNeedsRegeneration(retryContent, request: prompt) else {
            return retryContent
        }

        AppLog.ai.info("Local AI retry was still not a usable final prompt; returning a local prompt template.")
        return fallbackPrompt(for: prompt, context: context)
    }

    private static func generationRequest(for prompt: String, context: String) -> String {
        switch intent(for: prompt) {
        case .create(let topic):
            return """
            Transform this topic or task into direct instruction text for a future AI:
            \(topic)

            Original user request:
            \(prompt)

            Requirements:
            - Output only the instruction text the future AI should follow.
            - The future AI must perform work about "\(topic)"; it must not write, create, generate, or discuss a prompt.
            - Start with a performer role or direct task, such as "You are..." or "Act as...".
            - Include useful context placeholders, constraints, deliverables, output format, and quality criteria.
            - Make the prompt specific to "\(topic)".
            - Do not use unrelated existing editor content.
            - Do not answer the topic directly.
            - Do not include the words "prompt writer" or a first line that starts with "Generate a prompt".
            - Do not include surrounding quotes, labels, summaries, or commentary.
            - Output only the final prompt text.
            """
        case .edit:
            let currentPrompt = context.trimmingCharacters(in: .whitespacesAndNewlines)
            let contextSection = currentPrompt.isEmpty ? "(none)" : currentPrompt

            return """
            Revise the reusable LLM prompt below.

            User edit request:
            \(prompt)

            Current prompt:
            \(contextSection)

            Requirements:
            - Return the revised prompt text, not a conversation with the user.
            - Preserve useful intent from the current prompt while applying the requested change.
            - If the current prompt is empty, write a new reusable prompt that satisfies the edit request.
            - Include useful context, constraints, output expectations, and acceptance criteria when they improve the prompt.
            - Do not answer the prompt's topic directly.
            - Do not include surrounding quotes, labels, summaries, or commentary.
            - Output only the final prompt text.
            """
        }
    }

    private static func repairRequest(for prompt: String, context: String, echoedOutput: String) -> String {
        switch intent(for: prompt) {
        case .create(let topic):
            return """
            Your previous output repeated the user request or produced meta text about creating a prompt.

            Topic or task:
            \(topic)

            User request:
            \(prompt)

            Repeated output to avoid:
            \(echoedOutput)

            Now output direct instruction text for the future AI that will perform work about "\(topic)".
            The first line must start with "You are" or "Act as".
            The role must be a domain specialist for "\(topic)", not "Prompt Writer".
            Do not ask another AI to write, create, or generate a prompt. Write the instructions that make another AI perform the requested topic or task.
            Do not include quotes or commentary. Output only the final prompt text.
            """
        case .edit:
            let currentPrompt = context.trimmingCharacters(in: .whitespacesAndNewlines)
            let contextSection = currentPrompt.isEmpty ? "(none)" : currentPrompt

            return """
            Your previous output repeated or meta-described the user's request instead of revising the current prompt.

            User edit request:
            \(prompt)

            Current prompt:
            \(contextSection)

            Repeated output to avoid:
            \(echoedOutput)

            Now output the actual revised prompt text. It must apply the edit request to the current prompt and be ready to paste into another LLM.
            Do not include quotes or commentary. Output only the final prompt text.
            """
        }
    }

    static func normalizedPromptOutput(_ rawContent: String) throws -> String {
        var content = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        content = stripWrappingCodeFence(from: content)
        content = stripConversationalPrefixes(from: content)
        content = stripConversationalSuffixes(from: content)
        content = stripWrappingQuotes(from: content)
        content = stripConversationalPrefixes(from: content)
        content = stripConversationalSuffixes(from: content)

        guard !content.isEmpty else {
            throw LocalFoundationModelAIError.emptyResponse
        }

        return content
    }

    private static func stripWrappingCodeFence(from content: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        guard let firstLine = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines),
              let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              firstLine.hasPrefix("```"),
              lastLine == "```",
              lines.count >= 2 else {
            return content
        }

        lines.removeFirst()
        lines.removeLast()
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripConversationalPrefixes(from content: String) -> String {
        var output = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = [
            "assistant:",
            "ai:",
            "prompt:",
            "generated prompt:",
            "revised prompt:",
            "output:",
            "here is the prompt:",
            "here's the prompt:",
            "sure, here is the prompt:",
            "certainly, here is the prompt:"
        ]

        var didStripPrefix = true
        while didStripPrefix {
            didStripPrefix = false
            let lowercasedOutput = output.lowercased()
            for prefix in prefixes where lowercasedOutput.hasPrefix(prefix) {
                output = String(output.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStripPrefix = true
                break
            }
        }

        return output
    }

    private static func stripConversationalSuffixes(from content: String) -> String {
        var lines = content.components(separatedBy: .newlines)
        let blockedFragments = [
            "i can generate a prompt",
            "i can help generate a prompt",
            "i can create a prompt",
            "i can help create a prompt",
            "let me know",
            "once you have provided"
        ]

        while let lastLine = lines.last?.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastLine.isEmpty {
            let lowercasedLine = lastLine.lowercased()
            guard blockedFragments.contains(where: { lowercasedLine.contains($0) }) else {
                break
            }

            lines.removeLast()
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripWrappingQuotes(from content: String) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let quotePairs: [(Character, Character)] = [
            ("\"", "\""),
            ("'", "'"),
            ("\u{201C}", "\u{201D}"),
            ("\u{2018}", "\u{2019}")
        ]

        guard let first = trimmed.first,
              let last = trimmed.last,
              quotePairs.contains(where: { pair in pair.0 == first && pair.1 == last }) else {
            return trimmed
        }

        return String(trimmed.dropFirst().dropLast())
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func responseNeedsRegeneration(_ response: String, request: String) -> Bool {
        responseEchoesRequest(response, request: request)
            || responseIsMetaPrompt(response, request: request)
    }

    private static func responseEchoesRequest(_ response: String, request: String) -> Bool {
        let normalizedResponse = compactForComparison(response)
        let normalizedRequest = compactForComparison(request)
        guard !normalizedResponse.isEmpty, !normalizedRequest.isEmpty else {
            return false
        }

        if normalizedResponse == normalizedRequest {
            return true
        }

        let closeLength = Double(normalizedResponse.count) <= Double(normalizedRequest.count) * 1.18
        return closeLength && (
            normalizedResponse.hasPrefix(normalizedRequest)
                || normalizedRequest.hasPrefix(normalizedResponse)
        )
    }

    private static func responseIsMetaPrompt(_ response: String, request: String) -> Bool {
        let normalizedRequest = compactForComparison(request)
        guard normalizedRequest.hasPrefix("write a prompt")
                || normalizedRequest.hasPrefix("create a prompt")
                || normalizedRequest.hasPrefix("generate a prompt")
                || normalizedRequest.hasPrefix("draft a prompt") else {
            return false
        }

        let normalizedResponse = compactForComparison(response)
        return normalizedResponse.hasPrefix("write a prompt")
            || normalizedResponse.hasPrefix("create a prompt")
            || normalizedResponse.hasPrefix("generate a prompt")
            || normalizedResponse.hasPrefix("draft a prompt")
    }

    private static func compactForComparison(_ value: String) -> String {
        value
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func fallbackPrompt(for request: String, context: String) -> String {
        if case .create = intent(for: request) {
            return fallbackNewPrompt(for: request)
        }

        let currentPrompt = context.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentPrompt.isEmpty else {
            return fallbackNewPrompt(for: request)
        }

        let lowercasedRequest = request.lowercased()
        if lowercasedRequest.contains("action item") {
            return """
            \(currentPrompt)

            Action items:
            - Identify the concrete tasks the response should produce.
            - Assign an owner or responsible role for each task when context allows.
            - Include dependencies, risks, and acceptance criteria for completion.
            """
        }

        if lowercasedRequest.contains("concise") || lowercasedRequest.contains("shorten") {
            return """
            \(firstSentences(from: currentPrompt, maximum: 2))

            Keep the response focused on the essential objective, constraints, and expected output.
            """
        }

        if lowercasedRequest.contains("elaborate")
            || lowercasedRequest.contains("expand")
            || lowercasedRequest.contains("detail") {
            return """
            \(currentPrompt)

            Add enough detail to make the response immediately useful:
            - Relevant background and assumptions.
            - Constraints, edge cases, and quality standards.
            - Examples or output structure when helpful.
            - Clear success criteria.
            """
        }

        if lowercasedRequest.contains("tailor") || lowercasedRequest.contains("model") {
            return """
            \(currentPrompt)

            Tailor the response for the target AI model by making instructions explicit, limiting ambiguity, and specifying the expected format, constraints, and evaluation criteria.
            """
        }

        return """
        \(currentPrompt)

        Apply this additional instruction when using the prompt:
        \(request)
        """
    }

    private static func fallbackNewPrompt(for request: String) -> String {
        let topic = topicFromPromptRequest(request)
        return """
        You are an expert assistant specializing in \(topic).

        Help me produce a high-quality result for \(topic). Use the context below, ask for only essential missing details if needed, and otherwise proceed with reasonable assumptions.

        Context:
        [Paste relevant context, goals, audience, platform, constraints, and examples here.]

        Requirements:
        - Identify the primary objective and the intended audience.
        - Call out important constraints, risks, edge cases, and quality standards.
        - Provide a practical, specific output that can be acted on immediately.
        - Keep the response clear, structured, and free of filler.

        Output format:
        - Brief summary of the recommended approach.
        - Detailed steps or deliverables.
        - Acceptance criteria for a successful result.
        - Any follow-up questions only if required to avoid a bad answer.
        """
    }

    private static func firstSentences(from value: String, maximum: Int) -> String {
        let sentences = value
            .components(separatedBy: CharacterSet(charactersIn: ".!?\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(maximum)

        let joined = sentences.joined(separator: ". ")
        guard !joined.isEmpty else {
            return value
        }

        return joined.hasSuffix(".") ? joined : "\(joined)."
    }

    private static func topicFromPromptRequest(_ request: String) -> String {
        let trimmedRequest = request.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercasedRequest = trimmedRequest.lowercased()
        let prefixes = [
            "write a prompt about ",
            "write a prompt for ",
            "create a prompt about ",
            "create a prompt for ",
            "generate a prompt about ",
            "generate a prompt for ",
            "draft a prompt about ",
            "draft a prompt for "
        ]

        for prefix in prefixes where lowercasedRequest.hasPrefix(prefix) {
            let startIndex = trimmedRequest.index(trimmedRequest.startIndex, offsetBy: prefix.count)
            let topic = String(trimmedRequest[startIndex...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !topic.isEmpty {
                return topic
            }
        }

        return trimmedRequest.isEmpty ? "the requested task" : trimmedRequest
    }

    private static func intent(for request: String) -> PromptAIIntent {
        let topic = topicFromPromptRequest(request)
        let compactRequest = compactForComparison(request)
        let createPrefixes = [
            "write a prompt about",
            "write a prompt for",
            "create a prompt about",
            "create a prompt for",
            "generate a prompt about",
            "generate a prompt for",
            "draft a prompt about",
            "draft a prompt for"
        ]

        if createPrefixes.contains(where: { compactRequest.hasPrefix($0) }) {
            return .create(topic: topic)
        }

        return .edit
    }

    @available(macOS 26.0, *)
    private static func availabilityMessage(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "Foundation Models is available."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled."
        case .unavailable(.modelNotReady):
            return "The local Apple Intelligence model is not ready yet."
        case .unavailable(.deviceNotEligible):
            return "This Mac is not eligible for Apple Intelligence."
        @unknown default:
            return "Foundation Models is unavailable."
        }
    }
}

enum LocalFoundationModelAIError: LocalizedError {
    case emptyPrompt
    case emptyResponse
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "Enter an AI request first."
        case .emptyResponse:
            return "Apple Foundation Models returned an empty response."
        case .unavailable(let message):
            return message
        }
    }
}
