import Foundation
import HypomnemataCore

public enum JobAutomationOutcome: Sendable, Equatable {
    case skipped(reason: String)
    case summarized(summary: String)
    case taggedAutomatically(tags: [String])
}

public enum JobAutomationError: LocalizedError, Equatable, Sendable {
    case unsupportedJobKind(JobKind)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedJobKind(kind):
            "Job sem executor nesta versão: \(kind.rawValue)."
        }
    }
}

public struct JobAutomation: Sendable {
    public static let supportedKinds: Set<JobKind> = [.summarize, .autotag]

    private let service: ItemAIService

    public init(service: ItemAIService) {
        self.service = service
    }

    public static func canRun(_ kind: JobKind) -> Bool {
        supportedKinds.contains(kind)
    }

    public func run(_ kind: JobKind, on item: Item) async throws -> JobAutomationOutcome {
        let context = LLMItemContext(
            title: item.title,
            note: item.note,
            bodyText: item.bodyText
        )
        switch kind {
        case .summarize:
            do {
                let summary = try await service.summarize(context: context)
                return .summarized(summary: summary)
            } catch LLMClientError.emptyContent {
                return .skipped(reason: "Item sem conteúdo suficiente para resumo automático.")
            }
        case .autotag:
            guard item.tags.isEmpty else {
                return .skipped(reason: "Item já possui etiquetas; autotag automático foi preservado.")
            }
            do {
                let tags = try await service.autotags(context: context, existingTags: item.tags)
                return .taggedAutomatically(tags: tags)
            } catch LLMClientError.emptyContent {
                return .skipped(reason: "Item sem conteúdo suficiente para autotag.")
            }
        case .scrapeArticle, .downloadMedia, .generateThumbnail, .runOCR:
            throw JobAutomationError.unsupportedJobKind(kind)
        }
    }
}
