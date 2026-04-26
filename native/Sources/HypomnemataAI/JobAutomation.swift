import Foundation
import HypomnemataCore
import HypomnemataIngestion

public enum JobAutomationOutcome: Sendable, Equatable {
    case skipped(reason: String)
    case summarized(summary: String)
    case taggedAutomatically(tags: [String])
    case articleScraped(ArticleScrapeResult)
    case mediaDownloaded(MediaDownloadResult)
    case thumbnailFetched(RemoteThumbnailResult)
}

public enum JobAutomationError: LocalizedError, Equatable, Sendable {
    case unsupportedJobKind(JobKind)
    case missingExecutor(JobKind)
    case missingSourceURL

    public var errorDescription: String? {
        switch self {
        case let .unsupportedJobKind(kind):
            "Job sem executor nesta versão: \(kind.rawValue)."
        case let .missingExecutor(kind):
            "Executor de \(kind.rawValue) não está configurado."
        case .missingSourceURL:
            "Item sem URL não pode rodar este job."
        }
    }
}

public struct JobAutomation: Sendable {
    public static let supportedKinds: Set<JobKind> = [.summarize, .autotag, .scrapeArticle, .downloadMedia, .generateThumbnail]

    private let service: ItemAIService?
    private let articleScraper: (any ArticleScraper)?
    private let mediaDownloader: (any MediaDownloader)?
    private let remoteThumbnailFetcher: (any RemoteThumbnailFetcher)?

    public init(
        service: ItemAIService? = nil,
        articleScraper: (any ArticleScraper)? = nil,
        mediaDownloader: (any MediaDownloader)? = nil,
        remoteThumbnailFetcher: (any RemoteThumbnailFetcher)? = nil
    ) {
        self.service = service
        self.articleScraper = articleScraper
        self.mediaDownloader = mediaDownloader
        self.remoteThumbnailFetcher = remoteThumbnailFetcher
    }

    public static func canRun(_ kind: JobKind) -> Bool {
        supportedKinds.contains(kind)
    }

    public func run(_ kind: JobKind, on item: Item) async throws -> JobAutomationOutcome {
        switch kind {
        case .summarize:
            guard let service else {
                throw JobAutomationError.missingExecutor(kind)
            }
            let context = LLMItemContext(title: item.title, note: item.note, bodyText: item.bodyText)
            do {
                let summary = try await service.summarize(context: context)
                return .summarized(summary: summary)
            } catch LLMClientError.emptyContent {
                return .skipped(reason: "Item sem conteúdo suficiente para resumo automático.")
            }
        case .autotag:
            guard let service else {
                throw JobAutomationError.missingExecutor(kind)
            }
            guard item.tags.isEmpty else {
                return .skipped(reason: "Item já possui etiquetas; autotag automático foi preservado.")
            }
            let context = LLMItemContext(title: item.title, note: item.note, bodyText: item.bodyText)
            do {
                let tags = try await service.autotags(context: context, existingTags: item.tags)
                return .taggedAutomatically(tags: tags)
            } catch LLMClientError.emptyContent {
                return .skipped(reason: "Item sem conteúdo suficiente para autotag.")
            }
        case .scrapeArticle:
            guard let articleScraper else {
                throw JobAutomationError.missingExecutor(kind)
            }
            let trimmedURL = item.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedURL.isEmpty else {
                throw JobAutomationError.missingSourceURL
            }
            let result = try await articleScraper.scrape(url: trimmedURL)
            return .articleScraped(result)
        case .downloadMedia:
            guard let mediaDownloader else {
                throw JobAutomationError.missingExecutor(kind)
            }
            let trimmedURL = item.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedURL.isEmpty else {
                throw JobAutomationError.missingSourceURL
            }
            do {
                let mode: MediaDownloadMode = item.kind == .audio ? .audio : .video
                let result = try await mediaDownloader.download(url: trimmedURL, mode: mode)
                return .mediaDownloaded(result)
            } catch MediaDownloadError.outputNotFound where item.kind == .tweet {
                return .skipped(reason: "Tweet sem vídeo local; miniatura remota será usada quando disponível.")
            }
        case .generateThumbnail:
            guard let remoteThumbnailFetcher else {
                throw JobAutomationError.missingExecutor(kind)
            }
            let trimmedURL = item.sourceURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmedURL.isEmpty else {
                throw JobAutomationError.missingSourceURL
            }
            let result = try await remoteThumbnailFetcher.fetchThumbnail(url: trimmedURL)
            return .thumbnailFetched(result)
        case .runOCR:
            throw JobAutomationError.unsupportedJobKind(kind)
        }
    }
}
