import Darwin
import Foundation

public struct CoreLaunchConfiguration: Sendable {
    public var corePath: String?
    public var profile: Profile
    public var endpoint: ControllerEndpoint
    public var proxyPorts: ProxyPortConfiguration
    public var mode: OutboundMode

    public init(
        corePath: String? = nil,
        profile: Profile,
        endpoint: ControllerEndpoint = ControllerEndpoint(),
        proxyPorts: ProxyPortConfiguration = ProxyPortConfiguration(),
        mode: OutboundMode = .rule
    ) {
        self.corePath = corePath
        self.profile = profile
        self.endpoint = endpoint
        self.proxyPorts = proxyPorts
        self.mode = mode
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
        let runtime = try RuntimeConfigBuilder(
            endpoint: configuration.endpoint,
            proxyPorts: configuration.proxyPorts,
            mode: configuration.mode
        ).write(profile: configuration.profile, to: paths.runtimeConfigFile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: corePath)
        process.arguments = ["-d", paths.workDirectory.path]
        process.standardOutput = try logFileHandle()
        process.standardError = try logFileHandle()
        try process.run()

        let status = CoreStatus(
            state: .running,
            pid: Int32(process.processIdentifier),
            corePath: corePath,
            mode: configuration.mode,
            endpoint: runtime.endpoint,
            proxyPorts: runtime.proxyPorts,
            systemProxyEnabled: currentStatus.systemProxyEnabled,
            message: "Mihomo core started."
        )
        try stateStore.save(status)
        return status
    }

    @discardableResult
    public func stop() throws -> CoreStatus {
        var status = try stateStore.load()
        guard let pid = status.pid else {
            status.state = .stopped
            try stateStore.save(status)
            return status
        }

        if isProcessAlive(pid) {
            Darwin.kill(pid, SIGTERM)
        }

        status.state = .stopped
        status.pid = nil
        status.message = "Mihomo core stopped."
        try stateStore.save(status)
        return status
    }

    public func status() throws -> CoreStatus {
        var status = try stateStore.load()
        if let pid = status.pid, !isProcessAlive(pid) {
            status.state = .stopped
            status.pid = nil
            status.message = "Mihomo core is not running."
            try stateStore.save(status)
        }
        return status
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

    private func logFileHandle() throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: paths.coreLogFile.path) {
            FileManager.default.createFile(atPath: paths.coreLogFile.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: paths.coreLogFile)
        try handle.seekToEnd()
        return handle
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
