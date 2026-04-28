import Foundation

public struct VideoOptimizationResult: Sendable, Equatable {
    public var outputBytes: Int64
    public var durationSeconds: Double

    public init(outputBytes: Int64, durationSeconds: Double) {
        self.outputBytes = outputBytes
        self.durationSeconds = durationSeconds
    }
}

public struct VideoOptimizationProgress: Sendable, Equatable {
    public var percent: Double
    public var framesProcessed: Int?
    public var fps: Double?
    public var speed: Double?
    public var outTimeSeconds: Double?

    public init(
        percent: Double,
        framesProcessed: Int? = nil,
        fps: Double? = nil,
        speed: Double? = nil,
        outTimeSeconds: Double? = nil
    ) {
        self.percent = min(max(percent, 0), 1)
        self.framesProcessed = framesProcessed
        self.fps = fps
        self.speed = speed
        self.outTimeSeconds = outTimeSeconds
    }
}

public enum VideoOptimizationError: LocalizedError, Equatable, Sendable {
    case binaryNotFound(String)
    case inputNotFound(String)
    case ffprobeFailed(exitCode: Int32, stderr: String)
    case ffmpegFailed(exitCode: Int32, stderr: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .binaryNotFound(executable):
            "Executável não encontrado no PATH: \(executable)."
        case let .inputNotFound(path):
            "Arquivo de entrada não encontrado: \(path)."
        case let .ffprobeFailed(code, stderr):
            "ffprobe falhou (exit \(code)): \(stderr)"
        case let .ffmpegFailed(code, stderr):
            "ffmpeg falhou (exit \(code)): \(stderr)"
        case .cancelled:
            "Otimização de vídeo cancelada."
        }
    }
}

public protocol VideoOptimizer: Sendable {
    func optimize(
        input: URL,
        output: URL,
        progress: @Sendable @escaping (VideoOptimizationProgress) -> Void,
        isCancelled: @Sendable @escaping () -> Bool
    ) async throws -> VideoOptimizationResult
}

public extension VideoOptimizer {
    func optimize(
        input: URL,
        output: URL,
        progress: @Sendable @escaping (Double) -> Void,
        isCancelled: @Sendable @escaping () -> Bool
    ) async throws -> VideoOptimizationResult {
        try await optimize(
            input: input,
            output: output,
            progress: { progress($0.percent) },
            isCancelled: isCancelled
        )
    }

    func optimize(
        input: URL,
        output: URL,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> VideoOptimizationResult {
        try await optimize(input: input, output: output, progress: progress, isCancelled: { false })
    }
}

public struct FFmpegVideoOptimizer: VideoOptimizer {
    private static let maxWidth = 1280
    private static let maxFps = 30
    private static let videoQuality = 50
    private static let audioBitrate = "96k"
    private static let fallbackCRF = "28"

    private let ffmpegPath: String
    private let ffprobePath: String
    private let environment: [String: String]
    private let hasVideoToolboxHEVC: Bool

    public init(
        ffmpegPath: String = "ffmpeg",
        ffprobePath: String = "ffprobe",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        hasVideoToolboxHEVC: Bool? = nil
    ) {
        self.ffmpegPath = ffmpegPath
        self.ffprobePath = ffprobePath
        self.environment = environment
        self.hasVideoToolboxHEVC = hasVideoToolboxHEVC ?? Self.detectVideoToolboxHEVC(
            ffmpegPath: ffmpegPath,
            environment: environment
        )
    }

    public func optimize(
        input: URL,
        output: URL,
        progress: @Sendable @escaping (VideoOptimizationProgress) -> Void,
        isCancelled: @Sendable @escaping () -> Bool
    ) async throws -> VideoOptimizationResult {
        guard FileManager.default.fileExists(atPath: input.path) else {
            throw VideoOptimizationError.inputNotFound(input.path)
        }
        if isCancelled() {
            throw VideoOptimizationError.cancelled
        }

        let duration = try probeDuration(input: input)
        try await runFFmpeg(input: input, output: output, durationSeconds: duration, progress: progress, isCancelled: isCancelled)

        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let bytes = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        return VideoOptimizationResult(outputBytes: bytes, durationSeconds: duration)
    }

    private func probeDuration(input: URL) throws -> Double {
        let runner = SubprocessRunner(environment: environment)
        let result: SubprocessResult
        do {
            result = try runner.run(
                executable: ffprobePath,
                arguments: [
                    "-v", "error",
                    "-show_entries", "format=duration",
                    "-of", "csv=p=0",
                    input.path,
                ]
            )
        } catch SubprocessRunnerError.executableNotFound {
            throw VideoOptimizationError.binaryNotFound(ffprobePath)
        }

        guard result.exitCode == 0 else {
            throw VideoOptimizationError.ffprobeFailed(
                exitCode: result.exitCode,
                stderr: Self.trimmedText(result.stderr)
            )
        }

        let text = Self.trimmedText(result.stdout)
        guard let duration = Double(text), duration > 0 else {
            throw VideoOptimizationError.ffprobeFailed(
                exitCode: result.exitCode,
                stderr: "Duração inválida: \(text)"
            )
        }
        return duration
    }

