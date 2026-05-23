import Foundation

public struct Prompt: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var tags: [String]
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        body: String,
        tags: [String] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.body = body
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var searchableText: String {
        ([title, body] + tags).joined(separator: "\n")
    }

    public var preview: String {
        let trimmed = body.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 130 else {
            return trimmed
        }

        return String(trimmed.prefix(127)) + "..."
    }
}
