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

public struct DownloadedMediaThumbnail: Sendable, Equatable {
    public var data: Data
    public var mimeType: String?
    public var originalFilename: String
    public var sourceURL: String

    public init(data: Data, mimeType: String? = nil, originalFilename: String, sourceURL: String) {
        self.data = data
        self.mimeType = mimeType
        self.originalFilename = originalFilename
        self.sourceURL = sourceURL
    }
}

public struct MediaDownloadResult: Sendable, Equatable {
    public enum Kind: String, Sendable {
        case video
        case audio
    }

    public var data: Data
    public var mimeType: String?
    public var originalFilename: String
    public var kind: Kind
    public var title: String?
    public var durationSeconds: Double?
    public var webpageURL: String?
    public var subtitles: [DownloadedSubtitle]
    public var thumbnail: DownloadedMediaThumbnail?

    public init(
        data: Data,
        mimeType: String? = nil,
        originalFilename: String,
        kind: Kind = .video,
        title: String? = nil,
        durationSeconds: Double? = nil,
        webpageURL: String? = nil,
        subtitles: [DownloadedSubtitle] = [],
        thumbnail: DownloadedMediaThumbnail? = nil
    ) {
        self.data = data
        self.mimeType = mimeType
        self.originalFilename = originalFilename
        self.kind = kind
        self.title = title
        self.durationSeconds = durationSeconds
        self.webpageURL = webpageURL
        self.subtitles = subtitles
        self.thumbnail = thumbnail
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
    func download(url: String, mode: MediaDownloadMode) async throws -> MediaDownloadResult
}

public extension MediaDownloader {
    func download(url: String) async throws -> MediaDownloadResult {
        try await download(url: url, mode: .video)
    }
}

public enum MediaDownloadMode: Sendable, Equatable {
    case video
    case audio
}

public struct YTDLPMediaDownloader: MediaDownloader {
    private let ytDLPPath: String
    private let runProcess: @Sendable (String, [String], URL) throws -> SubprocessResult
    private let fetchData: @Sendable (String) async throws -> (Data, String?)

    public init(
        ytDLPPath: String = "yt-dlp",
        runProcess: (@Sendable (String, [String], URL) throws -> SubprocessResult)? = nil,
        fetchData: (@Sendable (String) async throws -> (Data, String?))? = nil
    ) {
        self.ytDLPPath = ytDLPPath
        self.runProcess = runProcess ?? Self.defaultRunProcess
        self.fetchData = fetchData ?? Self.defaultFetchData
    }

