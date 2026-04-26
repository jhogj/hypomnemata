import Foundation
import HypomnemataCore

public struct CaptureDraft: Sendable, Equatable {
    public var explicitKind: ItemKind?
    public var sourceURL: String?
    public var title: String?
    public var note: String?
    public var bodyText: String?
    public var fileURL: URL?
    public var tags: [String]

    public init(
        explicitKind: ItemKind? = nil,
        sourceURL: String? = nil,
        title: String? = nil,
        note: String? = nil,
        bodyText: String? = nil,
        fileURL: URL? = nil,
        tags: [String] = []
    ) {
        self.explicitKind = explicitKind
        self.sourceURL = sourceURL
        self.title = title
        self.note = note
        self.bodyText = bodyText
        self.fileURL = fileURL
        self.tags = tags
    }
}

public enum CaptureValidationError: LocalizedError, Equatable, Sendable {
    case missingInput
    case multipleInputs
    case invalidURL(String)
    case invalidFileURL(String)

    public var errorDescription: String? {
        switch self {
        case .missingInput:
            "Informe uma URL, escolha um arquivo ou escreva um texto."
        case .multipleInputs:
            "A captura deve usar apenas uma origem: URL, arquivo ou texto."
        case let .invalidURL(value):
            "URL inválida: \(value). Use uma URL http:// ou https:// com domínio."
        case let .invalidFileURL(value):
            "Arquivo inválido: \(value). Escolha um arquivo local."
        }
    }
}

public struct PlannedCapture: Sendable, Equatable {
    public var kind: ItemKind
    public var jobs: [JobKind]

    public init(kind: ItemKind, jobs: [JobKind]) {
        self.kind = kind
        self.jobs = jobs
    }
}

public enum CapturePlanner {
    public static func validate(_ draft: CaptureDraft) throws -> CaptureDraft {
        let sourceURL = draft.sourceURL.trimmedNonEmpty
        let title = draft.title.trimmedNonEmpty
        let note = draft.note.trimmedNonEmpty
        let bodyText = draft.bodyText.trimmedNonEmpty
        let tags = draft.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        let activeInputs = [
            sourceURL != nil,
            draft.fileURL != nil,
            bodyText != nil,
        ].filter { $0 }.count

        guard activeInputs > 0 else {
            throw CaptureValidationError.missingInput
        }
        guard activeInputs == 1 else {
            throw CaptureValidationError.multipleInputs
        }

        if let sourceURL {
            try validateWebURL(sourceURL)
        }

        if let fileURL = draft.fileURL, !fileURL.isFileURL {
            throw CaptureValidationError.invalidFileURL(fileURL.absoluteString)
        }

        return CaptureDraft(
            explicitKind: draft.explicitKind,
            sourceURL: sourceURL,
            title: title,
            note: note,
            bodyText: bodyText,
            fileURL: draft.fileURL,
            tags: Array(Set(tags)).sorted()
        )
    }

    public static func validateAndPlan(_ draft: CaptureDraft) throws -> (CaptureDraft, PlannedCapture) {
        let validated = try validate(draft)
        return (validated, plan(validated))
    }

    public static func plan(_ draft: CaptureDraft) -> PlannedCapture {
        let kind = KindInference.infer(
            urlString: draft.sourceURL,
            filename: draft.fileURL?.lastPathComponent,
            explicitKind: draft.explicitKind
        )
        var jobs: [JobKind] = []

        switch kind {
        case .article:
            if draft.sourceURL != nil {
                jobs.append(.scrapeArticle)
            }
        case .video:
            if draft.sourceURL != nil {
                jobs.append(.downloadMedia)
            } else if draft.fileURL != nil {
                jobs.append(.generateThumbnail)
            }
        case .audio:
            if draft.sourceURL != nil {
                jobs.append(.downloadMedia)
            }
        case .tweet:
            if draft.sourceURL != nil {
                jobs.append(.downloadMedia)
                jobs.append(.generateThumbnail)
            } else if draft.fileURL != nil {
                jobs.append(.generateThumbnail)
            }
        case .image:
            if draft.fileURL != nil {
                jobs.append(.runOCR)
            }
        case .pdf:
            if draft.fileURL != nil {
                jobs.append(contentsOf: [.generateThumbnail, .runOCR])
            }
        case .bookmark, .note:
            break
        }

        if kind == .article || kind == .video || kind == .audio || kind == .pdf {
            jobs.append(.summarize)
            jobs.append(.autotag)
        }

        return PlannedCapture(kind: kind, jobs: Array(NSOrderedSet(array: jobs).compactMap { $0 as? JobKind }))
    }

    private static func validateWebURL(_ value: String) throws {
        guard
            let components = URLComponents(string: value),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            let host = components.host,
            !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            components.url != nil
        else {
            throw CaptureValidationError.invalidURL(value)
        }
    }
}

private extension Optional where Wrapped == String {
    var trimmedNonEmpty: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}
