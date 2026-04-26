import Foundation

public struct DownloadedSubtitle: Sendable, Equatable {
    public var data: Data
    public var mimeType: String?
    public var originalFilename: String

    public init(data: Data, mimeType: String? = nil, originalFilename: String) {
        self.data = data
        self.mimeType = mimeType
        self.originalFilename = originalFilename
    }
}

public struct MediaDownloadResult: Sendable, Equatable {
    public var data: Data
    public var mimeType: String?
    public var originalFilename: String
    public var title: String?
    public var durationSeconds: Double?
    public var webpageURL: String?
    public var subtitles: [DownloadedSubtitle]

    public init(
        data: Data,
        mimeType: String? = nil,
        originalFilename: String,
        title: String? = nil,
        durationSeconds: Double? = nil,
        webpageURL: String? = nil,
        subtitles: [DownloadedSubtitle] = []
    ) {
        self.data = data
        self.mimeType = mimeType
        self.originalFilename = originalFilename
        self.title = title
        self.durationSeconds = durationSeconds
        self.webpageURL = webpageURL
        self.subtitles = subtitles
    }
}

public enum MediaDownloadError: LocalizedError, Equatable, Sendable {
    case missingURL
    case binaryFailed(exitCode: Int32, message: String)
    case invalidOutput(String)
    case outputNotFound
    case fileReadFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingURL:
            "Item sem URL — não há mídia para baixar."
        case let .binaryFailed(code, message):
            "yt-dlp falhou (exit \(code)): \(message)"
        case let .invalidOutput(detail):
            "Saída do yt-dlp inválida: \(detail)"
        case .outputNotFound:
            "yt-dlp terminou sem gerar arquivo de mídia."
        case let .fileReadFailed(detail):
            "Falha ao ler mídia baixada: \(detail)"
        }
    }
}

public protocol MediaDownloader: Sendable {
    func download(url: String) async throws -> MediaDownloadResult
}

public struct YTDLPMediaDownloader: MediaDownloader {
    private let ytDLPPath: String
    private let runProcess: @Sendable (String, [String], URL) throws -> SubprocessResult

    public init(
        ytDLPPath: String = "yt-dlp",
        runProcess: (@Sendable (String, [String], URL) throws -> SubprocessResult)? = nil
    ) {
        self.ytDLPPath = ytDLPPath
        self.runProcess = runProcess ?? Self.defaultRunProcess
    }

    public func download(url: String) async throws -> MediaDownloadResult {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MediaDownloadError.missingURL
        }

        let fileManager = FileManager.default
        let tempDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("hypomnemata-yt-dlp-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: tempDirectory) }

        let metadata = try loadMetadata(url: trimmed, workingDirectory: tempDirectory)
        try runDownload(url: trimmed, workingDirectory: tempDirectory)
        try? runSubtitleDownload(url: trimmed, workingDirectory: tempDirectory)
        return try collectResult(metadata: metadata, sourceURL: trimmed, workingDirectory: tempDirectory)
    }

    private func loadMetadata(url: String, workingDirectory: URL) throws -> Metadata {
        let result = try runProcess(
            ytDLPPath,
            ["--dump-json", "--no-warnings", url],
            workingDirectory
        )
        guard result.exitCode == 0 else {
            throw MediaDownloadError.binaryFailed(exitCode: result.exitCode, message: stderrText(result.stderr))
        }
        guard !result.stdout.isEmpty else {
            return Metadata()
        }
        do {
            let object = try JSONSerialization.jsonObject(with: result.stdout, options: [])
            guard let dict = object as? [String: Any] else {
                throw MediaDownloadError.invalidOutput("JSON sem objeto raiz")
            }
            return Metadata(
                title: trimmedNonEmpty(dict["title"] as? String),
                durationSeconds: doubleValue(dict["duration"]),
                webpageURL: trimmedNonEmpty(dict["webpage_url"] as? String)
            )
        } catch let error as MediaDownloadError {
            throw error
        } catch {
            throw MediaDownloadError.invalidOutput(error.localizedDescription)
        }
    }