    public func download(url: String, mode: MediaDownloadMode = .video) async throws -> MediaDownloadResult {
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
        switch mode {
        case .video:
            try runVideoDownload(url: trimmed, workingDirectory: tempDirectory)
            try? runSubtitleDownload(url: trimmed, workingDirectory: tempDirectory)
        case .audio:
            try runAudioDownload(url: trimmed, workingDirectory: tempDirectory)
        }
        let thumbnail = mode == .video
            ? await fetchThumbnailIfAvailable(metadata.thumbnailURL)
            : nil
        return try collectResult(
            mode: mode,
            metadata: metadata,
            sourceURL: trimmed,
            workingDirectory: tempDirectory,
            thumbnail: thumbnail
        )
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
                webpageURL: trimmedNonEmpty(dict["webpage_url"] as? String),
                thumbnailURL: thumbnailURL(from: dict)
            )
        } catch let error as MediaDownloadError {
            throw error
        } catch {
            throw MediaDownloadError.invalidOutput(error.localizedDescription)
        }
    }

    private func runVideoDownload(url: String, workingDirectory: URL) throws {
        let result = try runProcess(
            ytDLPPath,
            [
                "--no-warnings",
                "-f", "bv*[vcodec^=avc1][height<=1080]+ba[ext=m4a]/b[vcodec^=avc1][acodec!=none][height<=1080]/b[ext=mp4][vcodec^=avc1][height<=1080]",
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

    private func runAudioDownload(url: String, workingDirectory: URL) throws {
        let result = try runProcess(
            ytDLPPath,
            [
                "--no-warnings",
                "-f", "ba[ext=m4a]/bestaudio/best",
                "--extract-audio",
                "--audio-format", "m4a",
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

    private func collectResult(
        mode: MediaDownloadMode,
        metadata: Metadata,
        sourceURL: String,
        workingDirectory: URL,
        thumbnail: DownloadedMediaThumbnail?
    ) throws -> MediaDownloadResult {
        let files = try regularFiles(in: workingDirectory)
        guard let mediaURL = files
            .filter({ mode == .video ? Self.isLikelyVideo($0.url) : Self.isLikelyAudio($0.url) })
            .max(by: { $0.byteCount < $1.byteCount })?
            .url
        else {
            throw MediaDownloadError.outputNotFound
        }

        let mediaData: Data
        do {
            mediaData = try Data(contentsOf: mediaURL)
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
            data: mediaData,
            mimeType: Self.mimeType(for: mediaURL),
            originalFilename: mediaURL.lastPathComponent,
            kind: mode == .video ? .video : .audio,
            title: metadata.title,
            durationSeconds: metadata.durationSeconds,
            webpageURL: metadata.webpageURL ?? sourceURL,
            subtitles: mode == .video ? subtitles : [],
            thumbnail: thumbnail
        )
    }

    private func fetchThumbnailIfAvailable(_ url: String?) async -> DownloadedMediaThumbnail? {
        guard let url else {
            return nil
        }
        do {
            let (data, mimeType) = try await fetchData(url)
            guard !data.isEmpty else {
                return nil
            }
            return DownloadedMediaThumbnail(
                data: data,
                mimeType: mimeType,
                originalFilename: Self.thumbnailFilename(from: url),
                sourceURL: url
            )
        } catch {
            return nil
        }
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

    private static func isLikelyAudio(_ url: URL) -> Bool {
        ["m4a", "mp3", "aac", "opus", "ogg", "webm", "wav", "flac"].contains(url.pathExtension.lowercased())
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
        case "m4a": "audio/mp4"
        case "mp3": "audio/mpeg"
        case "aac": "audio/aac"
        case "opus": "audio/opus"
        case "ogg": "audio/ogg"
        case "wav": "audio/wav"
        case "flac": "audio/flac"
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

    @Sendable
    private static func defaultFetchData(url: String) async throws -> (Data, String?) {
        guard let target = URL(string: url) else {
            throw MediaDownloadError.invalidOutput("URL de thumbnail inválida")
        }
        let (data, response) = try await URLSession.shared.data(from: target)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw MediaDownloadError.invalidOutput("HTTP \(http.statusCode) ao baixar thumbnail")
        }
        let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
        return (data, mime)
    }

    private static func thumbnailFilename(from url: String) -> String {
        guard let parsed = URL(string: url) else {
            return "media-thumbnail"
        }
        let lastPathComponent = parsed.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        return lastPathComponent.isEmpty ? "media-thumbnail" : lastPathComponent
    }
}

private struct Metadata {
    var title: String?
    var durationSeconds: Double?
    var webpageURL: String?
    var thumbnailURL: String?
}

private func thumbnailURL(from dict: [String: Any]) -> String? {
    if let thumbnail = trimmedNonEmpty(dict["thumbnail"] as? String) {
        return thumbnail
    }
    guard let thumbnails = dict["thumbnails"] as? [[String: Any]] else {
        return nil
    }
    return thumbnails
        .compactMap { entry -> (url: String, preference: Int) in
            let preference = (entry["preference"] as? Int) ?? 0
            return (trimmedNonEmpty(entry["url"] as? String) ?? "", preference)
        }
        .filter { !$0.url.isEmpty }
        .max { $0.preference < $1.preference }?
        .url
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
