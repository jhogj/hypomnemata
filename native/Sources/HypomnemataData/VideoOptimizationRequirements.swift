import Foundation

public enum VideoOptimizationRequirements {
    public static func missingDependencyMessage(doctor: DependencyDoctor = DependencyDoctor()) -> String? {
        let missing = ["ffmpeg", "ffprobe"].filter { executable in
            doctor.status(for: executable)?.isInstalled != true
        }
        guard !missing.isEmpty else {
            return nil
        }
        return "Instale ffmpeg via Homebrew para usar esta funcionalidade."
    }
}
