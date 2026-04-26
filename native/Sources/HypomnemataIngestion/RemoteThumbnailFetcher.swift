import Foundation

public struct RemoteThumbnailResult: Sendable, Equatable {
    public var data: Data
    public var mimeType: String?
    public var originalFilename: String
    public var sourceURL: String?

    public init(data: Data, mimeType: String? = nil, originalFilename: String, sourceURL: String? = nil) {
        self.data = data
        self.mimeType = mimeType
        self.originalFilename = originalFilename
        self.sourceURL = sourceURL
    }
}

public enum RemoteThumbnailError: LocalizedError, Equatable, Sendable {
    case missingURL
    case binaryFailed(exitCode: Int32, message: String)
    case noImageFound
    case invalidOEmbed(String)
    case fetchFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingURL:
            "Item sem URL — não há miniatura remota para buscar."
        case let .binaryFailed(code, message):
            "gallery-dl falhou (exit \(code)): \(message)"
        case .noImageFound:
            "Não foi possível encontrar imagem para miniatura."
        case let .invalidOEmbed(detail):
            "Resposta oEmbed inválida: \(detail)"
        case let .fetchFailed(detail):
            "Falha ao baixar miniatura: \(detail)"
        }
    }
}

public protocol RemoteThumbnailFetcher: Sendable {
    func fetchThumbnail(url: String) async throws -> RemoteThumbnailResult
}

public struct GalleryDLThumbnailFetcher: RemoteThumbnailFetcher {
    private let galleryDLPath: String
    private let runProcess: @Sendable (String, [String], URL) throws -> SubprocessResult
    private let fetchData: @Sendable (String) async throws -> (Data, String?)

    public init(
        galleryDLPath: String = "gallery-dl",
        runProcess: (@Sendable (String, [String], URL) throws -> SubprocessResult)? = nil,
        fetchData: (@Sendable (String) async throws -> (Data, String?))? = nil
    ) {
        self.galleryDLPath = galleryDLPath
        self.runProcess = runProcess ?? Self.defaultRunProcess
        self.fetchData = fetchData ?? Self.defaultFetchData
    }

    public func fetchThumbnail(url: String) async throws -> RemoteThumbnailResult {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw RemoteThumbnailError.missingURL
        }

        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("hypomnemata-gallery-dl-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        do {
            if let result = try runGalleryDL(url: trimmed, workingDirectory: tempDirectory) {
                return result
            }
        } catch RemoteThumbnailError.binaryFailed {
            // gallery-dl can fail on rate limits or unsupported tweet shapes; oEmbed is the fallback.
        }

        return try await fetchOEmbedThumbnail(url: trimmed)
    }

    private func runGalleryDL(url: String, workingDirectory: URL) throws -> RemoteThumbnailResult? {
        let result = try runProcess(
            galleryDLPath,
            ["-D", workingDirectory.path, url],
            workingDirectory
        )
        guard result.exitCode == 0 else {
            throw RemoteThumbnailError.binaryFailed(exitCode: result.exitCode, message: stderrText(result.stderr))
        }
        guard let image = try imageFiles(in: workingDirectory)
            .max(by: { $0.byteCount < $1.byteCount })?
            .url
        else {
            return nil
        }
        return RemoteThumbnailResult(
            data: try Data(contentsOf: image),
            mimeType: Self.mimeType(for: image),
            originalFilename: image.lastPathComponent,
            sourceURL: url
        )
    }

    private func fetchOEmbedThumbnail(url: String) async throws -> RemoteThumbnailResult {
        guard let encodedURL = url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw RemoteThumbnailError.invalidOEmbed("URL inválida")
        }
        let oembedURL = "https://publish.twitter.com/oembed?omit_script=true&url=\(encodedURL)"
        let (jsonData, _) = try await fetchData(oembedURL)
        let imageURL = try Self.thumbnailURL(fromOEmbedJSON: jsonData)
        let (imageData, mime) = try await fetchData(imageURL)
        guard !imageData.isEmpty else {
            throw RemoteThumbnailError.noImageFound
        }
        let filename = URL(string: imageURL)?.lastPathComponent.nilIfEmpty ?? "tweet-thumbnail"
        return RemoteThumbnailResult(
            data: imageData,
            mimeType: mime,
            originalFilename: filename,
            sourceURL: imageURL
        )
    }

    static func thumbnailURL(fromOEmbedJSON data: Data) throws -> String {
        do {
            let object = try JSONSerialization.jsonObject(with: data, options: [])
            guard let dict = object as? [String: Any] else {
                throw RemoteThumbnailError.invalidOEmbed("JSON sem objeto raiz")
            }
            if let thumbnail = (dict["thumbnail_url"] as? String)?.trimmedNonEmpty {
                return thumbnail
            }
            if let html = dict["html"] as? String,
               let src = firstImageSource(in: html) {
                return src
            }
            throw RemoteThumbnailError.noImageFound
        } catch let error as RemoteThumbnailError {
            throw error
        } catch {
            throw RemoteThumbnailError.invalidOEmbed(error.localizedDescription)
        }
    }

    private static func firstImageSource(in html: String) -> String? {
        guard let range = html.range(of: #"src=["']([^"']+)["']"#, options: .regularExpression) else {
            return nil
        }
        let match = String(html[range])
        return match
            .replacingOccurrences(of: #"src=["']"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"["']$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func imageFiles(in directory: URL) throws -> [(url: URL, byteCount: Int64)] {
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, Self.isImage(url) else { return nil }
            return (url, Int64(values.fileSize ?? 0))
        }
    }

    private func stderrText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?.trimmedNonEmpty ?? "sem detalhes"
    }

    private static func isImage(_ url: URL) -> Bool {
        ["jpg", "jpeg", "png", "webp", "gif", "heic"].contains(url.pathExtension.lowercased())
    }

    private static func mimeType(for url: URL) -> String? {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": "image/jpeg"
        case "png": "image/png"
        case "webp": "image/webp"
        case "gif": "image/gif"
        case "heic": "image/heic"
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
            throw RemoteThumbnailError.fetchFailed("URL inválida: \(url)")
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: target)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw RemoteThumbnailError.fetchFailed("HTTP \(http.statusCode)")
            }
            let mime = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type")
            return (data, mime)
        } catch let error as RemoteThumbnailError {
            throw error
        } catch {
            throw RemoteThumbnailError.fetchFailed(error.localizedDescription)
        }
    }
}

private extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let self, !self.isEmpty else { return nil }
        return self
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
