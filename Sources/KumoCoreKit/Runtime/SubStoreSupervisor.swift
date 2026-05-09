import Foundation

/// Manages the lifecycle of the local Sub-Store backend process. The
/// supervisor is `actor`-isolated because `Process` is not Sendable; callers
/// must `await` start/stop and accessors. Logs are appended to
/// `KumoPaths.subStoreLogFile` so users can tail/inspect the same way they do
/// with the Mihomo core log.
public actor SubStoreSupervisor {
    private let paths: KumoPaths
    private var process: Process?
    private var logHandle: FileHandle?

    public init(paths: KumoPaths = KumoPaths()) {
        self.paths = paths
    }

    /// True if the supervised process is alive.
    public var isRunning: Bool {
        guard let process else { return false }
        return process.isRunning
    }

    /// Process identifier of the running backend, or `nil` when stopped.
    public var pid: Int32? {
        process?.processIdentifier
    }

    /// Start the supervised process described by `plan`. If `plan` has no
    /// backend command (e.g. user enabled custom-backend mode) this is a
    /// no-op. Calling start while already running is also a no-op.
    public func start(plan: SubStoreLaunchPlan) throws {
        guard let command = plan.backendCommand else {
            return
        }

        if let process, process.isRunning {
            return
        }

        try paths.prepare()
        let handle = try makeLogHandle()
        try writeLogHeader(to: handle, command: command)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments
        process.standardOutput = handle
        process.standardError = handle
        try process.run()

        self.process = process
        self.logHandle = handle
    }

    /// Restart the supervised process with `plan`. Useful when the underlying
    /// configuration (port, paths) changes without disabling Sub-Store first.
    public func restart(plan: SubStoreLaunchPlan) throws {
        stop()
        try start(plan: plan)
    }

    /// Stop the supervised process if it is running.
    public func stop() {
        if let process, process.isRunning {
            process.terminate()
            process.waitUntilExit()
        }
        process = nil
        try? logHandle?.close()
        logHandle = nil
    }

    private func makeLogHandle() throws -> FileHandle {
        let url = paths.subStoreLogFile
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        return handle
    }

    private func writeLogHeader(to handle: FileHandle, command: ShellCommand) throws {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let header = "[\(timestamp)] starting \(command.executable) \(command.arguments.joined(separator: " "))\n"
        if let data = header.data(using: .utf8) {
            try handle.write(contentsOf: data)
        }
    }
}
