import Foundation
import GRDB
import HypomnemataCore

public struct ItemListFilter: Sendable, Equatable {
    public var kind: ItemKind?
    public var tag: String?
    public var folderID: String?
    public var limit: Int
    public var offset: Int

    public init(kind: ItemKind? = nil, tag: String? = nil, folderID: String? = nil, limit: Int = 200, offset: Int = 0) {
        self.kind = kind
        self.tag = tag
        self.folderID = folderID
        self.limit = limit
        self.offset = offset
    }
}

public struct ItemPatch: Sendable, Equatable {
    public var title: String?
    public var note: String?
    public var bodyText: String?
    public var summary: String?
    public var tags: [String]?

    public init(title: String? = nil, note: String? = nil, bodyText: String? = nil, summary: String? = nil, tags: [String]? = nil) {
        self.title = title
        self.note = note
        self.bodyText = bodyText
        self.summary = summary
        self.tags = tags
    }
}

public protocol ItemRepository: Sendable {
    func createItem(
        kind: ItemKind,
        sourceURL: String?,
        title: String?,
        note: String?,
        bodyText: String?,
        summary: String?,
        metadataJSON: String?,
        tags: [String]
    ) throws -> Item

    func listItems(filter: ItemListFilter) throws -> [Item]
    func search(_ query: String, limit: Int) throws -> [Item]
    func search(_ query: String, filter: ItemListFilter) throws -> [Item]
    func item(id: String) throws -> Item
    func patchItem(id: String, patch: ItemPatch) throws -> Item
    func deleteItems(ids: [String]) throws
    func insertAsset(_ asset: AssetRecord) throws
    func assets(forItemID itemID: String) throws -> [AssetRecord]
    func totalItemCount() throws -> Int
    func itemCountsByKind() throws -> [ItemKind: Int]
    func tagCounts() throws -> [TagCount]
    func listFolders() throws -> [Folder]
    func createFolder(name: String) throws -> Folder
    func addItems(_ itemIDs: [String], toFolder folderID: String) throws
}

public final class SQLiteItemRepository: ItemRepository, @unchecked Sendable {
    private let database: NativeDatabase

    public init(database: NativeDatabase) {
        self.database = database
    }

    public func createItem(
        kind: ItemKind,
        sourceURL: String? = nil,
        title: String? = nil,
        note: String? = nil,
        bodyText: String? = nil,
        summary: String? = nil,
        metadataJSON: String? = nil,
        tags: [String] = []
    ) throws -> Item {
        let now = ClockTimestamp.nowISO8601()
        var item = Item(
            kind: kind,
            sourceURL: sourceURL,
            title: title,
            note: note,
            bodyText: bodyText,
            summary: summary,
            metadataJSON: metadataJSON,
            capturedAt: now,
            createdAt: now,
            updatedAt: now,
            tags: normalizeTags(tags)
        )

        try database.writer.write { db in
            try insert(item, db: db)
            try setTags(item.tags, for: item.id, db: db)
            try syncLinks(for: item.id, note: item.note, bodyText: item.bodyText, db: db)
        }
        item.tags = normalizeTags(tags)
        return item
    }

    public func listItems(filter: ItemListFilter = ItemListFilter()) throws -> [Item] {
        try database.writer.read { db in
            var sql = "SELECT DISTINCT items.* FROM items"
            var joins: [String] = []
            var clauses: [String] = []
            var arguments = StatementArguments()

            appendFilterClauses(filter, joins: &joins, clauses: &clauses, arguments: &arguments)

            if !joins.isEmpty {
                sql += " " + joins.joined(separator: " ")
            }
            if !clauses.isEmpty {
                sql += " WHERE " + clauses.joined(separator: " AND ")
            }
            sql += " ORDER BY items.captured_at DESC LIMIT ? OFFSET ?"
            _ = arguments.append(contentsOf: [filter.limit, filter.offset])

            let items = try Row.fetchAll(db, sql: sql, arguments: arguments).map(Self.item(from:))
            return try hydrateTags(for: items, db: db)
        }
    }

    public func search(_ query: String, limit: Int = 200) throws -> [Item] {
        try search(query, filter: ItemListFilter(limit: limit))
    }

    public func search(_ query: String, filter: ItemListFilter) throws -> [Item] {
        let pattern = ftsPattern(query)
        guard !pattern.isEmpty else {
            return []
        }
        return try database.writer.read { db in
            var sql = """
                SELECT DISTINCT items.*
                FROM items_fts
                JOIN items ON items.rowid = items_fts.rowid
                """
            var joins: [String] = []
            var clauses = ["items_fts MATCH ?"]
            var arguments: StatementArguments = [pattern]

            appendFilterClauses(filter, joins: &joins, clauses: &clauses, arguments: &arguments)

            if !joins.isEmpty {
                sql += "\n" + joins.joined(separator: "\n")
            }
            sql += "\nWHERE " + clauses.joined(separator: " AND ")
            sql += "\nORDER BY rank LIMIT ? OFFSET ?"
            _ = arguments.append(contentsOf: [filter.limit, filter.offset])

            let rows = try Row.fetchAll(
                db,
                sql: sql,
                arguments: arguments
            )
            return try hydrateTags(for: rows.map(Self.item(from:)), db: db)
        }
    }

