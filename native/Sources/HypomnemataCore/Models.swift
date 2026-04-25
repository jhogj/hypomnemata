import Foundation

public enum ItemKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case image
    case article
    case video
    case tweet
    case bookmark
    case note
    case pdf

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .image: "Imagens"
        case .article: "Artigos"
        case .video: "Vídeos"
        case .tweet: "Tweets"
        case .bookmark: "Bookmarks"
        case .note: "Notas"
        case .pdf: "PDFs"
        }
    }
}

public enum JobKind: String, Codable, CaseIterable, Sendable {
    case scrapeArticle
    case downloadMedia
    case generateThumbnail
    case runOCR
    case summarize
    case autotag
}

public enum JobStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case running
    case done
    case failed
}

public enum AssetRole: String, Codable, CaseIterable, Sendable {
    case original
    case thumbnail
    case heroImage
    case subtitle
    case derivedText
}

public struct Item: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var kind: ItemKind
    public var sourceURL: String?
    public var title: String?
    public var note: String?
    public var bodyText: String?
    public var summary: String?
    public var metadataJSON: String?
    public var capturedAt: String
    public var createdAt: String
    public var updatedAt: String
    public var tags: [String]

    public init(
        id: String = UUIDV7.generateString(),
        kind: ItemKind,
        sourceURL: String? = nil,
        title: String? = nil,
        note: String? = nil,
        bodyText: String? = nil,
        summary: String? = nil,
        metadataJSON: String? = nil,
        capturedAt: String = ClockTimestamp.nowISO8601(),
        createdAt: String = ClockTimestamp.nowISO8601(),
        updatedAt: String = ClockTimestamp.nowISO8601(),
        tags: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.sourceURL = sourceURL
        self.title = title
        self.note = note
        self.bodyText = bodyText
        self.summary = summary
        self.metadataJSON = metadataJSON
        self.capturedAt = capturedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
    }
}

public struct ItemSummary: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var title: String?
    public var kind: ItemKind
    public var capturedAt: String

    public init(id: String, title: String?, kind: ItemKind, capturedAt: String) {
        self.id = id
        self.title = title
        self.kind = kind
        self.capturedAt = capturedAt
    }
}

public struct AssetRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var itemID: String
    public var role: AssetRole
    public var mimeType: String?
    public var byteCount: Int64
    public var encryptedPath: String
    public var originalFilename: String?
    public var durationSeconds: Double?
    public var width: Int?
    public var height: Int?
    public var createdAt: String

    public init(
        id: String = UUIDV7.generateString(),
        itemID: String,
        role: AssetRole,
        mimeType: String? = nil,
        byteCount: Int64,
        encryptedPath: String,
        originalFilename: String? = nil,
        durationSeconds: Double? = nil,
        width: Int? = nil,
        height: Int? = nil,
        createdAt: String = ClockTimestamp.nowISO8601()
    ) {
        self.id = id
        self.itemID = itemID
        self.role = role
        self.mimeType = mimeType
        self.byteCount = byteCount
        self.encryptedPath = encryptedPath
        self.originalFilename = originalFilename
        self.durationSeconds = durationSeconds
        self.width = width
        self.height = height
        self.createdAt = createdAt
    }
}

public struct Folder: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var itemCount: Int
    public var createdAt: String

    public init(
        id: String = UUIDV7.generateString(),
        name: String,
        itemCount: Int = 0,
        createdAt: String = ClockTimestamp.nowISO8601()
    ) {
        self.id = id
        self.name = name
        self.itemCount = itemCount
        self.createdAt = createdAt
    }
}

public struct TagCount: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public var name: String
    public var count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct ChatMessage: Identifiable, Codable, Equatable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public var id: String
    public var itemID: String
    public var role: Role
    public var content: String
    public var createdAt: String

    public init(
        id: String = UUIDV7.generateString(),
        itemID: String,
        role: Role,
        content: String,
        createdAt: String = ClockTimestamp.nowISO8601()
    ) {
        self.id = id
        self.itemID = itemID
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

public struct Job: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var itemID: String?
    public var kind: JobKind
    public var status: JobStatus
    public var error: String?
    public var attempts: Int
    public var payloadJSON: String?
    public var createdAt: String
    public var updatedAt: String

    public init(
        id: String = UUIDV7.generateString(),
        itemID: String? = nil,
        kind: JobKind,
        status: JobStatus = .pending,
        error: String? = nil,
        attempts: Int = 0,
        payloadJSON: String? = nil,
        createdAt: String = ClockTimestamp.nowISO8601(),
        updatedAt: String = ClockTimestamp.nowISO8601()
    ) {
        self.id = id
        self.itemID = itemID
        self.kind = kind
        self.status = status
        self.error = error
        self.attempts = attempts
        self.payloadJSON = payloadJSON
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
