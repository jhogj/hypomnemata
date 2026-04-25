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

public struct PlannedCapture: Sendable, Equatable {
    public var kind: ItemKind
    public var jobs: [JobKind]

    public init(kind: ItemKind, jobs: [JobKind]) {
        self.kind = kind
        self.jobs = jobs
    }
}

public enum CapturePlanner {
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
        case .video, .tweet:
            if draft.sourceURL != nil {
                jobs.append(.downloadMedia)
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

        if kind == .article || kind == .video || kind == .pdf {
            jobs.append(.summarize)
            jobs.append(.autotag)
        }

        return PlannedCapture(kind: kind, jobs: Array(NSOrderedSet(array: jobs).compactMap { $0 as? JobKind }))
    }
}
