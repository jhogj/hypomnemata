import Foundation

public struct AppPaths: Sendable {
    public var rootDirectory: URL

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
    }

    public static func production(fileManager: FileManager = .default) throws -> AppPaths {
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return AppPaths(rootDirectory: base.appendingPathComponent("Hypomnemata", isDirectory: true))
    }

    public var databaseURL: URL {
        rootDirectory.appendingPathComponent("Hypomnemata.sqlite", isDirectory: false)
    }

    public var assetsDirectory: URL {
        rootDirectory.appendingPathComponent("Assets", isDirectory: true)
    }

    public var temporaryCacheDirectory: URL {
        rootDirectory.appendingPathComponent("TemporaryCache", isDirectory: true)
    }

    public func ensureDirectories(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assetsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: temporaryCacheDirectory, withIntermediateDirectories: true)
    }
}
