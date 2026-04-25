import Foundation
import GRDB
import HypomnemataCore

public final class NativeDatabase: @unchecked Sendable {
    public let writer: DatabaseQueue
    public let databaseURL: URL

    public init(
        databaseURL: URL,
        passphrase: String,
        requireSQLCipher: Bool = true,
        fileManager: FileManager = .default
    ) throws {
        let directory = databaseURL.deletingLastPathComponent()
        guard !databaseURL.path.isEmpty else {
            throw DataError.invalidDatabasePath(databaseURL)
        }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        var configuration = Configuration()
        configuration.label = "HypomnemataNative"
        configuration.prepareDatabase { db in
            try db.usePassphrase(passphrase)

            if requireSQLCipher {
                let cipherVersion = try String.fetchOne(db, sql: "PRAGMA cipher_version") ?? ""
                guard !cipherVersion.isEmpty else {
                    throw DataError.sqlCipherUnavailable
                }
            }

            try db.execute(sql: "PRAGMA foreign_keys = ON")
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA synchronous = NORMAL")
        }

        writer = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        self.databaseURL = databaseURL
        try DatabaseSchema.migrator().migrate(writer)
        try seedVaultSettings(passphraseMarker: requireSQLCipher ? "sqlcipher" : "plaintext-dev")
    }

    public convenience init(
        appPaths: AppPaths,
        passphrase: String,
        requireSQLCipher: Bool = true
    ) throws {
        try appPaths.ensureDirectories()
        try self.init(
            databaseURL: appPaths.databaseURL,
            passphrase: passphrase,
            requireSQLCipher: requireSQLCipher
        )
    }

    public func close() throws {
        try writer.close()
    }

    private func seedVaultSettings(passphraseMarker: String) throws {
        try writer.write { db in
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO settings(key, value)
                    VALUES ('vault_format', ?), ('database_protection', ?)
                    """,
                arguments: ["native-v1", passphraseMarker]
            )
        }
    }

    private static func sqlLiteral(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }
}
