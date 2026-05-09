import Foundation

public struct KumoController: Sendable {
    public let paths: KumoPaths
    private let profileRepository: ProfileRepository
    private let supervisor: CoreSupervisor
    private let stateStore: CoreStateStore
    private let systemProxyController: SystemProxyController
    private let coreInstaller: CoreInstaller

    public init(paths: KumoPaths = KumoPaths()) {
        self.paths = paths
        self.profileRepository = ProfileRepository(paths: paths)
        self.supervisor = CoreSupervisor(paths: paths)
        self.stateStore = CoreStateStore(paths: paths)
        self.systemProxyController = SystemProxyController(paths: paths)
        self.coreInstaller = CoreInstaller(paths: paths)
    }

    public func status() throws -> CoreStatus {
        try supervisor.status()
    }

    public func currentProfile() throws -> ProfileSummary {
        try profileRepository.currentProfileSummary()
    }

    public func profiles() throws -> [ProfileSummary] {
        try profileRepository.listProfiles()
    }

    public func setCurrentProfile(id: String) throws {
        try profileRepository.setCurrentProfile(id: id)
    }

    public func coreCandidates() throws -> [CoreCandidate] {
        let status = try stateStore.load()
        return supervisor.discoverCoreCandidates(configuredPath: status.corePath)
    }

    public func setCorePath(_ path: String) throws {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw KumoError.coreNotFound(path)
        }

        var status = try stateStore.load()
        status.corePath = path
        try stateStore.save(status)
    }

    @discardableResult
    public func installManagedCore() async throws -> CoreInstallResult {
        let result = try await coreInstaller.installLatestMihomo()
        try setCorePath(result.path)
        return result
    }

    @discardableResult
    public func start(corePath: String? = nil) throws -> CoreStatus {
        let currentStatus = try stateStore.load()
        let profile = try profileRepository.loadDefaultProfile()
        return try supervisor.start(
            configuration: CoreLaunchConfiguration(
                corePath: corePath ?? currentStatus.corePath,
                profile: profile,
                endpoint: currentStatus.endpoint,
                proxyPorts: currentStatus.proxyPorts,
                mode: currentStatus.mode
            )
        )
    }

    @discardableResult
    public func stop() throws -> CoreStatus {
        try supervisor.stop()
    }

    public func restart(corePath: String? = nil) throws -> CoreStatus {
        _ = try stop()
        return try start(corePath: corePath)
    }

    public func setMode(_ mode: OutboundMode) async throws {
        var status = try stateStore.load()
        status.mode = mode
        try stateStore.save(status)

        if status.state == .running {
            try await MihomoControllerClient(endpoint: status.endpoint).setMode(mode)
        }
    }

    public func proxyGroups() async throws -> [ProxyGroup] {
        let status = try stateStore.load()
        return try await MihomoControllerClient(endpoint: status.endpoint).proxyGroups()
    }

    public func coreConfiguration() async throws -> CoreConfigurationSnapshot {
        let status = try stateStore.load()
        return try await MihomoControllerClient(endpoint: status.endpoint).configuration()
    }

    public func waitForControllerReady(maxAttempts: Int = 30, intervalNanoseconds: UInt64 = 200_000_000) async throws {
        let status = try stateStore.load()
        let client = MihomoControllerClient(endpoint: status.endpoint)
        var lastError: Error?

        for _ in 0..<maxAttempts {
            do {
                _ = try await client.version()
                return
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: intervalNanoseconds)
            }
        }

        throw lastError ?? KumoError.coreNotRunning
    }

    public func rules() async throws -> [RuleEntry] {
        let status = try stateStore.load()
        return try await MihomoControllerClient(endpoint: status.endpoint).rules()
    }

    public func connections() async throws -> [ConnectionEntry] {
        let status = try stateStore.load()
        return try await MihomoControllerClient(endpoint: status.endpoint).connections()
    }

    public func selectProxy(group: String, name: String) async throws {
        let status = try stateStore.load()
        try await MihomoControllerClient(endpoint: status.endpoint).selectProxy(group: group, name: name)
    }

    public func testProxyDelay(proxy: String, testURL: String? = nil) async throws -> Int? {
        let status = try stateStore.load()
        return try await MihomoControllerClient(endpoint: status.endpoint).proxyDelay(proxy: proxy, testURL: testURL)
    }

    public func testGroupDelay(group: ProxyGroup) async throws -> [ProxyNode] {
        let status = try stateStore.load()
        return try await MihomoControllerClient(endpoint: status.endpoint).groupDelay(group: group)
    }

    public func refreshProfile(from url: URL, useProxy: Bool = false) async throws -> Profile {
        let status = try supervisor.status()
        let proxyPort = status.state == .running ? status.proxyPorts.mixedPort : nil
        let summary = try await profileRepository.saveRemoteProfile(
            from: url,
            useProxy: useProxy,
            proxyPort: proxyPort
        )
        return try profileRepository.loadProfile(id: summary.id)
    }

    public func importProfile(from url: URL) throws -> ProfileSummary {
        let profile = try profileRepository.importLocalProfile(from: url)
        return try profileRepository.saveProfile(profile)
    }

    public func profileContent(id: String) throws -> String {
        try profileRepository.profileContent(id: id)
    }

    @discardableResult
    public func updateProfile(
        id: String,
        name: String,
        remoteURL: URL?,
        autoUpdate: Bool,
        useProxy: Bool,
        rawYAML: String
    ) throws -> ProfileSummary {
        try profileRepository.updateProfile(
            id: id,
            name: name,
            remoteURL: remoteURL,
            autoUpdate: autoUpdate,
            useProxy: useProxy,
            rawYAML: rawYAML
        )
    }

    @discardableResult
    public func deleteProfile(id: String) throws -> Bool {
        try profileRepository.deleteProfile(id: id)
    }

    @discardableResult
    public func refreshProfile(id: String) async throws -> ProfileSummary {
        let status = try supervisor.status()
        let proxyPort = status.state == .running ? status.proxyPorts.mixedPort : nil
        return try await profileRepository.refreshRemoteProfile(id: id, proxyPort: proxyPort)
    }

    @discardableResult
    public func refreshDueProfiles() async throws -> [ProfileSummary] {
        let status = try supervisor.status()
        let proxyPort = status.state == .running ? status.proxyPorts.mixedPort : nil
        return try await profileRepository.refreshDueRemoteProfiles(proxyPort: proxyPort)
    }

    public func recentLogs(limit: Int = 300) throws -> [LogEntry] {
        guard FileManager.default.fileExists(atPath: paths.coreLogFile.path) else {
            return []
        }

        let content = try String(contentsOf: paths.coreLogFile, encoding: .utf8)
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(limit)

        return lines.enumerated().map { index, line in
            let message = String(line)
            return LogEntry(
                id: "\(index)-\(message.hashValue)",
                level: logLevel(in: message),
                message: message
            )
        }
    }

    @discardableResult
    public func setSystemProxy(_ isEnabled: Bool, dryRun: Bool = false) throws -> [ShellCommand] {
        let status = try stateStore.load()
        return try systemProxyController.setEnabled(
            isEnabled,
            configuration: SystemProxyConfiguration(
                host: status.endpoint.host,
                port: status.proxyPorts.mixedPort
            ),
            dryRun: dryRun
        )
    }

    private func logLevel(in message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("error") { return "error" }
        if lowercased.contains("warn") { return "warning" }
        if lowercased.contains("debug") { return "debug" }
        return "info"
    }
}
