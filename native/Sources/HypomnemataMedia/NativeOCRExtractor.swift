import AppKit
import Foundation
import PDFKit
import Vision

public enum NativeOCRError: LocalizedError, Equatable {
    case unsupportedAsset
    case unreadableImage
    case unreadablePDF
    case visionFailed

    public var errorDescription: String? {
        switch self {
        case .unsupportedAsset:
            "Asset sem OCR nativo suportado."
        case .unreadableImage:
            "Não foi possível carregar a imagem para OCR."
        case .unreadablePDF:
            "Não foi possível carregar o PDF para OCR."
        case .visionFailed:
            "Vision não conseguiu reconhecer texto no asset."
        }
    }
}

public struct NativeOCRExtractor: Sendable {
    private let pdfPageLimit: Int

    public init(pdfPageLimit: Int = 12) {
        self.pdfPageLimit = pdfPageLimit
    }

    public func extractText(from fileURL: URL, mimeType: String?) throws -> String {
        if isImage(fileURL: fileURL, mimeType: mimeType) {
            guard let image = NSImage(contentsOf: fileURL) else {
                throw NativeOCRError.unreadableImage
            }
            return try recognizeText(in: image)
        }

        if isPDF(fileURL: fileURL, mimeType: mimeType) {
            guard let document = PDFDocument(url: fileURL) else {
                throw NativeOCRError.unreadablePDF
            }
            if let nativeText = document.string?.trimmingCharacters(in: .whitespacesAndNewlines), !nativeText.isEmpty {
                return nativeText
            }
            return try recognizeText(in: document)
        }

        throw NativeOCRError.unsupportedAsset
    }

    private func recognizeText(in document: PDFDocument) throws -> String {
        let pageCount = min(document.pageCount, pdfPageLimit)
        var pageTexts: [String] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else {
                continue
            }
            let image = page.thumbnail(of: CGSize(width: 1800, height: 1800), for: .cropBox)
            let text = try recognizeText(in: image)
            if !text.isEmpty {
                pageTexts.append(text)
            }
        }
        return pageTexts.joined(separator: "\n\n")
    }

    private func recognizeText(in image: NSImage) throws -> String {
        guard let cgImage = image.cgImageForVision else {
            throw NativeOCRError.unreadableImage
        }

        var observations: [VNRecognizedTextObservation] = []
        let request = VNRecognizeTextRequest { request, error in
            if error == nil {
                observations = request.results as? [VNRecognizedTextObservation] ?? []
            }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["pt-BR", "en-US"]

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            throw NativeOCRError.visionFailed
        }

        let lines = observations.compactMap { observation in
            observation.topCandidates(1).first?.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
        return lines.joined(separator: "\n")
    }

    private func isImage(fileURL: URL, mimeType: String?) -> Bool {
        let ext = fileURL.pathExtension.lowercased()
        return mimeType?.lowercased().hasPrefix("image/") == true
            || ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"].contains(ext)
    }

    private func isPDF(fileURL: URL, mimeType: String?) -> Bool {
        mimeType?.lowercased() == "application/pdf" || fileURL.pathExtension.lowercased() == "pdf"
    }
}

private extension NSImage {
    var cgImageForVision: CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
