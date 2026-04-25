import Foundation
import GRDB
import HypomnemataCore
import Security

public final class NativeDatabase: @unchecked Sendable {
    private static let assetKeySetting = "asset_key_v1"

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

    public func loadOrCreateAssetKeyData() throws -> Data {
        try writer.write { db in
            if let encoded = try String.fetchOne(
                db,
                sql: "SELECT value FROM settings WHERE key = ?",
                arguments: [Self.assetKeySetting]
            ) {
                guard let keyData = Data(base64Encoded: encoded), keyData.count == 32 else {
                    throw DataError.invalidStoredAssetKey
                }
                return keyData
            }

            let keyData = try Self.generateAssetKeyData()
            try db.execute(
                sql: "INSERT INTO settings(key, value) VALUES (?, ?)",
                arguments: [Self.assetKeySetting, keyData.base64EncodedString()]
            )
            return keyData
        }
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

    private static func generateAssetKeyData() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw DataError.assetKeyGenerationFailed(status)
        }
        return Data(bytes)
    }
}
