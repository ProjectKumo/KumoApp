import Darwin
import Foundation

public struct CoreLaunchConfiguration: Sendable {
    public var corePath: String?
    public var profile: Profile
    public var overrideYAMLs: [String]
    public var endpoint: ControllerEndpoint
    public var proxyPorts: ProxyPortConfiguration
    public var mode: OutboundMode
    public var runtimeSettings: CoreRuntimeSettings

    public init(
        corePath: String? = nil,
        profile: Profile,
        overrideYAMLs: [String] = [],
        endpoint: ControllerEndpoint = ControllerEndpoint(),
        proxyPorts: ProxyPortConfiguration = ProxyPortConfiguration(),
        mode: OutboundMode = .rule,
        runtimeSettings: CoreRuntimeSettings = CoreRuntimeSettings()
    ) {
        self.corePath = corePath
        self.profile = profile
        self.overrideYAMLs = overrideYAMLs
        self.endpoint = endpoint
        self.proxyPorts = proxyPorts
        self.mode = mode
        self.runtimeSettings = runtimeSettings
    }
}

public struct CoreSupervisor: Sendable {
    private let paths: KumoPaths
    private let stateStore: CoreStateStore

    public init(paths: KumoPaths = KumoPaths()) {
        self.paths = paths
        self.stateStore = CoreStateStore(paths: paths)
    }

    @discardableResult
    public func start(configuration: CoreLaunchConfiguration) throws -> CoreStatus {
        try paths.prepare()

        let currentStatus = try stateStore.load()
        if let pid = currentStatus.pid, isProcessAlive(pid) {
            throw KumoError.coreAlreadyRunning(pid)
        }

        let corePath = try resolveCorePath(configuration.corePath)
        try appendRuntimeEvent(kind: "core.starting", message: "Starting Mihomo core at \(corePath).")
        let runtime = try RuntimeConfigBuilder(
            endpoint: configuration.endpoint,
            proxyPorts: configuration.proxyPorts,
            mode: configuration.mode,
            runtimeSettings: configuration.runtimeSettings
        ).write(profile: configuration.profile, overrideYAMLs: configuration.overrideYAMLs, to: paths.runtimeConfigFile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: corePath)
        process.arguments = ["-d", paths.workDirectory.path]
        process.standardOutput = try logFileHandle()
        process.standardError = try logFileHandle()
        do {
            try process.run()
        } catch {
            var failedStatus = currentStatus
            failedStatus.state = .failed
            failedStatus.pid = nil
            failedStatus.readiness = nil
            failedStatus.message = "Failed to start Mihomo core: \(error.localizedDescription)"
            try stateStore.save(failedStatus)
            try appendRuntimeEvent(kind: "core.failed", message: failedStatus.message ?? "Failed to start Mihomo core.")
            throw error
        }

        let status = CoreStatus(
            state: .running,
            pid: Int32(process.processIdentifier),
            corePath: corePath,
            mode: configuration.mode,
            endpoint: runtime.endpoint,
            proxyPorts: runtime.proxyPorts,
            systemProxyEnabled: currentStatus.systemProxyEnabled,
            runtimeSettings: configuration.runtimeSettings,
            systemProxySettings: currentStatus.systemProxySettings,
            previousSystemProxySnapshot: currentStatus.previousSystemProxySnapshot,
            serviceModeStatus: currentStatus.serviceModeStatus,
            tunStatus: currentStatus.tunStatus,
            readiness: .processLaunched,
            message: "Mihomo core started."
        )
        try stateStore.save(status)
        try appendRuntimeEvent(kind: "core.started", message: "Mihomo core started with pid \(process.processIdentifier).")
        return status
    }

    @discardableResult
    public func stop() throws -> CoreStatus {
        var status = try stateStore.load()
        guard let pid = status.pid else {
            status.state = .stopped
            status.readiness = nil
            try stateStore.save(status)
            try appendRuntimeEvent(kind: "core.stopped", message: "Mihomo core was already stopped.")
            return status
        }

        if isProcessAlive(pid), !terminateProcess(pid) {
            status.state = .failed
            status.message = "Failed to stop Mihomo core with pid \(pid)."
            try stateStore.save(status)
            try appendRuntimeEvent(kind: "core.stop_failed", message: status.message ?? "Failed to stop Mihomo core.")
            return status
        }

        status.state = .stopped
        status.pid = nil
        status.readiness = nil
        status.message = "Mihomo core stopped."
        try stateStore.save(status)
        try appendRuntimeEvent(kind: "core.stopped", message: "Mihomo core stopped.")
        return status
    }

    public func status() throws -> CoreStatus {
        var status = try stateStore.load()
        if let pid = status.pid, !isProcessAlive(pid) {
            status.state = .stopped
            status.pid = nil
            status.readiness = nil
            status.message = "Mihomo core is not running."
            try stateStore.save(status)
            try appendRuntimeEvent(kind: "core.stale_pid", message: "Cleared stale Mihomo pid \(pid).")
        }
        return status
    }

