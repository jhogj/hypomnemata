import Foundation
import HypomnemataCore

public struct DependencyRequirement: Identifiable, Equatable, Sendable {
    public var id: String { executable }
    public var executable: String
    public var purpose: String
    public var installCommand: String

    public init(executable: String, purpose: String, installCommand: String) {
        self.executable = executable
        self.purpose = purpose
        self.installCommand = installCommand
    }
}

public struct DependencyStatus: Identifiable, Equatable, Sendable {
    public var id: String { requirement.executable }
    public var requirement: DependencyRequirement
    public var path: String?

    public var isInstalled: Bool {
        path != nil
    }

    public init(requirement: DependencyRequirement, path: String?) {
        self.requirement = requirement
        self.path = path
    }
}

public struct DependencyDoctor: Sendable {
    public static let productionRequirements: [DependencyRequirement] = [
        DependencyRequirement(
            executable: "sqlcipher",
            purpose: "Criptografia real do vault SQLite",
            installCommand: "brew install sqlcipher"
        ),
        DependencyRequirement(
            executable: "ffmpeg",
            purpose: "Merge de streams de vídeo e geração de thumbnails",
            installCommand: "brew install ffmpeg"
        ),
        DependencyRequirement(
            executable: "yt-dlp",
            purpose: "Download de YouTube, Vimeo e tweets com vídeo",
            installCommand: "brew install yt-dlp"
        ),
        DependencyRequirement(
            executable: "gallery-dl",
            purpose: "Download de galerias de fotos de tweets",
            installCommand: "brew install gallery-dl"
        ),
        DependencyRequirement(
            executable: "trafilatura",
            purpose: "Extração de texto e metadados de artigos",
            installCommand: "brew install trafilatura"
        ),
    ]

    private let requirements: [DependencyRequirement]
    private let environment: [String: String]

    public init(
        requirements: [DependencyRequirement] = Self.productionRequirements,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.requirements = requirements
        self.environment = environment
    }

    public func check() -> [DependencyStatus] {
        requirements.map { requirement in
            DependencyStatus(
                requirement: requirement,
                path: locate(executable: requirement.executable)
            )
        }
    }

    public func status(for executable: String) -> DependencyStatus? {
        guard let requirement = requirements.first(where: { $0.executable == executable }) else {
            return nil
        }
        return DependencyStatus(
            requirement: requirement,
            path: locate(executable: requirement.executable)
        )
    }

    private func locate(executable: String) -> String? {
        let pathValue = environment["PATH"] ?? "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        for directory in pathValue.split(separator: ":").map(String.init) {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executable).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }
}

public struct JobDependencyResolver: Sendable {
    private let doctor: DependencyDoctor

    public init(doctor: DependencyDoctor = DependencyDoctor()) {
        self.doctor = doctor
    }

    public func missingDependencyError(for kind: JobKind) -> String? {
        let executables = requiredExecutables(for: kind)
        let missing = executables.compactMap { executable -> DependencyStatus? in
            guard let status = doctor.status(for: executable), !status.isInstalled else {
                return nil
            }
            return status
        }
        guard !missing.isEmpty else {
            return nil
        }
        return missing
            .map { "Dependência ausente: \($0.requirement.executable). Rode `\($0.requirement.installCommand)`." }
            .joined(separator: " ")
    }

    private func requiredExecutables(for kind: JobKind) -> [String] {
        switch kind {
        case .scrapeArticle:
            ["trafilatura"]
        case .downloadMedia:
            ["yt-dlp", "ffmpeg"]
        case .generateThumbnail:
            ["ffmpeg"]
        case .runOCR, .summarize, .autotag:
            []
        }
    }
}
