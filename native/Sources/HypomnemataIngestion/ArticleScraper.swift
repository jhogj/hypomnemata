import Foundation
import HypomnemataCore
import os

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
    private static let logger = Logger(subsystem: "hypomnemata", category: "article-scraper")

    private let trafilaturaPath: String
    private let renderer: JSPageRenderer?
    private let imageDownloader: @Sendable (String) async throws -> (Data, String?)
    private let runProcess: @Sendable (String, [String], Data?) throws -> SubprocessResult

    public init(
        trafilaturaPath: String = "trafilatura",
        renderer: JSPageRenderer? = nil,
        imageDownloader: (@Sendable (String) async throws -> (Data, String?))? = nil,
        runProcess: (@Sendable (String, [String], Data?) throws -> SubprocessResult)? = nil
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
        var renderedFallbackHTML: String?

        if needsFallback(for: result), let renderer {
            do {
                let html = try await renderer.renderHTML(url: trimmed)
                if !html.isEmpty {
                    renderedFallbackHTML = html
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

        if result.heroImageURL == nil {
            if let renderedFallbackHTML {
                result.heroImageURL = Self.extractHeroImageURL(fromHTML: renderedFallbackHTML)
            } else if let html = try? await Self.fetchRawHTML(url: trimmed) {
                result.heroImageURL = Self.extractHeroImageURL(fromHTML: html)
            }
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
                Self.logger.warning("Falha ao baixar hero image: \(String(describing: error), privacy: .public)")
            }
        }

        return result
    }

    private func runTrafilatura(arguments: [String], stdin: Data? = nil) throws -> ArticleScrapeResult {
        let result = try runProcess(trafilaturaPath, arguments, stdin)
        guard result.exitCode == 0 else {
            let message = String(data: result.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ArticleScrapeError.binaryFailed(exitCode: result.exitCode, message: message)
        }
        return try Self.parse(result.stdout)
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

    private static func extractHeroImageURL(fromHTML html: String) -> String? {
        let metaTags = tags(named: "meta", in: html)
        let linkTags = tags(named: "link", in: html)
        let candidates: [(String, String, String)] = [
            ("property", "og:image", "content"),
            ("name", "twitter:image", "content"),
            ("name", "twitter:image:src", "content"),
        ]
        for (key, expectedValue, outputKey) in candidates {
            for tag in metaTags {
                let attributes = attributes(in: tag)
                if attributes[key]?.caseInsensitiveCompare(expectedValue) == .orderedSame,
                   let value = trimmedNonEmpty(attributes[outputKey]) {
                    return value
                }
            }
        }
        for tag in linkTags {
            let attributes = attributes(in: tag)
            if attributes["rel"]?.caseInsensitiveCompare("image_src") == .orderedSame,
               let value = trimmedNonEmpty(attributes["href"]) {
                return value
            }
        }
        return nil
    }

    private static func tags(named name: String, in html: String) -> [String] {
        let pattern = "<\(name)\\b[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, options: [], range: range).compactMap { match in
            Range(match.range, in: html).map { String(html[$0]) }
        }
    }

    private static func attributes(in tag: String) -> [String: String] {
        let pattern = #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(['"])(.*?)\2"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return [:]
        }
        let range = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        var values: [String: String] = [:]
        for match in regex.matches(in: tag, options: [], range: range) {
            guard
                match.numberOfRanges == 4,
                let keyRange = Range(match.range(at: 1), in: tag),
                let valueRange = Range(match.range(at: 3), in: tag)
            else {
                continue
            }
            values[String(tag[keyRange]).lowercased()] = String(tag[valueRange])
        }
        return values
    }

    private static func fetchRawHTML(url: String) async throws -> String? {
        guard let target = URL(string: url) else {
            throw ArticleScrapeError.fetchFailed("URL inválida: \(url)")
        }
        let (data, response) = try await URLSession.shared.data(from: target)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ArticleScrapeError.fetchFailed("HTTP \(http.statusCode)")
        }
        return String(data: data, encoding: .utf8)
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
            return (data, resolvedImageMimeType(responseMimeType: mime, data: data))
        } catch let error as ArticleScrapeError {
            throw error
        } catch {
            throw ArticleScrapeError.fetchFailed(error.localizedDescription)
        }
    }

    private static func resolvedImageMimeType(responseMimeType: String?, data: Data) -> String? {
        let normalized = responseMimeType?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized?.hasPrefix("image/") == true {
            return normalized
        }
        return sniffImageMimeType(data)
    }

    private static func sniffImageMimeType(_ data: Data) -> String? {
        let bytes = [UInt8](data.prefix(12))
        if bytes.count >= 3, bytes[0] == 0xFF, bytes[1] == 0xD8, bytes[2] == 0xFF {
            return "image/jpeg"
        }
        if bytes.count >= 8,
           bytes[0] == 0x89, bytes[1] == 0x50, bytes[2] == 0x4E, bytes[3] == 0x47,
           bytes[4] == 0x0D, bytes[5] == 0x0A, bytes[6] == 0x1A, bytes[7] == 0x0A {
            return "image/png"
        }
        if bytes.count >= 4,
           bytes[0] == 0x47, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x38 {
            return "image/gif"
        }
        if bytes.count >= 12,
           bytes[0] == 0x52, bytes[1] == 0x49, bytes[2] == 0x46, bytes[3] == 0x46,
           bytes[8] == 0x57, bytes[9] == 0x45, bytes[10] == 0x42, bytes[11] == 0x50 {
            return "image/webp"
        }
        return nil
    }

    @Sendable
    private static func defaultRunProcess(executable: String, arguments: [String], stdin: Data?) throws -> SubprocessResult {
        try SubprocessRunner().run(
            executable: executable,
            arguments: arguments,
            standardInput: stdin
        )
    }
}
