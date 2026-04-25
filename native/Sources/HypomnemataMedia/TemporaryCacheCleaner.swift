import Foundation

public struct TemporaryCacheCleaner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func clear(at cacheDirectory: URL) throws {
        if fileManager.fileExists(atPath: cacheDirectory.path) {
            try fileManager.removeItem(at: cacheDirectory)
        }
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }
}
