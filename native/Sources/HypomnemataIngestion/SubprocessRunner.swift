import Foundation

public struct SubprocessResult: Sendable, Equatable {
    public var exitCode: Int32
    public var stdout: Data
    public var stderr: Data

    public init(exitCode: Int32, stdout: Data, stderr: Data) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public enum SubprocessRunnerError: LocalizedError, Equatable, Sendable {
    case executableNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .executableNotFound(executable):
            "Executável não encontrado no PATH: \(executable)."
        }
    }
}

public struct SubprocessRunner: Sendable {
    private static let defaultSearchDirectories = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL? = nil,
        standardInput: Data? = nil
    ) throws -> SubprocessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try resolve(executable: executable))
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory
        process.environment = processEnvironment()

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let inputPipe: Pipe?
        if standardInput != nil {
            let pipe = Pipe()
            process.standardInput = pipe
            inputPipe = pipe
        } else {
            inputPipe = nil
        }

        try process.run()

        let group = DispatchGroup()
        let queue = DispatchQueue(label: "hypomnemata.subprocess.io", attributes: .concurrent)
        let stdoutBox = LockedDataBox()
        let stderrBox = LockedDataBox()

        group.enter()
        queue.async {
            stdoutBox.set(stdoutPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        group.enter()
        queue.async {
            stderrBox.set(stderrPipe.fileHandleForReading.readDataToEndOfFile())
            group.leave()
        }

        if let standardInput, let inputPipe {
            group.enter()
            queue.async {
                try? inputPipe.fileHandleForWriting.write(contentsOf: standardInput)
                try? inputPipe.fileHandleForWriting.close()
                group.leave()
            }
        }

        process.waitUntilExit()
        group.wait()

        return SubprocessResult(
            exitCode: process.terminationStatus,
            stdout: stdoutBox.data(),
            stderr: stderrBox.data()
        )
    }

    public func resolve(executable: String) throws -> String {
        if executable.contains("/") {
            guard FileManager.default.isExecutableFile(atPath: executable) else {
                throw SubprocessRunnerError.executableNotFound(executable)
            }
            return executable
        }

        for directory in searchDirectories() {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent(executable).path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw SubprocessRunnerError.executableNotFound(executable)
    }

    private func processEnvironment() -> [String: String] {
        var values = ProcessInfo.processInfo.environment
        for (key, value) in environment {
            values[key] = value
        }
        values["PATH"] = searchDirectories().joined(separator: ":")
        return values
    }

    private func searchDirectories() -> [String] {
        var directories = (environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        directories.append(contentsOf: Self.defaultSearchDirectories)

        var seen = Set<String>()
        return directories.filter { directory in
            guard !directory.isEmpty, !seen.contains(directory) else {
                return false
            }
            seen.insert(directory)
            return true
        }
    }
}

final class LockedDataBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Data()

    func set(_ data: Data) {
        lock.lock()
        value = data
        lock.unlock()
    }

    func data() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