    private func runDownload(url: String, workingDirectory: URL) throws {
        let result = try runProcess(
            ytDLPPath,
            [
                "--no-warnings",
                "--merge-output-format", "mp4",
                "-o", "%(title).200B [%(id)s].%(ext)s",
                url,
            ],
            workingDirectory
        )
        guard result.exitCode == 0 else {
            throw MediaDownloadError.binaryFailed(exitCode: result.exitCode, message: stderrText(result.stderr))
        }
    }

    private func runSubtitleDownload(url: String, workingDirectory: URL) throws {
        _ = try runProcess(
            ytDLPPath,
            [
                "--no-warnings",
                "--skip-download",
                "--write-subs",
                "--write-auto-subs",
                "--sub-langs", "pt.*,pt,en.*,en",
                "-o", "%(title).200B [%(id)s].%(ext)s",
                url,
            ],
            workingDirectory
        )
    }

    private func collectResult(metadata: Metadata, sourceURL: String, workingDirectory: URL) throws -> MediaDownloadResult {
        let files = try regularFiles(in: workingDirectory)
        guard let videoURL = files
            .filter({ Self.isLikelyVideo($0.url) })
            .max(by: { $0.byteCount < $1.byteCount })?
            .url
        else {
            throw MediaDownloadError.outputNotFound
        }

        let videoData: Data
        do {
            videoData = try Data(contentsOf: videoURL)
        } catch {
            throw MediaDownloadError.fileReadFailed(error.localizedDescription)
        }

        let subtitles = try files
            .map(\.url)
            .filter(Self.isLikelySubtitle)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { url in
                DownloadedSubtitle(
                    data: try Data(contentsOf: url),
                    mimeType: Self.mimeType(for: url),
                    originalFilename: url.lastPathComponent
                )
            }

        return MediaDownloadResult(
            data: videoData,
            mimeType: Self.mimeType(for: videoURL),
            originalFilename: videoURL.lastPathComponent,
            title: metadata.title,
            durationSeconds: metadata.durationSeconds,
            webpageURL: metadata.webpageURL ?? sourceURL,
            subtitles: subtitles
        )
    }

    private func regularFiles(in directory: URL) throws -> [(url: URL, byteCount: Int64)] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { return nil }
            return (url, Int64(values.fileSize ?? 0))
        }
    }

    private func stderrText(_ data: Data) -> String {
        trimmedNonEmpty(String(data: data, encoding: .utf8)) ?? "sem detalhes"
    }

    private static func isLikelyVideo(_ url: URL) -> Bool {
        ["mp4", "mov", "m4v", "webm", "mkv"].contains(url.pathExtension.lowercased())
    }

    private static func isLikelySubtitle(_ url: URL) -> Bool {
        ["vtt", "srt", "ass"].contains(url.pathExtension.lowercased())
    }

    private static func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "mp4": "video/mp4"
        case "mov": "video/quicktime"
        case "m4v": "video/x-m4v"
        case "webm": "video/webm"
        case "mkv": "video/x-matroska"
        case "vtt": "text/vtt; charset=utf-8"
        case "srt": "application/x-subrip; charset=utf-8"
        case "ass": "text/plain; charset=utf-8"
        default: nil
        }
    }

    @Sendable
    private static func defaultRunProcess(executable: String, arguments: [String], workingDirectory: URL) throws -> SubprocessResult {
        try SubprocessRunner().run(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory
        )
    }
}

private struct Metadata {
    var title: String?
    var durationSeconds: Double?
    var webpageURL: String?
}

private func doubleValue(_ value: Any?) -> Double? {
    if let value = value as? Double {
        return value
    }
    if let value = value as? Int {
        return Double(value)
    }
    if let value = value as? String {
        return Double(value)
    }
    return nil
}

private func trimmedNonEmpty(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
        return nil
    }
    return trimmed
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}