    private func runFFmpeg(
        input: URL,
        output: URL,
        durationSeconds: Double,
        progress: @Sendable @escaping (VideoOptimizationProgress) -> Void,
        isCancelled: @Sendable @escaping () -> Bool
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                do {
                    try self.runFFmpegBlocking(
                        input: input,
                        output: output,
                        durationSeconds: durationSeconds,
                        progress: progress,
                        isCancelled: isCancelled
                    )
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runFFmpegBlocking(
        input: URL,
        output: URL,
        durationSeconds: Double,
        progress: @Sendable @escaping (VideoOptimizationProgress) -> Void,
        isCancelled: @Sendable @escaping () -> Bool
    ) throws {
        let runner = SubprocessRunner(environment: environment)
        let resolvedFFmpeg: String
        do {
            resolvedFFmpeg = try runner.resolve(executable: ffmpegPath)
        } catch SubprocessRunnerError.executableNotFound {
            throw VideoOptimizationError.binaryNotFound(ffmpegPath)
        }
        let resolvedFFprobe = try? runner.resolve(executable: ffprobePath)

        let processEnvironment = processEnvironment(
            resolvedFFmpeg: resolvedFFmpeg,
            resolvedFFprobe: resolvedFFprobe
        )

        try runFFmpegProcess(
            resolvedFFmpeg: resolvedFFmpeg,
            arguments: Self.ffmpegArguments(input: input, output: output, useVideoToolbox: hasVideoToolboxHEVC),
            environment: processEnvironment,
            output: output,
            durationSeconds: durationSeconds,
            progress: progress,
            isCancelled: isCancelled
        )
    }

    private func runFFmpegProcess(
        resolvedFFmpeg: String,
        arguments: [String],
        environment: [String: String],
        output: URL,
        durationSeconds: Double,
        progress: @Sendable @escaping (VideoOptimizationProgress) -> Void,
        isCancelled: @Sendable @escaping () -> Bool
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedFFmpeg)
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "hypomnemata.video-optimizer.io", attributes: .concurrent)
        let stderrBox = LockedDataBox()
        let cancelBox = LockedBoolBox()

        try process.run()
        let cancelTimer = DispatchSource.makeTimerSource(queue: queue)
        cancelTimer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        cancelTimer.setEventHandler {
            if isCancelled() {
                cancelBox.set(true)
                if process.isRunning {
                    process.terminate()
                }
            }
        }
        cancelTimer.resume()

        group.enter()
        queue.async {
            Self.readProgress(
                from: stdoutPipe.fileHandleForReading,
                durationSeconds: durationSeconds,
                progress: progress,
                isCancelled: isCancelled,
                cancel: {
                    cancelBox.set(true)
                    if process.isRunning {
                        process.terminate()
                    }
                }
            )
            group.leave()
        }

        group.enter()
        queue.async {
            stderrBox.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        process.waitUntilExit()
        cancelTimer.cancel()
        group.wait()

        let wasCancelled = cancelBox.value()
        if process.terminationStatus == 0, !wasCancelled {
            progress(VideoOptimizationProgress(percent: 1))
            return
        }

        if wasCancelled {
            try? FileManager.default.removeItem(at: output)
            throw VideoOptimizationError.cancelled
        }

        throw VideoOptimizationError.ffmpegFailed(
            exitCode: process.terminationStatus,
            stderr: Self.trimmedText(stderrBox.data())
        )
    }

    private static func ffmpegArguments(input: URL, output: URL, useVideoToolbox: Bool) -> [String] {
        let videoFilter = "scale='min(\(maxWidth),iw)':'-2':flags=lanczos,fps=fps='min(\(maxFps),source_fps)'"
        var arguments = [
            "-i", input.path,
            "-nostdin",
            "-vf", videoFilter,
            "-c:v", useVideoToolbox ? "hevc_videotoolbox" : "libx265",
            "-tag:v", "hvc1",
        ]
        if useVideoToolbox {
            arguments.append(contentsOf: ["-q:v", String(videoQuality)])
        } else {
            arguments.append(contentsOf: ["-crf", fallbackCRF, "-preset", "medium"])
        }
        arguments.append(contentsOf: [
            "-c:a", "aac",
            "-b:a", audioBitrate,
            "-ac", "2",
            "-movflags", "+faststart",
            "-progress", "pipe:1",
            "-nostats",
            "-y",
            output.path,
        ])
        return arguments
    }

    private static func detectVideoToolboxHEVC(ffmpegPath: String, environment: [String: String]) -> Bool {
        let runner = SubprocessRunner(environment: environment)
        guard let result = try? runner.run(
            executable: ffmpegPath,
            arguments: ["-hide_banner", "-encoders"]
        ), result.exitCode == 0 else {
            return false
        }
        let output = [
            String(data: result.stdout, encoding: .utf8),
            String(data: result.stderr, encoding: .utf8),
        ].compactMap { $0 }.joined(separator: "\n")
        return output.contains("hevc_videotoolbox")
    }

    private func processEnvironment(resolvedFFmpeg: String, resolvedFFprobe: String?) -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            values[key] = value
        }
        let path = values["PATH"] ?? ""
        let directories = [
            URL(fileURLWithPath: resolvedFFmpeg).deletingLastPathComponent().path,
            resolvedFFprobe.map { URL(fileURLWithPath: $0).deletingLastPathComponent().path },
            path,
        ].compactMap { $0 }.filter { !$0.isEmpty }
        values["PATH"] = directories.joined(separator: ":")
        return values
    }

