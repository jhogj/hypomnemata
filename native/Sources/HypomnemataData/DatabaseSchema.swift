import Foundation
import GRDB

public enum DatabaseSchema {
    public static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE settings (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE items (
                    id TEXT PRIMARY KEY,
                    kind TEXT NOT NULL,
                    source_url TEXT,
                    title TEXT,
                    note TEXT,
                    body_text TEXT,
                    summary TEXT,
                    meta_json TEXT,
                    captured_at TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_items_kind ON items(kind)")
            try db.execute(sql: "CREATE INDEX idx_items_captured_at ON items(captured_at)")

            try db.execute(sql: """
                CREATE TABLE assets (
                    id TEXT PRIMARY KEY,
                    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                    role TEXT NOT NULL,
                    mime_type TEXT,
                    byte_count INTEGER NOT NULL DEFAULT 0,
                    encrypted_path TEXT NOT NULL,
                    original_filename TEXT,
                    duration_seconds REAL,
                    width INTEGER,
                    height INTEGER,
                    created_at TEXT NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_assets_item_id ON assets(item_id)")

            try db.execute(sql: """
                CREATE TABLE tags (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    name TEXT NOT NULL UNIQUE
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_tags_name ON tags(name)")

            try db.execute(sql: """
                CREATE TABLE item_tags (
                    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                    tag_id INTEGER NOT NULL REFERENCES tags(id) ON DELETE CASCADE,
                    PRIMARY KEY (item_id, tag_id)
                )
                """)

            try db.execute(sql: """
                CREATE TABLE folders (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """)

            try db.execute(sql: """
                CREATE TABLE folder_items (
                    folder_id TEXT NOT NULL REFERENCES folders(id) ON DELETE CASCADE,
                    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                    added_at TEXT NOT NULL,
                    PRIMARY KEY (folder_id, item_id)
                )
                """)

            try db.execute(sql: """
                CREATE TABLE item_links (
                    source_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                    target_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                    PRIMARY KEY (source_id, target_id)
                )
                """)

            try db.execute(sql: """
                CREATE TABLE chat_messages (
                    id TEXT PRIMARY KEY,
                    item_id TEXT NOT NULL REFERENCES items(id) ON DELETE CASCADE,
                    role TEXT NOT NULL,
                    content TEXT NOT NULL,
                    created_at TEXT NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_chat_messages_item_id ON chat_messages(item_id)")

            try db.execute(sql: """
                CREATE TABLE jobs (
                    id TEXT PRIMARY KEY,
                    item_id TEXT REFERENCES items(id) ON DELETE CASCADE,
                    kind TEXT NOT NULL,
                    status TEXT NOT NULL,
                    error TEXT,
                    attempts INTEGER NOT NULL DEFAULT 0,
                    payload_json TEXT,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                )
                """)
            try db.execute(sql: "CREATE INDEX idx_jobs_status ON jobs(status)")
            try db.execute(sql: "CREATE INDEX idx_jobs_item_id ON jobs(item_id)")

            try db.execute(sql: """
                CREATE VIRTUAL TABLE items_fts USING fts5(
                    title,
                    note,
                    body_text,
                    summary,
                    content='items',
                    content_rowid='rowid',
                    tokenize='unicode61 remove_diacritics 2'
                )
                """)
            try db.execute(sql: """
                CREATE TRIGGER items_ai AFTER INSERT ON items BEGIN
                    INSERT INTO items_fts(rowid, title, note, body_text, summary)
                    VALUES (new.rowid, coalesce(new.title,''), coalesce(new.note,''), coalesce(new.body_text,''), coalesce(new.summary,''));
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER items_ad AFTER DELETE ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, title, note, body_text, summary)
                    VALUES ('delete', old.rowid, coalesce(old.title,''), coalesce(old.note,''), coalesce(old.body_text,''), coalesce(old.summary,''));
                END
                """)
            try db.execute(sql: """
                CREATE TRIGGER items_au AFTER UPDATE ON items BEGIN
                    INSERT INTO items_fts(items_fts, rowid, title, note, body_text, summary)
                    VALUES ('delete', old.rowid, coalesce(old.title,''), coalesce(old.note,''), coalesce(old.body_text,''), coalesce(old.summary,''));
                    INSERT INTO items_fts(rowid, title, note, body_text, summary)
                    VALUES (new.rowid, coalesce(new.title,''), coalesce(new.note,''), coalesce(new.body_text,''), coalesce(new.summary,''));
                END
                """)
        }

        return migrator
    }
}
