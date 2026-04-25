import Foundation

public enum KindInference {
    private static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic"]
    private static let videoExtensions: Set<String> = ["mp4", "webm", "mkv", "mov", "m4v", "avi"]

    public static func infer(urlString: String?, filename: String? = nil, explicitKind: ItemKind? = nil) -> ItemKind {
        if let explicitKind {
            return explicitKind
        }

        if let urlString, let url = URL(string: urlString), let host = url.host()?.lowercased() {
            if host == "x.com" || host == "www.x.com" || host == "twitter.com" || host == "www.twitter.com" {
                return .tweet
            }
            if isVideoPlatform(host: host, path: url.path) {
                return .video
            }
            if let kind = inferFromPath(url.path) {
                return kind
            }
            return .article
        }

        if let filename, let kind = inferFromPath(filename) {
            return kind
        }

        return .note
    }

    private static func isVideoPlatform(host: String, path: String) -> Bool {
        if host == "youtu.be" || host == "www.youtu.be" {
            return true
        }
        if host == "youtube.com" || host == "www.youtube.com" {
            return path.hasPrefix("/watch")
                || path.hasPrefix("/shorts")
                || path.hasPrefix("/live")
                || path.hasPrefix("/embed")
        }
        if host == "vimeo.com" || host == "www.vimeo.com" {
            return path.split(separator: "/").first?.allSatisfy(\.isNumber) == true
        }
        return false
    }

    private static func inferFromPath(_ path: String) -> ItemKind? {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        if imageExtensions.contains(ext) {
            return .image
        }
        if videoExtensions.contains(ext) {
            return .video
        }
        if ext == "pdf" {
            return .pdf
        }
        return nil
    }
}
