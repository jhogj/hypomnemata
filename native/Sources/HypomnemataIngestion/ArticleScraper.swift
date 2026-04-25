import Foundation
import HypomnemataCore

public struct ArticleHeroImage: Sendable, Equatable {
    public var data: Data
    public var mimeType: String?
    public var originalFilename: String?

    public init(data: Data, mimeType: String? = nil, originalFilename: String? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.originalFilename = originalFilename
    }
}

public struct ArticleScrapeResult: Sendable, Equatable {
    public var title: String?
    public var bodyText: String?
    public var description: String?
    public var author: String?
    public var sitename: String?
    public var publishedAt: String?
    public var heroImageURL: String?
    public var heroImage: ArticleHeroImage?

    public init(
        title: String? = nil,
        bodyText: String? = nil,
        description: String? = nil,
        author: String? = nil,
        sitename: String? = nil,
        publishedAt: String? = nil,
        heroImageURL: String? = nil,
        heroImage: ArticleHeroImage? = nil
    ) {
        self.title = title
        self.bodyText = bodyText
        self.description = description
        self.author = author
        self.sitename = sitename
        self.publishedAt = publishedAt
        self.heroImageURL = heroImageURL
        self.heroImage = heroImage
    }
}

public enum ArticleScrapeError: LocalizedError, Equatable, Sendable {
    case missingURL
    case binaryFailed(exitCode: Int32, message: String)
    case invalidOutput(String)
    case emptyContent
    case fetchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingURL:
            "Item sem URL — não há o que extrair."
        case let .binaryFailed(code, message):
            "trafilatura falhou (exit \(code)): \(message)"
        case let .invalidOutput(detail):
            "Saída do trafilatura inválida: \(detail)"
        case .emptyContent:
            "Não foi possível extrair conteúdo da página."
        case let .fetchFailed(detail):
            "Falha ao buscar a página: \(detail)"
        }
    }
}

public protocol ArticleScraper: Sendable {
    func scrape(url: String) async throws -> ArticleScrapeResult
}

public protocol JSPageRenderer: Sendable {
    func renderHTML(url: String) async throws -> String
}

public struct TrafilaturaArticleScraper: ArticleScraper {
    public static let renderFallbackThreshold = 200

    private let trafilaturaPath: String
    private let renderer: JSPageRenderer?
    private let imageDownloader: @Sendable (String) async throws -> (Data, String?)
    private let runProcess: @Sendable (String, [String], Data?) throws -> (Int32, Data, Data)

    public init(
        trafilaturaPath: String = "/opt/homebrew/bin/trafilatura",
        renderer: JSPageRenderer? = nil,
        imageDownloader: (@Sendable (String) async throws -> (Data, String?))? = nil,
        runProcess: (@Sendable (String, [String], Data?) throws -> (Int32, Data, Data))? = nil
    ) {
        self.trafilaturaPath = trafilaturaPath
        self.renderer = renderer
        self.imageDownloader = imageDownloader ?? Self.defaultImageDownloader
        self.runProcess = runProcess ?? Self.defaultRunProcess
    }

    public func scrape(url: String) async throws -> ArticleScrapeResult {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ArticleScrapeError.missingURL
        }

        var result = try runTrafilatura(arguments: ["--json", "--URL", trimmed])

        if needsFallback(for: result), let renderer {
            do {
                let html = try await renderer.renderHTML(url: trimmed)
                if !html.isEmpty {
                    let rendered = try runTrafilatura(
                        arguments: ["--json"],
                        stdin: Data(html.utf8)
                    )
                    if !needsFallback(for: rendered) {
                        result = rendered
                    }
                }
            } catch {
                // Fallback opcional: se o renderer falhar mantemos o resultado original.
            }
        }

        guard !needsFallback(for: result) else {
            throw ArticleScrapeError.emptyContent
        }

