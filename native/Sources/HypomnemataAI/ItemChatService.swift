import Foundation
import HypomnemataCore

public struct ItemChatService: Sendable {
    public static let minimumBodyTextLength = 300

    public struct Conversation: Sendable, Equatable {
        public var item: Item
        public var history: [ChatMessage]
        public var newUserMessage: String

        public init(item: Item, history: [ChatMessage], newUserMessage: String) {
            self.item = item
            self.history = history
            self.newUserMessage = newUserMessage
        }
    }

    private let client: any LLMClient
    private let configuration: LLMConfiguration

    public init(client: any LLMClient, configuration: LLMConfiguration = LLMConfiguration()) {
        self.client = client
        self.configuration = configuration
    }

    public static func isAvailable(for item: Item) -> Bool {
        (item.bodyText?.count ?? 0) >= minimumBodyTextLength
    }

    public func streamReply(_ conversation: Conversation) throws -> AsyncThrowingStream<String, Error> {
        let trimmedQuestion = conversation.newUserMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else {
            throw LLMClientError.emptyContent
        }
        guard Self.isAvailable(for: conversation.item) else {
            throw LLMClientError.emptyContent
        }
        let systemPrompt = makeSystemPrompt(for: conversation.item)
        var messages: [LLMMessage] = [LLMMessage(role: "system", content: systemPrompt)]
        for entry in conversation.history {
            messages.append(LLMMessage(role: entry.role.rawValue, content: entry.content))
        }
        messages.append(LLMMessage(role: "user", content: trimmedQuestion))
        return client.streamChat(messages: messages, temperature: 0.2)
    }

    private func makeSystemPrompt(for item: Item) -> String {
        let title = item.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "sem título"
        let body = item.bodyText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedBody = String(body.prefix(configuration.contextCharacterLimit))
        return """
        Responda em português usando apenas o conteúdo abaixo. Se a resposta não estiver no documento, diga claramente que não sabe e não invente fatos.

        Título: \(title)

        Conteúdo:
        \(trimmedBody)
        """
    }
}
