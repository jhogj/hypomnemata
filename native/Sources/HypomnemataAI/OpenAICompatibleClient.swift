import Foundation

public enum LLMConfigurationError: LocalizedError, Equatable, Sendable {
    case invalidBaseURL(String)
    case emptyModel
    case invalidContextLimit(String)

    public var errorDescription: String? {
        switch self {
        case let .invalidBaseURL(value):
            "URL do provider LLM inválida: \(value)."
        case .emptyModel:
            "Modelo LLM não pode ficar vazio."
        case let .invalidContextLimit(value):
            "Limite de contexto LLM inválido: \(value)."
        }
    }
}

public enum LLMClientError: LocalizedError, Equatable, Sendable {
    case emptyContent
    case invalidResponse
    case providerStatus(Int)
    case providerUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case .emptyContent:
            "Não há conteúdo suficiente para chamar a IA."
        case .invalidResponse:
            "Provider LLM retornou uma resposta inválida."
        case let .providerStatus(statusCode):
            "Provider LLM retornou HTTP \(statusCode)."
        case let .providerUnavailable(message):
            "Provider LLM indisponível: \(message)"
        }
    }
}

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

    public init(baseURLString: String, model: String, contextCharacterLimit: Int = 6_000) throws {
        let trimmedURL = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: trimmedURL),
            let scheme = url.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            url.host != nil
        else {
            throw LLMConfigurationError.invalidBaseURL(baseURLString)
        }
        let trimmedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            throw LLMConfigurationError.emptyModel
        }
        guard contextCharacterLimit > 0 else {
            throw LLMConfigurationError.invalidContextLimit(String(contextCharacterLimit))
        }
        self.baseURL = url
        self.model = trimmedModel
        self.contextCharacterLimit = contextCharacterLimit
    }

    public static func fromEnvironment(_ environment: [String: String] = ProcessInfo.processInfo.environment) throws -> LLMConfiguration {
        try resolve(overrides: LLMOverrides(), environment: environment)
    }

    public static func resolve(
        overrides: LLMOverrides,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> LLMConfiguration {
        let baseURL = overrides.url
            ?? environment["HYPO_LLM_URL"]
            ?? "http://localhost:8080"
        let model = overrides.model
            ?? environment["HYPO_LLM_MODEL"]
            ?? "mlx-community/gemma-4-e2b-it-4bit"
        let contextLimitValue = overrides.contextLimit
            ?? environment["HYPO_LLM_CONTEXT_LIMIT"]
            ?? "6000"
        guard let contextLimit = Int(contextLimitValue), contextLimit > 0 else {
            throw LLMConfigurationError.invalidContextLimit(contextLimitValue)
        }
        return try LLMConfiguration(
            baseURLString: baseURL,
            model: model,
            contextCharacterLimit: contextLimit
        )
    }
}

public struct LLMOverrides: Sendable, Equatable {
    public var url: String?
    public var model: String?
    public var contextLimit: String?

    public init(url: String? = nil, model: String? = nil, contextLimit: String? = nil) {
        self.url = url.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        self.model = model.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
        self.contextLimit = contextLimit.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
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

public protocol LLMClient: Sendable {
    func complete(messages: [LLMMessage], temperature: Double) async throws -> String
    func streamChat(messages: [LLMMessage], temperature: Double) -> AsyncThrowingStream<String, Error>
}

public extension LLMClient {
    func complete(messages: [LLMMessage]) async throws -> String {
        try await complete(messages: messages, temperature: 0.2)
    }

    func streamChat(messages: [LLMMessage]) -> AsyncThrowingStream<String, Error> {
        streamChat(messages: messages, temperature: 0.2)
    }
}

public struct LLMItemContext: Equatable, Sendable {
    public var title: String?
    public var note: String?
    public var bodyText: String?

    public init(title: String? = nil, note: String? = nil, bodyText: String? = nil) {
        self.title = title
        self.note = note
        self.bodyText = bodyText
    }

    public func promptContext(limit: Int) throws -> String {
        let candidates = [bodyText, note, title]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let content = candidates.first else {
            throw LLMClientError.emptyContent
        }
        return String(content.prefix(limit))
    }
}

public struct LLMRecoverableErrorMapper: Sendable {
    public init() {}

    public func jobErrorMessage(for error: Error) -> String {
        if let localized = (error as? LocalizedError)?.errorDescription {
            return "Falha recuperável de IA: \(localized)"
        }
        return "Falha recuperável de IA: \(error.localizedDescription)"
    }
}

public final class OpenAICompatibleClient: LLMClient, Sendable {
    private let configuration: LLMConfiguration
    private let session: URLSession

    public init(configuration: LLMConfiguration = LLMConfiguration(), session: URLSession = .shared) {
        self.configuration = configuration
        self.session = session
    }

    public func complete(messages: [LLMMessage], temperature: Double = 0.2) async throws -> String {
        let request = try makeRequest(messages: messages, temperature: temperature, stream: false)
        do {
            let (data, response) = try await session.data(for: request)
            try validate(response: response)
            let completion = try JSONDecoder().decode(ChatCompletion.self, from: data)
            guard let content = completion.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
                throw LLMClientError.invalidResponse
            }
            return content
        } catch let error as LLMClientError {
            throw error
        } catch {
            throw LLMClientError.providerUnavailable(error.localizedDescription)
        }
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
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("v1/chat/completions"))
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
            throw LLMClientError.providerStatus(http.statusCode)
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

private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String
        }
        var message: Message
    }
    var choices: [Choice]
}