        if let heroURL = result.heroImageURL,
           result.heroImage == nil,
           let absoluteURL = absoluteHeroURL(heroURL, base: trimmed) {
            do {
                let (data, mime) = try await imageDownloader(absoluteURL)
                if !data.isEmpty {
                    let filename = URL(string: absoluteURL)?.lastPathComponent
                    result.heroImage = ArticleHeroImage(
                        data: data,
                        mimeType: mime,
                        originalFilename: filename?.isEmpty == false ? filename : nil
                    )
                }
            } catch {
                // Hero opcional. Texto/metadados continuam válidos sem ela.
            }
        }

        return result
    }

    private func runTrafilatura(arguments: [String], stdin: Data? = nil) throws -> ArticleScrapeResult {
        let (exitCode, stdoutData, stderrData) = try runProcess(trafilaturaPath, arguments, stdin)
        guard exitCode == 0 else {
            let message = String(data: stderrData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ArticleScrapeError.binaryFailed(exitCode: exitCode, message: message)
        }
        return try Self.parse(stdoutData)
    }

    private func needsFallback(for result: ArticleScrapeResult) -> Bool {
        let body = result.bodyText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return body.count < Self.renderFallbackThreshold
    }

    private func absoluteHeroURL(_ raw: String, base: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        if URL(string: trimmed)?.scheme != nil {
            return trimmed
        }
        if let baseURL = URL(string: base), let resolved = URL(string: trimmed, relativeTo: baseURL)?.absoluteURL {
            return resolved.absoluteString
        }
        return nil
    }

    static func parse(_ data: Data) throws -> ArticleScrapeResult {
        guard !data.isEmpty else {
            throw ArticleScrapeError.invalidOutput("saída vazia")
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw ArticleScrapeError.invalidOutput(error.localizedDescription)
        }
        guard let dict = object as? [String: Any] else {
            throw ArticleScrapeError.invalidOutput("JSON sem objeto raiz")
        }

        let title = (dict["title"] as? String).flatMap(Self.trimmedNonEmpty)
        let body = Self.trimmedNonEmpty(dict["text"] as? String ?? dict["raw_text"] as? String)
        let description = Self.trimmedNonEmpty(dict["description"] as? String ?? dict["excerpt"] as? String)
        let author = Self.trimmedNonEmpty(dict["author"] as? String)
        let sitename = Self.trimmedNonEmpty(dict["sitename"] as? String ?? dict["site_name"] as? String)
        let publishedAt = Self.trimmedNonEmpty(dict["date"] as? String ?? dict["published_at"] as? String)
        let heroURL = Self.trimmedNonEmpty(
            dict["image"] as? String
                ?? (dict["images"] as? [String])?.first
                ?? dict["og_image"] as? String
        )

        return ArticleScrapeResult(
            title: title,
            bodyText: body,
            description: description,
            author: author,
            sitename: sitename,
            publishedAt: publishedAt,
            heroImageURL: heroURL
        )
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    @Sendable
    private static func defaultImageDownloader(url: String) async throws -> (Data, String?) {
        guard let target = URL(string: url) else {
            throw ArticleScrapeError.fetchFailed("URL inválida: \(url)")
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: target)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw ArticleScrapeError.fetchFailed("HTTP \(http.statusCode)")
            }
            let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
            return (data, mime)
        } catch let error as ArticleScrapeError {
            throw error
        } catch {
            throw ArticleScrapeError.fetchFailed(error.localizedDescription)
        }
    }

    @Sendable
    private static func defaultRunProcess(executable: String, arguments: [String], stdin: Data?) throws -> (Int32, Data, Data) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        if stdin != nil {
            process.standardInput = Pipe()
        }
        try process.run()
        if let stdin, let inputPipe = process.standardInput as? Pipe {
            try inputPipe.fileHandleForWriting.write(contentsOf: stdin)
            try inputPipe.fileHandleForWriting.close()
        }
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, stdoutData, stderrData)
    }
}