    public func item(id: String) throws -> Item {
        try database.writer.read { db in
            guard let row = try Row.fetchOne(db, sql: "SELECT * FROM items WHERE id = ?", arguments: [id]) else {
                throw DataError.itemNotFound(id)
            }
            return try hydrateTags(for: [Self.item(from: row)], db: db)[0]
        }
    }

    public func patchItem(id: String, patch: ItemPatch) throws -> Item {
        try database.writer.write { db in
            guard var existing = try Row.fetchOne(db, sql: "SELECT * FROM items WHERE id = ?", arguments: [id]).map(Self.item(from:)) else {
                throw DataError.itemNotFound(id)
            }

            if patch.title != nil {
                existing.title = patch.title ?? nil
            }
            if patch.note != nil {
                existing.note = patch.note ?? nil
            }
            if patch.bodyText != nil {
                existing.bodyText = patch.bodyText ?? nil
            }
            if patch.summary != nil {
                existing.summary = patch.summary ?? nil
            }
            existing.updatedAt = ClockTimestamp.nowISO8601()

            try db.execute(
                sql: """
                    UPDATE items
                    SET title = ?, note = ?, body_text = ?, summary = ?, updated_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    existing.title,
                    existing.note,
                    existing.bodyText,
                    existing.summary,
                    existing.updatedAt,
                    id,
                ]
            )

            if let tags = patch.tags {
                try setTags(normalizeTags(tags), for: id, db: db)
            }
            try syncLinks(for: id, note: existing.note, bodyText: existing.bodyText, db: db)
        }
        return try item(id: id)
    }

    public func deleteItems(ids: [String]) throws {
        guard !ids.isEmpty else {
            return
        }
        try database.writer.write { db in
            for id in ids {
                try db.execute(sql: "DELETE FROM items WHERE id = ?", arguments: [id])
            }
        }
    }

    public func insertAsset(_ asset: AssetRecord) throws {
        try database.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO assets(
                        id, item_id, role, mime_type, byte_count, encrypted_path, original_filename,
                        duration_seconds, width, height, created_at
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    asset.id,
                    asset.itemID,
                    asset.role.rawValue,
                    asset.mimeType,
                    asset.byteCount,
                    asset.encryptedPath,
                    asset.originalFilename,
                    asset.durationSeconds,
                    asset.width,
                    asset.height,
                    asset.createdAt,
                ]
            )
        }
    }

    public func assets(forItemID itemID: String) throws -> [AssetRecord] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT *
                    FROM assets
                    WHERE item_id = ?
                    ORDER BY created_at, id
                    """,
                arguments: [itemID]
            ).map(Self.asset(from:))
        }
    }

    public func totalItemCount() throws -> Int {
        try database.writer.read { db in
            try Int.fetchOne(db, sql: "SELECT count(*) FROM items") ?? 0
        }
    }

