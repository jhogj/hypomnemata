import Foundation

public struct VideoOptimizationResult: Sendable, Equatable {
    public var outputBytes: Int64
    public var durationSeconds: Double

    public init(outputBytes: Int64, durationSeconds: Double) {
        self.outputBytes = outputBytes
        self.durationSeconds = durationSeconds
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
        progress: @Sendable @escaping (Double) -> Void,
        isCancelled: @Sendable @escaping () -> Bool
    ) async throws -> VideoOptimizationResult
}

public extension VideoOptimizer {
    func optimize(
        input: URL,
        output: URL,
        progress: @Sendable @escaping (Double) -> Void = { _ in }
    ) async throws -> VideoOptimizationResult {
        try await optimize(input: input, output: output, progress: progress, isCancelled: { false })
    }
}

public struct FFmpegVideoOptimizer: VideoOptimizer {
    private let ffmpegPath: String
    private let ffprobePath: String
    private let environment: [String: String]

    public init(
        ffmpegPath: String = "ffmpeg",
        ffprobePath: String = "ffprobe",
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.ffmpegPath = ffmpegPath
        self.ffprobePath = ffprobePath
        self.environment = environment
    }

    public func optimize(
        input: URL,
        output: URL,
        progress: @Sendable @escaping (Double) -> Void,
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
        progress: @Sendable @escaping (Double) -> Void,
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
        progress: @Sendable @escaping (Double) -> Void,
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: resolvedFFmpeg)
        process.arguments = [
            "-i", input.path,
            "-vcodec", "libx264",
            "-crf", "28",
            "-preset", "slow",
            "-c:a", "aac",
            "-b:a", "128k",
            "-progress", "pipe:1",
            "-nostats",
            "-y",
            output.path,
        ]
        process.environment = processEnvironment(
            resolvedFFmpeg: resolvedFFmpeg,
            resolvedFFprobe: resolvedFFprobe
        )

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
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
            progress(1)
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
        progress: @Sendable (Double) -> Void,
        isCancelled: @Sendable () -> Bool,
        cancel: () -> Void
    ) {
        var buffer = Data()
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
                progress: progress,
                isCancelled: isCancelled,
                cancel: cancel
            )
        }
    }

    private static func handleProgressLine(
        _ line: String,
        durationSeconds: Double,
        progress: @Sendable (Double) -> Void,
        isCancelled: @Sendable () -> Bool,
        cancel: () -> Void
    ) {
        if isCancelled() {
            cancel()
            return
        }
        guard line.hasPrefix("out_time_ms=") else {
            return
        }
        let rawValue = line.dropFirst("out_time_ms=".count)
        guard let microseconds = Double(rawValue) else {
            return
        }
        let percent = min(max((microseconds / 1_000_000) / durationSeconds, 0), 1)
        progress(percent)
        if isCancelled() {
            cancel()
        }
    }

    private static func trimmedText(_ data: Data) -> String {
        String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
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
