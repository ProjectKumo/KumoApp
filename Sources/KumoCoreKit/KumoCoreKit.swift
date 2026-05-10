import Foundation

public struct KumoController: Sendable {
    public let paths: KumoPaths
    private let profileRepository: ProfileRepository
    private let overrideRepository: OverrideRepository
    private let supervisor: CoreSupervisor
    private let stateStore: CoreStateStore
    private let systemProxyController: SystemProxyController
    private let coreInstaller: CoreInstaller
    private let subStoreManager: SubStoreManager
    private let backupManager: KumoBackupManager
    private let appUpdateManager: AppUpdateManager
    private let appUpdateInstaller: AppUpdateInstaller
    private let preferencesStore: UserPreferencesStore
    private let subStoreSupervisor: SubStoreSupervisor
    private let serviceManager: KumoServiceManager
    private let useServiceBackend: Bool

    public init(paths: KumoPaths = KumoPaths(), useServiceBackend: Bool = true) {
        self.paths = paths
        self.profileRepository = ProfileRepository(paths: paths)
        self.overrideRepository = OverrideRepository(paths: paths)
        self.supervisor = CoreSupervisor(paths: paths)
        self.stateStore = CoreStateStore(paths: paths)
        self.systemProxyController = SystemProxyController(paths: paths)
        self.coreInstaller = CoreInstaller(paths: paths)
        self.subStoreManager = SubStoreManager(paths: paths)
        self.backupManager = KumoBackupManager(paths: paths)
        self.appUpdateManager = AppUpdateManager()
        self.appUpdateInstaller = AppUpdateInstaller(paths: paths)
        self.preferencesStore = UserPreferencesStore(paths: paths)
        self.subStoreSupervisor = SubStoreSupervisor(paths: paths)
        self.serviceManager = KumoServiceManager(paths: paths)
        self.useServiceBackend = useServiceBackend
    }

