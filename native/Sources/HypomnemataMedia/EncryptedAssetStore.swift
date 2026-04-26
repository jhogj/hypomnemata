import CryptoKit
import Foundation
import HypomnemataCore
import Security

public enum MediaError: LocalizedError, Equatable {
    case invalidKeyLength(Int)
    case missingCombinedCiphertext
    case assetNotFound(String)
    case randomGenerationFailed(OSStatus)

    public var errorDescription: String? {
        switch self {
        case let .invalidKeyLength(length):
            "A chave de assets precisa ter 32 bytes; recebeu \(length)."
        case .missingCombinedCiphertext:
            "CryptoKit não retornou ciphertext combinado."
        case let .assetNotFound(path):
            "Asset não encontrado: \(path)"
        case let .randomGenerationFailed(status):
            "Falha ao gerar chave aleatória de assets (SecRandomCopyBytes status \(status))."
        }
    }
}

public struct StoredEncryptedAsset: Sendable, Equatable {
    public var record: AssetRecord
    public var absoluteURL: URL

    public init(record: AssetRecord, absoluteURL: URL) {
        self.record = record
        self.absoluteURL = absoluteURL
    }
}

public final class EncryptedAssetStore: @unchecked Sendable {
    private let rootDirectory: URL
    private let cacheDirectory: URL
    private let key: SymmetricKey
    private let fileManager: FileManager

    public init(
        rootDirectory: URL,
        cacheDirectory: URL,
        keyData: Data,
        fileManager: FileManager = .default
    ) throws {
        guard keyData.count == 32 else {
            throw MediaError.invalidKeyLength(keyData.count)
        }
        self.rootDirectory = rootDirectory
        self.cacheDirectory = cacheDirectory
        self.key = SymmetricKey(data: keyData)
        self.fileManager = fileManager
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public static func generateKeyData() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw MediaError.randomGenerationFailed(status)
        }
        return Data(bytes)
    }

    public func write(
        data: Data,
        itemID: String,
        role: AssetRole,
        originalFilename: String?,
        mimeType: String?
    ) throws -> StoredEncryptedAsset {
        let now = Date()
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: now)
        let month = String(format: "%02d", calendar.component(.month, from: now))
        let assetID = UUIDV7.generateString(now: now)
        let relativePath = "\(year)/\(month)/\(itemID)/\(assetID).hasset"
        let absoluteURL = rootDirectory.appendingPathComponent(relativePath)
        try fileManager.createDirectory(
            at: absoluteURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw MediaError.missingCombinedCiphertext
        }
        try combined.write(to: absoluteURL, options: .atomic)

        let record = AssetRecord(
            id: assetID,
            itemID: itemID,
            role: role,
            mimeType: mimeType,
            byteCount: Int64(data.count),
            encryptedPath: relativePath,
            originalFilename: originalFilename
        )
        return StoredEncryptedAsset(record: record, absoluteURL: absoluteURL)
    }

    public func read(record: AssetRecord) throws -> Data {
        let encryptedURL = rootDirectory.appendingPathComponent(record.encryptedPath)
        guard fileManager.fileExists(atPath: encryptedURL.path) else {
            throw MediaError.assetNotFound(record.encryptedPath)
        }
        let sealedBox = try AES.GCM.SealedBox(combined: Data(contentsOf: encryptedURL))
        return try AES.GCM.open(sealedBox, using: key)
    }

    public func decryptToTemporaryFile(record: AssetRecord) throws -> URL {
        let data = try read(record: record)
        let filename = record.originalFilename?.isEmpty == false
            ? record.originalFilename!
            : "\(record.id).asset"
        let itemCache = cacheDirectory
            .appendingPathComponent(record.itemID, isDirectory: true)
            .appendingPathComponent(record.id, isDirectory: true)
        try fileManager.createDirectory(at: itemCache, withIntermediateDirectories: true)
        let targetURL = itemCache.appendingPathComponent(filename)
        try data.write(to: targetURL, options: .atomic)
        return targetURL
    }

    public func remove(record: AssetRecord) throws {
        let encryptedURL = rootDirectory.appendingPathComponent(record.encryptedPath)
        guard fileManager.fileExists(atPath: encryptedURL.path) else {
            return
        }
        try fileManager.removeItem(at: encryptedURL)
    }

    public func clearTemporaryCache() throws {
        try TemporaryCacheCleaner(fileManager: fileManager).clear(at: cacheDirectory)
    }
}
