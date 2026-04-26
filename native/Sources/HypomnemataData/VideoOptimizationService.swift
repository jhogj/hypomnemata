import Foundation
import HypomnemataCore
import HypomnemataIngestion
import HypomnemataMedia

public enum OptimizeOutcome: Equatable, Sendable {
    case optimized(originalBytes: Int64, newBytes: Int64, asset: AssetRecord)
    case alreadyOptimized(originalBytes: Int64, asset: AssetRecord)
}

public enum VideoOptimizationServiceError: LocalizedError, Equatable, Sendable {
    case unsupportedAsset(String)
    case alreadyOptimized(String)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedAsset(id):
            "Asset não é um vídeo otimizável: \(id)."
        case let .alreadyOptimized(id):
            "Asset já foi otimizado: \(id)."
        }
    }
}

public struct VideoOptimizationService {
    private let repository: any ItemRepository
    private let assetStore: EncryptedAssetStore
    private let fileManager: FileManager

    public init(
        repository: any ItemRepository,
        assetStore: EncryptedAssetStore,
        fileManager: FileManager = .default
    ) {
        self.repository = repository
        self.assetStore = assetStore
        self.fileManager = fileManager
    }

    public func optimizeVideoAsset(
        record: AssetRecord,
        optimizer: any VideoOptimizer,
        progress: @Sendable @escaping (Double) -> Void = { _ in },
        isCancelled: @Sendable @escaping () -> Bool = { false }
    ) async throws -> OptimizeOutcome {
        guard Self.isVideoAsset(record) else {
            throw VideoOptimizationServiceError.unsupportedAsset(record.id)
        }
        guard record.optimizedAt == nil else {
            throw VideoOptimizationServiceError.alreadyOptimized(record.id)
        }

        let originalBytes = record.byteCount
        try saveOriginalSizeMetadata(itemID: record.itemID, originalBytes: originalBytes)

        let inputURL = try assetStore.decryptToTemporaryFile(record: record)
        let outputURL = fileManager.temporaryDirectory
            .appendingPathComponent("hypomnemata-optimize-\(UUID().uuidString).mp4")
        defer {
            try? fileManager.removeItem(at: inputURL)
            try? fileManager.removeItem(at: outputURL)
        }

        let result = try await optimizer.optimize(
            input: inputURL,
            output: outputURL,
            progress: progress,
            isCancelled: isCancelled
        )
        let optimizedAt = ClockTimestamp.nowISO8601()

        if result.outputBytes >= originalBytes {
            var updated = record
            updated.optimizedAt = optimizedAt
            try repository.updateAsset(updated)
            return .alreadyOptimized(originalBytes: originalBytes, asset: updated)
        }

        let replacementData = try Data(contentsOf: outputURL)
        var replacement = try assetStore.writeReplacement(
            data: replacementData,
            for: record,
            optimizedAt: optimizedAt
        ).record
        replacement.durationSeconds = result.durationSeconds

        do {
            try repository.updateAsset(replacement)
        } catch {
            try? assetStore.remove(record: replacement)
            throw error
        }

        try assetStore.remove(record: record)
        return .optimized(
            originalBytes: originalBytes,
            newBytes: replacement.byteCount,
            asset: replacement
        )
    }

    public static func isVideoAsset(_ record: AssetRecord) -> Bool {
        if record.role != .original {
            return false
        }
        if let mime = record.mimeType?.lowercased(), mime.hasPrefix("video/") {
            return true
        }
        let filename = record.originalFilename?.lowercased() ?? ""
        return [".mp4", ".mov", ".m4v"].contains { filename.hasSuffix($0) }
    }

    private func saveOriginalSizeMetadata(itemID: String, originalBytes: Int64) throws {
        let item = try repository.item(id: itemID)
        var metadata = Self.metadataDictionary(from: item.metadataJSON)
        metadata["video_original_size_bytes"] = originalBytes
        let data = try JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys])
        let json = String(data: data, encoding: .utf8)
        _ = try repository.patchItem(id: itemID, patch: ItemPatch(metadataJSON: json))
    }

    private static func metadataDictionary(from json: String?) -> [String: Any] {
        guard
            let json,
            let data = json.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data),
            let dictionary = object as? [String: Any]
        else {
            return [:]
        }
        return dictionary
    }
}
