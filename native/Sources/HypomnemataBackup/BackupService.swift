import Foundation
import HypomnemataCore
import HypomnemataData

public enum BackupError: LocalizedError, Equatable {
    case destinationNeedsSentinel(URL)
    case rsyncFailed(String)
    case rsyncMissing

    public var errorDescription: String? {
        switch self {
        case let .destinationNeedsSentinel(url):
            "Destino não vazio sem sentinel .hypomnemata-backup: \(url.path)"
        case let .rsyncFailed(message):
            "rsync falhou: \(message)"
        case .rsyncMissing:
            "rsync não encontrado em /usr/bin/rsync."
        }
    }
}

public struct BackupService {
    public static let sentinelName = ".hypomnemata-backup"

    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func exportZip(vaultRoot: URL, destinationDirectory: URL) throws -> URL {
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        let archiveBase = destinationDirectory.appendingPathComponent("hypomnemata-native-\(Int(Date().timeIntervalSince1970))")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-c", "-k", "--sequesterRsrc", "--keepParent", vaultRoot.path, "\(archiveBase.path).zip"]
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw BackupError.rsyncFailed("ditto saiu com código \(process.terminationStatus)")
        }
        return URL(fileURLWithPath: "\(archiveBase.path).zip")
    }

    public func incrementalBackup(vaultRoot: URL, backupDirectory: URL) throws {
        guard fileManager.fileExists(atPath: "/usr/bin/rsync") else {
            throw BackupError.rsyncMissing
        }
        try ensureBackupDestination(backupDirectory)

        let process = Process()
        let stderr = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
        process.arguments = ["-a", "--delete", vaultRoot.path.ensureTrailingSlash, backupDirectory.path.ensureTrailingSlash]
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "código \(process.terminationStatus)"
            throw BackupError.rsyncFailed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private func ensureBackupDestination(_ backupDirectory: URL) throws {
        let sentinel = backupDirectory.appendingPathComponent(Self.sentinelName)
        if fileManager.fileExists(atPath: backupDirectory.path) {
            let contents = try fileManager.contentsOfDirectory(atPath: backupDirectory.path)
            if !contents.isEmpty && !fileManager.fileExists(atPath: sentinel.path) {
                throw BackupError.destinationNeedsSentinel(backupDirectory)
            }
        }
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: sentinel.path) {
            fileManager.createFile(atPath: sentinel.path, contents: Data())
        }
    }
}

private extension String {
    var ensureTrailingSlash: String {
        hasSuffix("/") ? self : self + "/"
    }
}