    private static func readProgress(
        from handle: FileHandle,
        durationSeconds: Double,
        progress: @Sendable (VideoOptimizationProgress) -> Void,
        isCancelled: @Sendable () -> Bool,
        cancel: () -> Void
    ) {
        var buffer = Data()
        var state = FFmpegProgressState()
        while true {
            let chunk = handle.availableData
            if chunk.isEmpty {
                break
            }
            buffer.append(chunk)
            while let newline = buffer.firstIndex(of: 0x0A) {
                let lineData = buffer[..<newline]
                buffer.removeSubrange(...newline)
                handleProgressLine(
                    String(decoding: lineData, as: UTF8.self),
                    durationSeconds: durationSeconds,
                    state: &state,
                    progress: progress,
                    isCancelled: isCancelled,
                    cancel: cancel
                )
            }
        }
        if !buffer.isEmpty {
            handleProgressLine(
                String(decoding: buffer, as: UTF8.self),
                durationSeconds: durationSeconds,
                state: &state,
                progress: progress,
                isCancelled: isCancelled,
                cancel: cancel
            )
        }
    }

    private static func handleProgressLine(
        _ line: String,
        durationSeconds: Double,
        state: inout FFmpegProgressState,
        progress: @Sendable (VideoOptimizationProgress) -> Void,
        isCancelled: @Sendable () -> Bool,
        cancel: () -> Void
    ) {
        if isCancelled() {
            cancel()
            return
        }

        let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            return
        }
        let key = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let rawValue = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)

        switch key {
        case "frame":
            state.framesProcessed = Int(rawValue.trimmingCharacters(in: .whitespaces))
        case "fps":
            state.fps = Double(rawValue)
        case "speed":
            state.speed = Self.parseSpeed(rawValue)
        case "progress" where rawValue == "end":
            progress(VideoOptimizationProgress(
                percent: 1,
                framesProcessed: state.framesProcessed,
                fps: state.fps,
                speed: state.speed,
                outTimeSeconds: state.outTimeSeconds
            ))
        case "out_time_us", "out_time_ms":
            guard let microseconds = Double(rawValue) else {
                break
            }
            emitProgress(
                outTimeSeconds: microseconds / 1_000_000,
                durationSeconds: durationSeconds,
                state: &state,
                progress: progress
            )
        case "out_time":
            guard let seconds = parseOutTimeSeconds(rawValue) else {
                break
            }
            emitProgress(
                outTimeSeconds: seconds,
                durationSeconds: durationSeconds,
                state: &state,
                progress: progress
            )
        default:
            break
        }

        if isCancelled() {
            cancel()
        }
    }

    private static func emitProgress(
        outTimeSeconds: Double,
        durationSeconds: Double,
        state: inout FFmpegProgressState,
        progress: @Sendable (VideoOptimizationProgress) -> Void
    ) {
        state.outTimeSeconds = outTimeSeconds
        let percent = min(max(outTimeSeconds / durationSeconds, 0), 1)
        progress(VideoOptimizationProgress(
            percent: percent,
            framesProcessed: state.framesProcessed,
            fps: state.fps,
            speed: state.speed,
            outTimeSeconds: outTimeSeconds
        ))
    }

    private static func parseOutTimeSeconds(_ value: String) -> Double? {
        let components = value.split(separator: ":", omittingEmptySubsequences: false)
        guard components.count == 3,
              let hours = Double(components[0]),
              let minutes = Double(components[1])
        else {
            return nil
        }
        let secondsText = components[2].replacingOccurrences(of: ",", with: ".")
        guard let seconds = Double(secondsText) else {
            return nil
        }
        return (hours * 3600) + (minutes * 60) + seconds
    }

    private static func parseSpeed(_ value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutSuffix = trimmed.hasSuffix("x") ? String(trimmed.dropLast()) : trimmed
        return Double(withoutSuffix)
    }

    private static func trimmedText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct FFmpegProgressState {
    var framesProcessed: Int?
    var fps: Double?
    var speed: Double?
    var outTimeSeconds: Double?
}

private final class LockedBoolBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue = false

    func set(_ value: Bool) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    func value() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }
}