    public func status() throws -> CoreStatus {
        if let client = runningServiceClient() {
            return try client.sendDecodable(client.statusRequest(), as: CoreStatus.self)
        }
        return try supervisor.status()
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

    /// Clear any explicit core path so the supervisor falls back to auto-discovery
    /// (managed core, env, $PATH, bundled binaries).
    public func clearCorePath() throws {
        var status = try stateStore.load()
        status.corePath = nil
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
        if corePath == nil, let client = runningServiceClient() {
            return try client.sendDecodable(client.startCoreRequest(), as: CoreStatus.self)
        }
        let currentStatus = try normalizedStatusForLaunch()
        let profile = try profileRepository.loadDefaultProfile()
        let overrideYAMLs = try overrideRepository.activeYAMLs()
        return try supervisor.start(
            configuration: CoreLaunchConfiguration(
                corePath: corePath ?? currentStatus.corePath,
                profile: profile,
                overrideYAMLs: overrideYAMLs,
                endpoint: currentStatus.endpoint,
                proxyPorts: currentStatus.proxyPorts,
                mode: currentStatus.mode,
                runtimeSettings: runtimeSettings(for: currentStatus)
            )
        )
    }

    @discardableResult
    public func stop() throws -> CoreStatus {
        if let client = runningServiceClient() {
            return try client.sendDecodable(client.stopCoreRequest(), as: CoreStatus.self)
        }
        return try supervisor.stop()
    }

    public func restart(corePath: String? = nil) throws -> CoreStatus {
        if corePath == nil, let client = runningServiceClient() {
            return try client.sendDecodable(client.restartCoreRequest(), as: CoreStatus.self)
        }
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

    public func updateRuntimeSettings(_ settings: CoreRuntimeSettings) async throws {
        var status = try stateStore.load()
        status.runtimeSettings = settings
        status.proxyPorts.mixedPort = settings.mixedPort
        try stateStore.save(status)

        if status.state == .running {
            try await MihomoControllerClient(endpoint: status.endpoint).patchConfiguration(runtimePatch(for: settings))
        }

        if status.systemProxyEnabled {
            _ = try await setSystemProxy(true)
        }
    }

    public func setControllerSecret(_ secret: String) throws {
        var status = try stateStore.load()
        status.endpoint.secret = secret
        try stateStore.save(status)
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
                _ = try supervisor.updateReadiness(.controllerReady, message: "Mihomo controller is ready.")
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

    public func setRuleEnabled(index: Int, isEnabled: Bool) async throws {
        let status = try stateStore.load()
        try await MihomoControllerClient(endpoint: status.endpoint).setRulesDisabled([index: !isEnabled])
    }

    public func connections() async throws -> [ConnectionEntry] {
        let status = try stateStore.load()
        return try await MihomoControllerClient(endpoint: status.endpoint).connections()
    }

    public func closeConnection(id: String) async throws {
        let status = try stateStore.load()
        try await MihomoControllerClient(endpoint: status.endpoint).closeConnection(id: id)
    }

    public func closeConnections(matchingProxy proxy: String? = nil) async throws {
        let status = try stateStore.load()
        try await MihomoControllerClient(endpoint: status.endpoint).closeConnections(matchingProxy: proxy)
    }

    public func selectProxy(group: String, name: String) async throws {
        let status = try stateStore.load()
        try await MihomoControllerClient(endpoint: status.endpoint).selectProxy(group: group, name: name)
    }

    public func proxyProviders() async throws -> [ProxyProviderEntry] {
        let status = try stateStore.load()
        return try await MihomoControllerClient(endpoint: status.endpoint).proxyProviders()
    }

    public func updateProxyProvider(name: String) async throws {
        let status = try stateStore.load()
        try await MihomoControllerClient(endpoint: status.endpoint).updateProxyProvider(name: name)
    }

    public func ruleProviders() async throws -> [RuleProviderEntry] {
        let status = try stateStore.load()
        return try await MihomoControllerClient(endpoint: status.endpoint).ruleProviders()
    }

    public func updateRuleProvider(name: String) async throws {
        let status = try stateStore.load()
        try await MihomoControllerClient(endpoint: status.endpoint).updateRuleProvider(name: name)
    }

    public func upgradeGeoData() async throws {
        let status = try stateStore.load()
        try await MihomoControllerClient(endpoint: status.endpoint).upgradeGeoData()
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

    public func overrides() throws -> [OverrideItem] {
        try overrideRepository.listOverrides()
    }

    public func overrideContent(id: String) throws -> String {
        try overrideRepository.content(id: id)
    }

    @discardableResult
    public func addLocalOverride(name: String, format: OverrideFormat, content: String, isGlobal: Bool = false) throws -> OverrideItem {
        try overrideRepository.addLocalOverride(name: name, format: format, content: content, isGlobal: isGlobal)
    }

    @discardableResult
    public func addRemoteOverride(url: URL, name: String? = nil, format: OverrideFormat = .yaml, fingerprint: String? = nil, isGlobal: Bool = false) async throws -> OverrideItem {
        try await overrideRepository.addRemoteOverride(url: url, name: name, format: format, fingerprint: fingerprint, isGlobal: isGlobal)
    }

    public func updateOverride(_ item: OverrideItem, content: String? = nil) throws {
        try overrideRepository.updateOverride(item, content: content)
    }

    public func deleteOverride(id: String) throws {
        try overrideRepository.deleteOverride(id: id)
    }

    public func reorderOverrides(ids: [String]) throws {
        try overrideRepository.reorderOverrides(ids: ids)
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

    public func logStream(level: String = "info") throws -> AsyncThrowingStream<LogEntry, Error> {
        let status = try stateStore.load()
        return MihomoControllerClient(endpoint: status.endpoint).logStream(level: level)
    }

    public func trafficStream() throws -> AsyncThrowingStream<TrafficSnapshot, Error> {
        let status = try stateStore.load()
        return MihomoControllerClient(endpoint: status.endpoint).trafficStream()
    }

    public func memoryStream() throws -> AsyncThrowingStream<MemorySnapshot, Error> {
        let status = try stateStore.load()
        return MihomoControllerClient(endpoint: status.endpoint).memoryStream()
    }

    public func runtimeEvents(limit: Int = 200) throws -> [RuntimeEventEntry] {
        try supervisor.recentRuntimeEvents(limit: limit)
    }

    @discardableResult
    public func setSystemProxy(_ isEnabled: Bool, dryRun: Bool = false) async throws -> [ShellCommand] {
        if !dryRun, let client = runningServiceClient() {
            _ = try client.send(client.setSystemProxyEnabledRequest(isEnabled))
            return []
        }
        let status = try stateStore.load()
        let settings = try effectiveSystemProxySettings(for: status)
        return try await systemProxyController.setEnabled(
            isEnabled,
            configuration: SystemProxyConfiguration(
                networkService: settings.networkService,
                host: settings.host,
                port: settings.port,
                bypassList: settings.bypassList,
                mode: settings.mode,
                pacScript: settings.pacScript
            ),
            dryRun: dryRun
        )
    }

    public func availableNetworkServices() throws -> [String] {
        try systemProxyController.availableNetworkServices()
    }

    public func activeNetworkService() throws -> String {
        try systemProxyController.activeNetworkService()
    }

    public func updateSystemProxySettings(_ settings: SystemProxySettings) throws {
        var status = try stateStore.load()
        status.systemProxySettings = settings
        try stateStore.save(status)
    }

    public func serviceModeStatus() -> ServiceModeStatus {
        let status = serviceManager.status()
        persistServiceStatus(status)
        return status
    }

    @discardableResult
    public func installServiceMode() throws -> ServiceModeStatus {
        let status = try serviceManager.installService()
        persistServiceStatus(status)
        return status
    }

    @discardableResult
    public func uninstallServiceMode() throws -> ServiceModeStatus {
        let status = try serviceManager.uninstallService()
        persistServiceStatus(status)
        return status
    }

    public func tunStatus() throws -> TunStatus {
        if let client = runningServiceClient() {
            return try client.sendDecodable(client.tunStatusRequest(), as: TunStatus.self)
        }
        let status = try stateStore.load()
        let service = serviceManager.status()
        let settings = status.runtimeSettings?.tun ?? TunSettings()
        let logPermissionError = recentTunPermissionError()
        return TunStatus(
            isEnabled: settings.isEnabled,
            isRunning: status.state == .running && settings.isEnabled && service.canManageTun,
            requiresService: !service.canManageTun,
            lastError: status.tunStatus?.lastError ?? logPermissionError
        )
    }

    public func updateTunSettings(_ settings: TunSettings) throws {
        var status = try stateStore.load()
        var runtimeSettings = runtimeSettings(for: status)
        runtimeSettings.tun = settings
        status.runtimeSettings = runtimeSettings
        status.tunStatus = TunStatus(
            isEnabled: settings.isEnabled,
            isRunning: status.state == .running && settings.isEnabled && serviceManager.status().canManageTun,
            requiresService: !serviceManager.status().canManageTun,
            lastError: status.tunStatus?.lastError
        )
        try stateStore.save(status)
    }

    @discardableResult
    public func setTunEnabled(_ isEnabled: Bool) async throws -> TunStatus {
        if let client = runningServiceClient() {
            return try client.sendDecodable(client.setTunEnabledRequest(isEnabled), as: TunStatus.self)
        }
        var status = try stateStore.load()
        let service = serviceManager.status()
        var runtimeSettings = runtimeSettings(for: status)
        var tun = runtimeSettings.tun ?? TunSettings()

        if isEnabled, !service.canManageTun {
            let message = service.message ?? "TUN requires the Kumo privileged helper."
            status.serviceModeStatus = service
            status.tunStatus = TunStatus(isEnabled: false, isRunning: false, requiresService: true, lastError: message)
            try stateStore.save(status)
            throw KumoError.serviceUnavailable(message)
        }

        tun.isEnabled = isEnabled
        runtimeSettings.tun = tun
        status.runtimeSettings = runtimeSettings
        status.proxyPorts.mixedPort = runtimeSettings.mixedPort
        status.serviceModeStatus = service
        status.tunStatus = TunStatus(
            isEnabled: isEnabled,
            isRunning: status.state == .running && isEnabled,
            requiresService: !service.canManageTun,
            lastError: nil
        )
        try stateStore.save(status)

        if status.state == .running {
            _ = try restart()
            try await waitForControllerReady()
        }

        return try tunStatus()
    }

    public func subStoreStatus() throws -> SubStoreStatus {
        try subStoreManager.status()
    }

    public func updateSubStoreStatus(_ status: SubStoreStatus) throws {
        try subStoreManager.updateStatus(status)
    }

    @discardableResult
    public func setSubStoreEnabled(_ isEnabled: Bool) async throws -> SubStoreStatus {
        let status = try subStoreManager.markEnabled(isEnabled)
        if isEnabled {
            try await subStoreSupervisor.start(plan: subStoreManager.launchPlan(for: status))
        } else {
            await subStoreSupervisor.stop()
        }
        return status
    }

    public func restartSubStoreService() async throws {
        let status = try subStoreManager.status()
        try await subStoreSupervisor.restart(plan: subStoreManager.launchPlan(for: status))
    }

    public func stopSubStoreService() async {
        await subStoreSupervisor.stop()
    }

    public func subStoreServiceIsRunning() async -> Bool {
        await subStoreSupervisor.isRunning
    }

    public func subStoreWebURL() throws -> URL? {
        try subStoreManager.webURL(for: subStoreManager.status())
    }

    public func subStoreLaunchPlan() throws -> SubStoreLaunchPlan {
        try subStoreManager.launchPlan(for: subStoreManager.status())
    }

    @discardableResult
    public func downloadSubStoreBundle(kind: SubStoreBundleKind, from url: URL) async throws -> SubStoreStatus {
        try await subStoreManager.downloadBundle(kind: kind, from: url)
    }

    @discardableResult
    public func exportBackup(to destination: URL) throws -> KumoBackupResult {
        try backupManager.exportBackup(to: destination)
    }

    @discardableResult
    public func importBackup(from source: URL) throws -> KumoBackupManifest {
        try backupManager.importBackup(from: source)
    }

    public func checkAppUpdate(
        manifestURL: URL?,
        currentVersion: String,
        channel: AppUpdateChannel = .stable
    ) async throws -> AppUpdateCheckResult {
        try await appUpdateManager.checkForUpdate(
            manifestURL: manifestURL,
            currentVersion: currentVersion,
            channel: channel
        )
    }

    public func downloadAppUpdate(
        manifest: AppUpdateManifest,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> AppUpdateDownloadResult {
        try await appUpdateManager.downloadUpdate(
            manifest: manifest,
            to: paths.appUpdateDownloadsDirectory,
            progress: progress
        )
    }

    public func installAppUpdate(
        dmgURL: URL,
        currentAppURL: URL,
        processID: Int32
    ) throws {
        try appUpdateInstaller.installDMG(
            dmgURL: dmgURL,
            currentAppURL: currentAppURL,
            processID: processID
        )
    }

    public func userPreferences() -> UserPreferences {
        preferencesStore.load()
    }

    public func updateUserPreferences(_ preferences: UserPreferences) throws {
        try preferencesStore.save(preferences)
    }

    private func logLevel(in message: String) -> String {
        let lowercased = message.lowercased()
        if lowercased.contains("error") { return "error" }
        if lowercased.contains("warn") { return "warning" }
        if lowercased.contains("debug") { return "debug" }
        return "info"
    }

    private func recentTunPermissionError() -> String? {
        guard let logs = try? recentLogs(limit: 80) else {
            return nil
        }
        let permissionError = "Start TUN listening error: configure tun interface: operation not permitted"
        return logs.last(where: { $0.message.contains(permissionError) }).map { _ in
            "TUN could not create the macOS network interface. Install or repair the privileged helper, then enable TUN again."
        }
    }

    private func runtimeSettings(for status: CoreStatus) -> CoreRuntimeSettings {
        var settings = status.runtimeSettings ?? CoreRuntimeSettings(mixedPort: status.proxyPorts.mixedPort)
        settings.mixedPort = status.proxyPorts.mixedPort
        return settings
    }

    private func normalizedStatusForLaunch() throws -> CoreStatus {
        var status = try stateStore.load()
        let service = serviceManager.status()
        status.serviceModeStatus = service
        if var runtimeSettings = status.runtimeSettings,
           var tun = runtimeSettings.tun,
           tun.isEnabled,
           !service.canManageTun {
            tun.isEnabled = false
            runtimeSettings.tun = tun
            status.runtimeSettings = runtimeSettings
            status.tunStatus = TunStatus(
                isEnabled: false,
                isRunning: false,
                requiresService: true,
                lastError: service.message
            )
            try stateStore.save(status)
        }
        return status
    }

    private func effectiveSystemProxySettings(for status: CoreStatus) throws -> SystemProxySettings {
        let runtimePort = runtimeSettings(for: status).mixedPort
        var settings = status.systemProxySettings ?? SystemProxySettings(
            networkService: (try? systemProxyController.activeNetworkService()) ?? "Wi-Fi",
            host: status.endpoint.host,
            port: runtimePort
        )
        if settings.networkService.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || settings.networkService == "Automatic" {
            settings.networkService = try systemProxyController.activeNetworkService()
        }
        settings.port = runtimePort
        return settings
    }

    private func persistServiceStatus(_ serviceStatus: ServiceModeStatus) {
        do {
            var status = try stateStore.load()
            status.serviceModeStatus = serviceStatus
            try stateStore.save(status)
        } catch {
            // Status refresh should not fail user-facing operations.
        }
    }

    private func runningServiceClient() -> KumoServiceClient? {
        guard useServiceBackend,
              let client = serviceManager.serviceClient(),
              serviceManager.status().isRunning else {
            return nil
        }
        return client
    }

    private func runtimePatch(for settings: CoreRuntimeSettings) -> [String: Any] {
        var patch: [String: Any] = [
            "mixed-port": settings.mixedPort,
            "allow-lan": settings.allowLAN,
            "log-level": settings.logLevel,
            "ipv6": settings.ipv6,
            "geodata-mode": settings.geoData.usesDatMode,
            "geo-auto-update": settings.geoData.autoUpdate,
            "geo-update-interval": settings.geoData.updateIntervalHours,
            "geox-url": [
                "geoip": settings.geoData.geoIPURL,
                "geosite": settings.geoData.geoSiteURL,
                "mmdb": settings.geoData.mmdbURL,
                "asn": settings.geoData.asnURL
            ]
        ]
        if let tun = settings.tun {
            patch["tun"] = tunPatch(for: tun)
            if tun.isEnabled {
                patch["dns"] = dnsPatch(for: tun)
            }
        }
        return patch
    }

    private func tunPatch(for tun: TunSettings) -> [String: Any] {
        var patch: [String: Any] = [
            "enable": tun.isEnabled,
            "stack": tun.stack,
            "auto-route": tun.autoRoute,
            "auto-redirect": tun.autoRedirect,
            "auto-detect-interface": tun.autoDetectInterface,
            "strict-route": tun.strictRoute,
            "dns-hijack": tun.dnsHijack,
            "mtu": tun.mtu
        ]
        if !tun.routeExcludeAddress.isEmpty {
            patch["route-exclude-address"] = tun.routeExcludeAddress
        }
        if let device = tun.device, device.hasPrefix("utun") {
            patch["device"] = device
        }
        return patch
    }

    private func dnsPatch(for tun: TunSettings) -> [String: Any] {
        [
            "enable": tun.dnsEnabled,
            "enhanced-mode": tun.dnsEnhancedMode,
            "fake-ip-range": tun.fakeIPRange,
            "nameserver": tun.nameservers
        ]
    }
}
