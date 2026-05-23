import CryptoKit
import Foundation

public struct PromptSearchResult: Identifiable, Equatable, Sendable {
    public var id: UUID { prompt.id }
    public var prompt: Prompt
    public var score: Double
    public var reason: String

    public init(prompt: Prompt, score: Double, reason: String) {
        self.prompt = prompt
        self.score = score
        self.reason = reason
    }
}

public struct PromptVectorRecord: Codable, Equatable, Sendable {
    public var promptID: UUID
    public var contentHash: String
    public var vectorSpace: String
    public var vector: [Double]
    public var updatedAt: Date

    public init(promptID: UUID, contentHash: String, vectorSpace: String = "default", vector: [Double], updatedAt: Date = Date()) {
        self.promptID = promptID
        self.contentHash = contentHash
        self.vectorSpace = vectorSpace
        self.vector = vector
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case promptID
        case contentHash
        case vectorSpace
        case vector
        case updatedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        promptID = try container.decode(UUID.self, forKey: .promptID)
        contentHash = try container.decode(String.self, forKey: .contentHash)
        vectorSpace = try container.decodeIfPresent(String.self, forKey: .vectorSpace) ?? "default"
        vector = try container.decode([Double].self, forKey: .vector)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}

public enum PromptSearchEngine {
    public static func contentHash(for prompt: Prompt) -> String {
        let digest = SHA256.hash(data: Data(prompt.searchableText.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    public static func fuzzyResults(query: String, prompts: [Prompt]) -> [PromptSearchResult] {
        let tokens = normalizedTokens(in: query)

        guard !tokens.isEmpty else {
            return prompts
                .sorted { $0.updatedAt > $1.updatedAt }
                .map { PromptSearchResult(prompt: $0, score: 1, reason: "Recent") }
        }

        if let fuseResults = FusePromptSearch.results(query: query, prompts: prompts) {
            return fuseResults
        }

        return swiftFuzzyResults(query: query, prompts: prompts)
    }

    public static func lexicalResults(query: String, prompts: [Prompt]) -> [PromptSearchResult] {
        fuzzyResults(query: query, prompts: prompts)
    }

    private static func swiftFuzzyResults(query: String, prompts: [Prompt]) -> [PromptSearchResult] {
        let tokens = normalizedTokens(in: query)

        return prompts.compactMap { prompt in
            let title = prompt.title.lowercased()
            let body = prompt.body.lowercased()
            let tags = prompt.tags.map { $0.lowercased() }
            let searchableTokens = normalizedTokens(in: prompt.searchableText)
            var score = 0.0
            var usedFuzzyMatch = false

            for token in tokens {
                if title.contains(token) {
                    score += 4
                }

                if tags.contains(where: { $0.contains(token) }) {
                    score += 3
                }

                if body.contains(token) {
                    score += 1
                }

                let bestFuzzyScore = searchableTokens
                    .map { fuzzyScore(query: token, candidate: $0) }
                    .max() ?? 0

                if bestFuzzyScore >= 0.68 {
                    score += bestFuzzyScore * 2.4
                    usedFuzzyMatch = true
                }
            }

            guard score > 0 else {
                return nil
            }

            return PromptSearchResult(prompt: prompt, score: score, reason: usedFuzzyMatch ? "Fuzzy" : "Keyword")
        }
        .sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.prompt.title.localizedCaseInsensitiveCompare(rhs.prompt.title) == .orderedAscending
            }

            return lhs.score > rhs.score
        }
    }

    private static func normalizedTokens(in query: String) -> [String] {
        query
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 1 }
    }

    private static func fuzzyScore(query: String, candidate: String) -> Double {
        guard !query.isEmpty, !candidate.isEmpty else {
            return 0
        }

        if candidate.contains(query) {
            return min(1, Double(query.count) / Double(candidate.count) + 0.35)
        }

        let distance = levenshteinDistance(query, candidate)
        let longest = max(query.count, candidate.count)
        guard longest > 0 else {
            return 0
        }

        return max(0, 1 - (Double(distance) / Double(longest)))
    }

    private static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let lhsCharacters = Array(lhs)
        let rhsCharacters = Array(rhs)
        var previousRow = Array(0...rhsCharacters.count)

        for (lhsIndex, lhsCharacter) in lhsCharacters.enumerated() {
            var currentRow = [lhsIndex + 1]

            for (rhsIndex, rhsCharacter) in rhsCharacters.enumerated() {
                let insertion = currentRow[rhsIndex] + 1
                let deletion = previousRow[rhsIndex + 1] + 1
                let substitution = previousRow[rhsIndex] + (lhsCharacter == rhsCharacter ? 0 : 1)
                currentRow.append(min(insertion, deletion, substitution))
            }

            previousRow = currentRow
        }

        return previousRow.last ?? 0
    }
}
