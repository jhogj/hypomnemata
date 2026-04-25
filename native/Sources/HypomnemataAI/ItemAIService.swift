import Foundation

public struct ItemAIService: Sendable {
    private let client: any LLMClient
    private let configuration: LLMConfiguration

    public init(client: any LLMClient, configuration: LLMConfiguration = LLMConfiguration()) {
        self.client = client
        self.configuration = configuration
    }

    public func summarize(context: LLMItemContext) async throws -> String {
        let response = try await client.complete(
            messages: try summaryMessages(for: context),
            temperature: 0.2
        )
        return response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func streamSummary(context: LLMItemContext) throws -> AsyncThrowingStream<String, Error> {
        let messages = try summaryMessages(for: context)
        return client.streamChat(messages: messages, temperature: 0.2)
    }

    private func summaryMessages(for context: LLMItemContext) throws -> [LLMMessage] {
        let content = try context.promptContext(limit: configuration.contextCharacterLimit)
        return [
            LLMMessage(
                role: "system",
                content: "Resuma em português, com precisão, sem inventar fatos. Use no máximo 5 frases."
            ),
            LLMMessage(
                role: "user",
                content: "Título: \(context.title?.trimmedNonEmpty ?? "sem título")\n\nConteúdo:\n\(content)"
            ),
        ]
    }

    public func autotags(context: LLMItemContext, existingTags: [String] = []) async throws -> [String] {
        let content = try context.promptContext(limit: configuration.contextCharacterLimit)
        let response = try await client.complete(messages: [
            LLMMessage(
                role: "system",
                content: "Gere até 8 etiquetas curtas em português. Responda somente com JSON array de strings."
            ),
            LLMMessage(
                role: "user",
                content: "Título: \(context.title?.trimmedNonEmpty ?? "sem título")\n\nConteúdo:\n\(content)"
            ),
        ], temperature: 0.1)
        return Self.normalizedTags(from: response, existingTags: existingTags)
    }

    public static func normalizedTags(from response: String, existingTags: [String] = []) -> [String] {
        let generated = parseJSONTags(response) ?? parseLooseTags(response)
        let merged = existingTags + generated
        var seen = Set<String>()
        var normalized: [String] = []
        for tag in merged {
            let value = tag
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "#\"'[]"))
                .lowercased()
            guard !value.isEmpty, !seen.contains(value) else {
                continue
            }
            seen.insert(value)
            normalized.append(value)
            if normalized.count == 8 {
                break
            }
        }
        return normalized
    }

    private static func parseJSONTags(_ response: String) -> [String]? {
        guard let data = response.data(using: .utf8),
              let tags = try? JSONDecoder().decode([String].self, from: data)
        else {
            return nil
        }
        return tags
    }

    private static func parseLooseTags(_ response: String) -> [String] {
        response
            .replacingOccurrences(of: "\n", with: ",")
            .split(separator: ",")
            .map(String.init)
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