    public func updateReadiness(_ readiness: CoreReadiness, message: String? = nil) throws -> CoreStatus {
        var status = try stateStore.load()
        status.readiness = readiness
        status.message = message ?? status.message
        try stateStore.save(status)
        try appendRuntimeEvent(kind: "core.readiness", message: message ?? "Core readiness changed to \(readiness.rawValue).")
        return status
    }

    public func recentRuntimeEvents(limit: Int = 200) throws -> [RuntimeEventEntry] {
        guard FileManager.default.fileExists(atPath: paths.runtimeEventsFile.path) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let content = try String(contentsOf: paths.runtimeEventsFile, encoding: .utf8)
        return content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(limit)
            .compactMap { line -> RuntimeEventEntry? in
                guard let data = String(line).data(using: .utf8) else {
                    return nil
                }
                return try? decoder.decode(RuntimeEventEntry.self, from: data)
            }
    }

    public func discoverCoreCandidates(configuredPath: String? = nil) -> [CoreCandidate] {
        let fileManager = FileManager.default
        let names = ["mihomo", "mihomo-alpha", "clash", "clash-meta"]
        var candidates: [CoreCandidate] = []
        var seen = Set<String>()

        func append(_ path: String?, source: String) {
            guard let path, !path.isEmpty else {
                return
            }
            guard fileManager.isExecutableFile(atPath: path), !seen.contains(path) else {
                return
            }
            seen.insert(path)
            candidates.append(
                CoreCandidate(
                    name: URL(fileURLWithPath: path).lastPathComponent,
                    path: path,
                    sourceDescription: source
                )
            )
        }

        append(configuredPath, source: "Selected")
        append(paths.managedCoreExecutable.path, source: "Managed")
        append(ProcessInfo.processInfo.environment["KUMO_MIHOMO_PATH"], source: "Environment")

        for name in names {
            append(Bundle.main.url(forResource: name, withExtension: nil)?.path, source: "Bundled")
        }

        for directory in searchDirectories() {
            for name in names {
                append(URL(fileURLWithPath: directory).appendingPathComponent(name).path, source: directory)
            }
            appendMatchingExecutables(in: directory, seen: &seen, candidates: &candidates)
        }

        return candidates
    }

    private func resolveCorePath(_ configuredPath: String?) throws -> String {
        if let candidate = discoverCoreCandidates(configuredPath: configuredPath).first {
            return candidate.path
        }

        throw KumoError.coreNotFound(configuredPath ?? "mihomo")
    }

    private func isProcessAlive(_ pid: Int32) -> Bool {
        Darwin.kill(pid, 0) == 0
    }

    private func terminateProcess(_ pid: Int32) -> Bool {
        let steps: [(signal: Int32, timeout: TimeInterval)] = [
            (SIGINT, 1.0),
            (SIGTERM, 2.0),
            (SIGKILL, 1.0)
        ]

        for step in steps {
            Darwin.kill(pid, step.signal)
            if waitForExit(pid, timeout: step.timeout) {
                return true
            }
        }

        return !isProcessAlive(pid)
    }

    private func waitForExit(_ pid: Int32, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isProcessAlive(pid) {
                return true
            }
            usleep(100_000)
        }
        return !isProcessAlive(pid)
    }

    private func logFileHandle() throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: paths.coreLogFile.path) {
            FileManager.default.createFile(atPath: paths.coreLogFile.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: paths.coreLogFile)
        try handle.seekToEnd()
        return handle
    }

    private func appendRuntimeEvent(kind: String, message: String) throws {
        try FileManager.default.createDirectory(at: paths.logsDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(RuntimeEventEntry(kind: kind, message: message))
        var line = data
        line.append(0x0A)

        if !FileManager.default.fileExists(atPath: paths.runtimeEventsFile.path) {
            FileManager.default.createFile(atPath: paths.runtimeEventsFile.path, contents: nil)
        }

        let handle = try FileHandle(forWritingTo: paths.runtimeEventsFile)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
    }

    private func searchDirectories() -> [String] {
        let pathDirectories = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let commonDirectories = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "\(home)/.local/bin",
            "\(home)/bin"
        ]

        return Array(Set(pathDirectories + commonDirectories)).sorted()
    }

    private func appendMatchingExecutables(
        in directory: String,
        seen: inout Set<String>,
        candidates: inout [CoreCandidate]
    ) {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return
        }

        for file in files where file.hasPrefix("mihomo") || file.hasPrefix("clash") {
            let path = URL(fileURLWithPath: directory).appendingPathComponent(file).path
            guard FileManager.default.isExecutableFile(atPath: path), !seen.contains(path) else {
                continue
            }
            seen.insert(path)
            candidates.append(CoreCandidate(name: file, path: path, sourceDescription: directory))
        }
    }
}
