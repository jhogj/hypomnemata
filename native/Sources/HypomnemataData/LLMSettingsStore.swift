import Foundation
import GRDB

public struct LLMSettingsRecord: Equatable, Sendable {
    public var url: String?
    public var model: String?
    public var contextLimit: String?

    public init(url: String? = nil, model: String? = nil, contextLimit: String? = nil) {
        self.url = url
        self.model = model
        self.contextLimit = contextLimit
    }

    public var isEmpty: Bool {
        url == nil && model == nil && contextLimit == nil
    }
}

public final class LLMSettingsStore: @unchecked Sendable {
    static let urlKey = "llm_url_v1"
    static let modelKey = "llm_model_v1"
    static let contextLimitKey = "llm_context_limit_v1"

    private let database: NativeDatabase

    public init(database: NativeDatabase) {
        self.database = database
    }

    public func read() throws -> LLMSettingsRecord {
        try database.writer.read { db in
            LLMSettingsRecord(
                url: try Self.value(for: Self.urlKey, in: db),
                model: try Self.value(for: Self.modelKey, in: db),
                contextLimit: try Self.value(for: Self.contextLimitKey, in: db)
            )
        }
    }

    public func write(_ record: LLMSettingsRecord) throws {
        try database.writer.write { db in
            try Self.upsert(key: Self.urlKey, value: record.url, in: db)
            try Self.upsert(key: Self.modelKey, value: record.model, in: db)
            try Self.upsert(key: Self.contextLimitKey, value: record.contextLimit, in: db)
        }
    }

    public func clear() throws {
        try write(LLMSettingsRecord())
    }

    private static func value(for key: String, in db: Database) throws -> String? {
        let raw = try String.fetchOne(
            db,
            sql: "SELECT value FROM settings WHERE key = ?",
            arguments: [key]
        )
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private static func upsert(key: String, value: String?, in db: Database) throws {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            try db.execute(
                sql: """
                    INSERT INTO settings(key, value) VALUES (?, ?)
                    ON CONFLICT(key) DO UPDATE SET value = excluded.value
                    """,
                arguments: [key, trimmed]
            )
        } else {
            try db.execute(
                sql: "DELETE FROM settings WHERE key = ?",
                arguments: [key]
            )
        }
    }
}
