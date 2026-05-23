import Foundation
import JavaScriptCore

enum FusePromptSearch {
    static func results(query: String, prompts: [Prompt]) -> [PromptSearchResult]? {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return nil
        }

        guard let fuseSource = bundledFuseSource(),
              let documentsJSON = documentsJSON(for: prompts),
              let context = JSContext() else {
            return nil
        }

        var exceptionMessage: String?
        context.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString()
        }

        context.evaluateScript(fuseSource)
        guard exceptionMessage == nil else {
            return nil
        }

        context.setObject(documentsJSON, forKeyedSubscript: "promptProducerDocumentsJSON" as NSString)
        context.setObject(trimmedQuery, forKeyedSubscript: "promptProducerQuery" as NSString)

        guard let json = context.evaluateScript(searchScript)?.toString(),
              exceptionMessage == nil,
              let data = json.data(using: .utf8),
              let fuseResults = try? JSONDecoder().decode([FuseResult].self, from: data) else {
            return nil
        }

        let promptsByID = Dictionary(uniqueKeysWithValues: prompts.map { ($0.id.uuidString, $0) })
        return fuseResults.compactMap { result in
            guard let prompt = promptsByID[result.item.id] else {
                return nil
            }

            let rawScore = min(max(result.score ?? 1, 0), 1)
            return PromptSearchResult(
                prompt: prompt,
                score: 1 - rawScore,
                reason: "Fuzzy"
            )
        }
    }

    private static func bundledFuseSource() -> String? {
        guard let url = Bundle.module.url(
            forResource: "fuse.basic.min",
            withExtension: "js",
            subdirectory: "Fuse"
        ) else {
            return nil
        }

        return try? String(contentsOf: url, encoding: .utf8)
    }

    private static func documentsJSON(for prompts: [Prompt]) -> String? {
        let documents = prompts.map { prompt in
            FuseDocument(
                id: prompt.id.uuidString,
                title: prompt.title,
                body: prompt.body,
                tags: prompt.tags
            )
        }

        guard let data = try? JSONEncoder().encode(documents) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }

    private static let searchScript = """
    (function() {
        const documents = JSON.parse(promptProducerDocumentsJSON);
        const fuse = new Fuse(documents, {
            includeScore: true,
            ignoreLocation: true,
            shouldSort: true,
            threshold: 0.42,
            minMatchCharLength: 2,
            keys: [
                { name: "title", weight: 0.5 },
                { name: "tags", weight: 0.3 },
                { name: "body", weight: 0.2 }
            ]
        });

        return JSON.stringify(fuse.search(promptProducerQuery));
    })()
    """
}

private struct FuseDocument: Encodable {
    var id: String
    var title: String
    var body: String
    var tags: [String]
}

private struct FuseResult: Decodable {
    var item: FuseItem
    var score: Double?
}

private struct FuseItem: Decodable {
    var id: String
}