    public func itemCountsByKind() throws -> [ItemKind: Int] {
        try database.writer.read { db in
            var counts = Dictionary(uniqueKeysWithValues: ItemKind.allCases.map { ($0, 0) })
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT kind, count(*) AS count FROM items GROUP BY kind"
            )
            for row in rows {
                if let kind = ItemKind(rawValue: row["kind"]) {
                    counts[kind] = row["count"]
                }
            }
            return counts
        }
    }

    public func tagCounts() throws -> [TagCount] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT tags.name AS name, count(item_tags.item_id) AS count
                    FROM tags
                    JOIN item_tags ON item_tags.tag_id = tags.id
                    GROUP BY tags.id
                    ORDER BY tags.name
                    """
            ).map { row in
                TagCount(name: row["name"], count: row["count"])
            }
        }
    }

    public func listFolders() throws -> [Folder] {
        try database.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT folders.id, folders.name, folders.created_at, count(folder_items.item_id) AS item_count
                    FROM folders
                    LEFT JOIN folder_items ON folder_items.folder_id = folders.id
                    GROUP BY folders.id
                    ORDER BY lower(folders.name)
                    """
            ).map { row in
                Folder(
                    id: row["id"],
                    name: row["name"],
                    itemCount: row["item_count"],
                    createdAt: row["created_at"]
                )
            }
        }
    }

    public func createFolder(name: String) throws -> Folder {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DataError.emptyFolderName
        }

        let folder = Folder(name: trimmed)
        try database.writer.write { db in
            try db.execute(
                sql: "INSERT INTO folders(id, name, created_at) VALUES (?, ?, ?)",
                arguments: [folder.id, folder.name, folder.createdAt]
            )
        }
        return folder
    }

    public func addItems(_ itemIDs: [String], toFolder folderID: String) throws {
        guard !itemIDs.isEmpty else {
            return
        }
        let now = ClockTimestamp.nowISO8601()
        try database.writer.write { db in
            for itemID in itemIDs {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO folder_items(folder_id, item_id, added_at) VALUES (?, ?, ?)",
                    arguments: [folderID, itemID, now]
                )
            }
        }
    }

    private func insert(_ item: Item, db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO items(
                    id, kind, source_url, title, note, body_text, summary, meta_json,
                    captured_at, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [
                item.id,
                item.kind.rawValue,
                item.sourceURL,
                item.title,
                item.note,
                item.bodyText,
                item.summary,
                item.metadataJSON,
                item.capturedAt,
                item.createdAt,
                item.updatedAt,
            ]
        )
    }

    private func appendFilterClauses(
        _ filter: ItemListFilter,
        joins: inout [String],
        clauses: inout [String],
        arguments: inout StatementArguments
    ) {
        if let tag = filter.tag?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !tag.isEmpty {
            joins.append("JOIN item_tags ON item_tags.item_id = items.id JOIN tags ON tags.id = item_tags.tag_id")
            clauses.append("tags.name = ?")
            _ = arguments.append(contentsOf: [tag])
        }
        if let folderID = filter.folderID {
            joins.append("JOIN folder_items ON folder_items.item_id = items.id")
            clauses.append("folder_items.folder_id = ?")
            _ = arguments.append(contentsOf: [folderID])
        }
        if let kind = filter.kind {
            clauses.append("items.kind = ?")
            _ = arguments.append(contentsOf: [kind.rawValue])
        }
    }

    private func setTags(_ tags: [String], for itemID: String, db: Database) throws {
        try db.execute(sql: "DELETE FROM item_tags WHERE item_id = ?", arguments: [itemID])
        for tag in normalizeTags(tags) {
            try db.execute(sql: "INSERT OR IGNORE INTO tags(name) VALUES (?)", arguments: [tag])
            let tagID = try Int.fetchOne(db, sql: "SELECT id FROM tags WHERE name = ?", arguments: [tag])
            if let tagID {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO item_tags(item_id, tag_id) VALUES (?, ?)",
                    arguments: [itemID, tagID]
                )
            }
        }
    }

    private func syncLinks(for itemID: String, note: String?, bodyText: String?, db: Database) throws {
        try db.execute(sql: "DELETE FROM item_links WHERE source_id = ?", arguments: [itemID])
        for targetID in LinkParser.targetIDs(in: [note, bodyText]) where targetID != itemID {
            let exists = try Int.fetchOne(db, sql: "SELECT 1 FROM items WHERE id = ? LIMIT 1", arguments: [targetID])
            if exists == 1 {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO item_links(source_id, target_id) VALUES (?, ?)",
                    arguments: [itemID, targetID]
                )
            }
        }
    }

    private func hydrateTags(for items: [Item], db: Database) throws -> [Item] {
        guard !items.isEmpty else {
            return []
        }
        var hydrated = items
        for index in hydrated.indices {
            hydrated[index].tags = try String.fetchAll(
                db,
                sql: """
                    SELECT tags.name
                    FROM tags
                    JOIN item_tags ON item_tags.tag_id = tags.id
                    WHERE item_tags.item_id = ?
                    ORDER BY tags.name
                    """,
                arguments: [hydrated[index].id]
            )
        }
        return hydrated
    }

    private static func item(from row: Row) -> Item {
        guard let kind = ItemKind(rawValue: row["kind"]) else {
            return Item(kind: .note, title: "Tipo inválido")
        }
        return Item(
            id: row["id"],
            kind: kind,
            sourceURL: row["source_url"],
            title: row["title"],
            note: row["note"],
            bodyText: row["body_text"],
            summary: row["summary"],
            metadataJSON: row["meta_json"],
            capturedAt: row["captured_at"],
            createdAt: row["created_at"],
            updatedAt: row["updated_at"],
            tags: []
        )
    }

    private static func asset(from row: Row) -> AssetRecord {
        let role = AssetRole(rawValue: row["role"]) ?? .original
        return AssetRecord(
            id: row["id"],
            itemID: row["item_id"],
            role: role,
            mimeType: row["mime_type"],
            byteCount: row["byte_count"],
            encryptedPath: row["encrypted_path"],
            originalFilename: row["original_filename"],
            durationSeconds: row["duration_seconds"],
            width: row["width"],
            height: row["height"],
            createdAt: row["created_at"]
        )
    }

    private func normalizeTags(_ tags: [String]) -> [String] {
        Array(Set(tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty })).sorted()
    }

    private func ftsPattern(_ query: String) -> String {
        query
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                token
                    .filter { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
                    .lowercased()
            }
            .filter { !$0.isEmpty }
            .map { "\($0)*" }
            .joined(separator: " ")
    }
}
