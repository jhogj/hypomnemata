import Foundation

public struct LLMConfiguration: Sendable, Equatable {
    public var baseURL: URL
    public var model: String
    public var contextCharacterLimit: Int

    public init(
        baseURL: URL = URL(string: "http://localhost:8080")!,
        model: String = "mlx-community/gemma-4-e2b-it-4bit",
        contextCharacterLimit: Int = 6_000
    ) {
        self.baseURL = baseURL
        self.model = model
        self.contextCharacterLimit = contextCharacterLimit
    }
}

public struct LLMMessage: Codable, Equatable, Sendable {
    public var role: String
    public var content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
}

public final class OpenAICompatibleClient: Sendable {
    private let configuration: LLMConfiguration
    private let session: URLSession

    public init(configuration: LLMConfiguration = LLMConfiguration(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func streamChat(messages: [LLMMessage], temperature: Double = 0.2) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let request = try makeRequest(messages: messages, temperature: temperature, stream: true)
                    let (bytes, response) = try await session.bytes(for: request)
                    try validate(response: response)

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else {
                            continue
                        }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" {
                            break
                        }
                        guard let data = payload.data(using: .utf8) else {
                            continue
                        }
                        if let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data),
                           let content = chunk.choices.first?.delta.content,
                           !content.isEmpty {
                            continuation.yield(content)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func summarize(title: String?, bodyText: String) -> AsyncThrowingStream<String, Error> {
        let context = String(bodyText.prefix(configuration.contextCharacterLimit))
        return streamChat(messages: [
            LLMMessage(role: "system", content: "Resuma o conteúdo em português, com precisão e sem inventar fatos."),
            LLMMessage(role: "user", content: "Título: \(title ?? "sem título")\n\nConteúdo:\n\(context)"),
        ])
    }

    private func makeRequest(messages: [LLMMessage], temperature: Double, stream: Bool) throws -> URLRequest {
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(ChatRequest(
            model: configuration.model,
            messages: messages,
            temperature: temperature,
            stream: stream
        ))
        return request
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }
        guard (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }
}

private struct ChatRequest: Encodable {
    var model: String
    var messages: [LLMMessage]
    var temperature: Double
    var stream: Bool
}

private struct StreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var content: String?
        }
        var delta: Delta
    }
    var choices: [Choice]
}
