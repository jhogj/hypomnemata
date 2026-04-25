import AppKit
import AVFoundation
import Foundation
import PDFKit

public enum ThumbnailGenerationError: LocalizedError, Equatable {
    case unsupportedAsset
    case unreadableImage
    case unreadablePDF
    case unreadableVideo
    case encodingFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedAsset:
            "Asset sem thumbnail nativo suportado."
        case .unreadableImage:
            "Não foi possível carregar a imagem para gerar thumbnail."
        case .unreadablePDF:
            "Não foi possível carregar a primeira página do PDF."
        case .unreadableVideo:
            "Não foi possível capturar um frame do vídeo."
        case .encodingFailed:
            "Não foi possível codificar o thumbnail em JPEG."
        }
    }
}

public struct NativeThumbnailGenerator: Sendable {
    private let maxPixelSize: CGFloat

    public init(maxPixelSize: CGFloat = 960) {
        self.maxPixelSize = maxPixelSize
    }

    public func makeJPEGThumbnailData(for fileURL: URL, mimeType: String?) throws -> Data {
        let image: NSImage
        if isImage(fileURL: fileURL, mimeType: mimeType) {
            guard let source = NSImage(contentsOf: fileURL) else {
                throw ThumbnailGenerationError.unreadableImage
            }
            image = source
        } else if isPDF(fileURL: fileURL, mimeType: mimeType) {
            guard
                let document = PDFDocument(url: fileURL),
                let page = document.page(at: 0)
            else {
                throw ThumbnailGenerationError.unreadablePDF
            }
            image = page.thumbnail(of: CGSize(width: maxPixelSize, height: maxPixelSize), for: .cropBox)
        } else if isVideo(fileURL: fileURL, mimeType: mimeType) {
            image = try makeVideoThumbnail(fileURL: fileURL)
        } else {
            throw ThumbnailGenerationError.unsupportedAsset
        }

        return try encodeJPEG(image.scaledToFit(maxPixelSize: maxPixelSize))
    }

    private func makeVideoThumbnail(fileURL: URL) throws -> NSImage {
        let asset = AVURLAsset(url: fileURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        let preferredTime = CMTime(seconds: 1, preferredTimescale: 600)
        let fallbackTime = CMTime(seconds: 0, preferredTimescale: 600)
        let image: CGImage
        do {
            image = try generator.copyCGImage(at: preferredTime, actualTime: nil)
        } catch {
            do {
                image = try generator.copyCGImage(at: fallbackTime, actualTime: nil)
            } catch {
                throw ThumbnailGenerationError.unreadableVideo
            }
        }
        return NSImage(cgImage: image, size: .zero)
    }

    private func encodeJPEG(_ image: NSImage) throws -> Data {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let data = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.84])
        else {
            throw ThumbnailGenerationError.encodingFailed
        }
        return data
    }

    private func isImage(fileURL: URL, mimeType: String?) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        return mimeType?.lowercased().hasPrefix("image/") == true
            || ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"].contains(ext)
    }

    private func isPDF(fileURL: URL, mimeType: String?) -> Bool {
        mimeType?.lowercased() == "application/pdf" || fileURL.pathExtension.lowercased() == "pdf"
    }

    private func isVideo(fileURL: URL, mimeType: String?) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        return mimeType?.lowercased().hasPrefix("video/") == true
            || ["mp4", "mov", "m4v", "webm", "mkv", "avi"].contains(ext)
    }
}

private extension NSImage {
    func scaledToFit(maxPixelSize: CGFloat) -> NSImage {
        guard size.width > maxPixelSize || size.height > maxPixelSize else {
            return self
        }
        let ratio = min(maxPixelSize / size.width, maxPixelSize / size.height)
        let targetSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let scaled = NSImage(size: targetSize)
        scaled.lockFocus()
        draw(in: CGRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        scaled.unlockFocus()
        return scaled
    }
}
