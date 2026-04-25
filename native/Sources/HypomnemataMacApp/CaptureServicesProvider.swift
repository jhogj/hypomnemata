import AppKit
import Foundation

@MainActor
final class CaptureServicesProvider: NSObject {
    weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
    }

    @objc(captureSelection:userData:error:)
    func captureSelection(
        _ pasteboard: NSPasteboard,
        userData: String?,
        error: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let value = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string) else {
            error.pointee = "Nenhum texto ou URL disponível para capturar." as NSString
            return
        }

        guard let model else {
            error.pointee = "Hypomnemata não está pronto para receber capturas." as NSString
            return
        }

        let didOpen: Bool
        if let url = URL(string: value), url.scheme == "http" || url.scheme == "https" || url.scheme == "hypomnemata" {
            didOpen = model.openExternalCapture(url)
        } else {
            didOpen = model.openExternalCaptureText(value)
        }

        if !didOpen {
            error.pointee = "Desbloqueie o vault antes de receber uma captura externa." as NSString
        }
    }
}
