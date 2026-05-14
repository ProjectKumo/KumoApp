import AppKit
import Foundation
import Observation
import KumoCoreKit

@MainActor
@Observable
final class KumoAppStore {
    var status = CoreStatus()
    var proxyGroups: [ProxyGroup] = []
    /// Read-only proxy groups parsed from the current profile YAML, used as
    /// a fallback render source for the Overview sidebar while the core is
    /// stopped. Refreshed alongside `refreshProfiles()` and after every
    /// `loadProxyGroups()` call so the preview is always current.
    var profilePreviewGroups: [ProxyGroup] = []
    var profiles: [ProfileSummary] = []
    var currentProfile: ProfileSummary?
    var coreConfiguration = CoreConfigurationSnapshot()
    var trafficSnapshot = TrafficSnapshot()
    /// Rolling 60-sample buffer of throughput data points (~60 s at
    /// mihomo's 1 Hz `/traffic` stream). Used by the Overview Traffic card
    /// to render a sparkline when expanded. Reset whenever the core stops
    /// or the stream errors out.
    var trafficHistory: [TrafficSample] = []
    var rules: [RuleEntry] = []
    var connections: [ConnectionEntry] = []
    var logs: [LogEntry] = []
    var proxyProviders: [ProxyProviderEntry] = []
    var ruleProviders: [RuleProviderEntry] = []
    var overrides: [OverrideItem] = []
    var subStoreStatus = SubStoreStatus()
    var subStoreRuntimeStatus = SubStoreRuntimeStatus()
    var subStoreEntries: [SubStoreEntry] = []
    var serviceModeStatus = ServiceModeStatus()
    var tunStatus = TunStatus()
    var coreCandidates: [CoreCandidate] = []
    var preferences = UserPreferences()
    /// Drives the first-run onboarding sheet attached at the root view.
    /// `loadPreferences()` flips this on when `preferences.hasCompletedOnboarding`
    /// is false; `completeOnboarding()` and `reopenOnboarding()` are the only
    /// authorized state transitions.
    var showOnboarding = false
    var errorMessage: String?
    var isLoading = false
    var isSwitchingMode = false
    var isImportingProfile = false
    var isInstallingCore = false
    var isTestingDelay = false
    var isStreamingLogs = false
    var isCheckingForUpdates = false
    var isDownloadingUpdate = false
    var isInstallingUpdate = false
    var updateDownloadProgress: Double?
    var updateStatusMessage: String?
    var lastUpdateCheckResult: AppUpdateCheckResult?

    let controller = KumoController()
    private let appNotificationCoordinator = AppNotificationCoordinator.shared
    private let proxyGeoLookup: ProxyGeoLookup
    private static let updatePollingIntervalNanoseconds: UInt64 = 5 * 60 * 1_000_000_000
    private var loadingTaskCount = 0
    private var trafficStreamTask: Task<Void, Never>?
    private var logStreamTask: Task<Void, Never>?
    private var lastNotifiedDownloadBucket: Int?
    private var proxyGeoTask: Task<Void, Never>?
    private var updatePollingTask: Task<Void, Never>?
    private var isPollingForUpdates = false

    private enum AppUpdateCheckSource {
        case manual
        case polling
    }

    init() {
        self.proxyGeoLookup = ProxyGeoLookup(cacheURL: controller.paths.proxyGeoCacheFile)
    }

    func refreshAll() async {
        refreshStatus()
        syncTrafficStreamWithStatus()
        refreshProfiles()
        await refreshDueProfiles()
        refreshCoreCandidates()
        refreshProfiles()
        loadPreferences()
        await loadProxyGroups()
        await loadCoreConfiguration()
        await loadInspectData()
        await loadResources()
        refreshOverrides()
        await refreshSubStoreRuntimeStatus()
        refreshServiceModeStatus()
        refreshTunStatus()
    }

    func refreshStatus() {
        do {
            status = try controller.status()
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func clearError() {
        errorMessage = nil
    }

    func refreshCoreCandidates() {
        do {
            coreCandidates = try controller.coreCandidates()
            if !coreCandidates.isEmpty {
                errorMessage = nil
            }
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func setCorePath(_ path: String) {
        do {
            try controller.setCorePath(path)
            refreshStatus()
            refreshCoreCandidates()
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func clearCorePath() {
        do {
            try controller.clearCorePath()
            refreshStatus()
            refreshCoreCandidates()
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func installManagedCore() async {
        guard !isInstallingCore else { return }

        isInstallingCore = true
        defer { isInstallingCore = false }

        await performLoadingTask { [self] in
            let wasRunning = self.status.state == .running
            let result = try await self.controller.installManagedCore()
            self.refreshCoreCandidates()

            if wasRunning {
                self.status = try self.controller.restart()
                try await self.controller.waitForControllerReady()
                await self.loadProxyGroups()
                await self.loadCoreConfiguration()
            } else {
                self.refreshStatus()
            }

            self.status.message = "Installed Mihomo core \(result.version)."
        }
    }

    func refreshProfiles() {
        do {
            profiles = try controller.profiles()
            currentProfile = try controller.currentProfile()
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
        refreshProfilePreview()
    }

    func startCore() async {
        beginLoading()
        defer { endLoading() }

        do {
            let installResult = try await installManagedCoreIfNeeded()
            status = try controller.start()
            try await controller.waitForControllerReady()
            startTrafficStream()
            refreshProfiles()
            await loadProxyGroups()
            await loadCoreConfiguration()
            await loadResources()
            refreshOverrides()
            if let installResult {
                status.message = "Installed Mihomo core \(installResult.version) and started."
            }
            errorMessage = nil
            appNotificationCoordinator.clearCoreStateNotifications()
        } catch {
            let message = displayMessage(for: error)
            errorMessage = message
            // Surface the failure as a system notification so users notice
            // it even when the main window is occluded or the menu bar
            // status item isn't visible.
            appNotificationCoordinator.postCoreStartFailed(error: message)
        }
    }

    func stopCore() {
        do {
            stopTrafficStream()
            stopLogStream()
            status = try controller.stop()
            proxyGroups = []
            rules = []
            connections = []
            proxyProviders = []
            ruleProviders = []
            coreConfiguration = CoreConfigurationSnapshot(mode: status.mode, mixedPort: status.proxyPorts.mixedPort)
            trafficSnapshot = TrafficSnapshot()
            trafficHistory = []
            refreshServiceModeStatus()
            refreshTunStatus()
            errorMessage = nil
            appNotificationCoordinator.clearCoreStateNotifications()
        } catch {
            let message = displayMessage(for: error)
            errorMessage = message
            appNotificationCoordinator.postCoreStopFailed(error: message)
        }
    }

    func setMode(_ mode: OutboundMode) async {
        guard mode != status.mode else { return }
        guard !isSwitchingMode else { return }

        let previousStatusMode = status.mode
        let previousConfigurationMode = coreConfiguration.mode
        var didApplyMode = false

        isSwitchingMode = true
        status.mode = mode
        coreConfiguration.mode = mode
        defer { isSwitchingMode = false }

        do {
            try await controller.setMode(mode)
            didApplyMode = true
            errorMessage = nil

            if status.state == .running {
                try await controller.closeConnections(matchingProxy: nil)
                connections = []
                await loadProxyGroups()
            }
        } catch {
            if !didApplyMode {
                status.mode = previousStatusMode
                coreConfiguration.mode = previousConfigurationMode
            }
            errorMessage = displayMessage(for: error)
        }
    }

    func loadProxyGroups() async {
        guard status.state == .running else {
            proxyGroups = []
            proxyGeoTask?.cancel()
            proxyGeoTask = nil
            return
        }

        do {
            proxyGroups = try await controller.proxyGroups()
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }

        applyCachedCountries()
        scheduleCountryDetection()
        refreshProfilePreview()
    }

    /// Re-parses the current profile YAML into a list of read-only proxy
    /// groups (`profilePreviewGroups`). Used by the Overview sidebar to
    /// render the user's configured nodes while mihomo is stopped. Failures
    /// are intentionally swallowed — there's no actionable error to surface
    /// for a missing or malformed `proxy-groups:` section, and the empty
    /// fallback already provides a clear UI state.
    private func refreshProfilePreview() {
        guard let profileID = currentProfile?.id else {
            profilePreviewGroups = []
            return
        }
        guard let yaml = try? controller.profileContent(id: profileID) else {
            profilePreviewGroups = []
            return
        }
        guard let groups = try? ProfileNodeParser.parseProxyGroups(yaml: yaml) else {
            profilePreviewGroups = []
            return
        }
        profilePreviewGroups = groups
    }

    /// Reads cached `server → country` codes for every node in the current
    /// `proxyGroups` and writes them onto `detectedCountry` synchronously,
    /// so the UI shows known flags immediately without waiting on the
    /// async lookup task.
    private func applyCachedCountries() {
        guard let serverMap = currentProfileServerMap(), !serverMap.isEmpty else {
            return
        }
        Task { @MainActor [proxyGeoLookup] in
            var updates: [String: String] = [:]
            for server in Set(serverMap.values) {
                if let code = await proxyGeoLookup.cachedCountry(for: server) {
                    updates[server] = code
                }
            }
            guard !updates.isEmpty else { return }
            self.writeBackCountries(serverMap: serverMap, codes: updates)
        }
    }

    /// Spawns a single async task that resolves country codes for every
    /// known node server in the current profile, deduplicating across nodes
    /// that share a server and writing the result back to `proxyGroups`.
    /// Re-entrancy is guarded by `proxyGeoTask` — calling this again while
    /// a previous lookup is still in flight cancels the previous task.
    private func scheduleCountryDetection() {
        proxyGeoTask?.cancel()
        guard let serverMap = currentProfileServerMap(), !serverMap.isEmpty else {
            return
        }
        let hosts = Array(Set(serverMap.values))
        let lookup = proxyGeoLookup
        proxyGeoTask = Task { @MainActor [weak self] in
            let codes = await lookup.countries(for: hosts)
            guard !Task.isCancelled, let self else { return }
            self.writeBackCountries(serverMap: serverMap, codes: codes)
        }
    }

    private func writeBackCountries(serverMap: [String: String], codes: [String: String]) {
        guard !codes.isEmpty else { return }
        var updated = proxyGroups
        var didChange = false
        for groupIndex in updated.indices {
            for proxyIndex in updated[groupIndex].proxies.indices {
                let proxyName = updated[groupIndex].proxies[proxyIndex].name
                guard let server = serverMap[proxyName] else { continue }
                guard let code = codes[server.lowercased()] ?? codes[server] else { continue }
                if updated[groupIndex].proxies[proxyIndex].detectedCountry != code {
                    updated[groupIndex].proxies[proxyIndex].detectedCountry = code
                    didChange = true
                }
            }
        }
        if didChange {
            proxyGroups = updated
        }
    }

    private func currentProfileServerMap() -> [String: String]? {
        guard let profileID = currentProfile?.id else { return nil }
        guard let yaml = try? controller.profileContent(id: profileID) else { return nil }
        guard let nodes = try? ProfileNodeParser.parseNodes(yaml: yaml) else { return nil }
        return nodes.mapValues(\.server)
    }

    func loadCoreConfiguration() async {
        guard status.state == .running else {
            let settings = status.runtimeSettings ?? CoreRuntimeSettings(mixedPort: status.proxyPorts.mixedPort)
            coreConfiguration = CoreConfigurationSnapshot(
                mode: status.mode,
                mixedPort: settings.mixedPort,
                logLevel: settings.logLevel,
                allowLAN: settings.allowLAN,
                ipv6: settings.ipv6,
                geoData: settings.geoData,
                tunEnabled: settings.tun?.isEnabled ?? false
            )
            return
        }

        do {
            coreConfiguration = try await controller.coreConfiguration()
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func loadInspectData() async {
        do {
            logs = try controller.recentLogs()
        } catch {
            logs = []
        }

        guard status.state == .running else {
            rules = []
            connections = []
            return
        }

        do {
            async let nextRules = controller.rules()
            async let nextConnections = controller.connections()
            rules = try await nextRules
            connections = try await nextConnections
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func loadResources() async {
        guard status.state == .running else {
            proxyProviders = []
            ruleProviders = []
            return
        }

        do {
            async let nextProxyProviders = controller.proxyProviders()
            async let nextRuleProviders = controller.ruleProviders()
            proxyProviders = try await nextProxyProviders
            ruleProviders = try await nextRuleProviders
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func updateRuntimeSettings(_ settings: CoreRuntimeSettings) async {
        await performLoadingTask { [self] in
            try await controller.updateRuntimeSettings(settings)
            status.runtimeSettings = settings
            status.proxyPorts.mixedPort = settings.mixedPort
            if let service = try? controller.status().serviceModeStatus {
                serviceModeStatus = service
            }
            coreConfiguration.mixedPort = settings.mixedPort
            coreConfiguration.logLevel = settings.logLevel
            coreConfiguration.allowLAN = settings.allowLAN
            coreConfiguration.ipv6 = settings.ipv6
            coreConfiguration.geoData = settings.geoData
            coreConfiguration.tunEnabled = settings.tun?.isEnabled ?? coreConfiguration.tunEnabled
        }
    }

    func setControllerSecret(_ secret: String) {
        do {
            try controller.setControllerSecret(secret)
            status.endpoint.secret = secret
            if status.state == .running {
                startTrafficStream()
            }
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func setRuleEnabled(_ rule: RuleEntry, isEnabled: Bool) async {
        await performLoadingTask { [self] in
            try await controller.setRuleEnabled(index: rule.index, isEnabled: isEnabled)
            if let index = rules.firstIndex(where: { $0.id == rule.id }) {
                rules[index].isEnabled = isEnabled
            }
        }
    }

    func updateProxyProvider(_ provider: ProxyProviderEntry) async {
        await performLoadingTask { [self] in
            try await controller.updateProxyProvider(name: provider.name)
            await loadResources()
        }
    }

    func updateRuleProvider(_ provider: RuleProviderEntry) async {
        await performLoadingTask { [self] in
            try await controller.updateRuleProvider(name: provider.name)
            await loadResources()
        }
    }

    func updateAllProviders() async {
        await performLoadingTask { [self] in
            for provider in proxyProviders {
                try await controller.updateProxyProvider(name: provider.name)
            }
            for provider in ruleProviders {
                try await controller.updateRuleProvider(name: provider.name)
            }
            await loadResources()
        }
    }

    func upgradeGeoData() async {
        await performLoadingTask { [self] in
            try await controller.upgradeGeoData()
        }
    }

    func selectProxy(group: ProxyGroup, proxy: ProxyNode) async {
        await performLoadingTask { [self] in
            try await self.controller.selectProxy(group: group.name, name: proxy.name)
            await self.loadProxyGroups()
        }
    }

    func testDelay(for group: ProxyGroup) async {
        isTestingDelay = true
        defer { isTestingDelay = false }

        do {
            let nodes = try await controller.testGroupDelay(group: group)
            if let index = proxyGroups.firstIndex(where: { $0.id == group.id }) {
                proxyGroups[index].proxies = nodes
            }
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func importRemoteProfile(urlString: String, useProxy: Bool) async {
        guard let url = URL(string: urlString), !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a valid profile URL."
            return
        }

        isImportingProfile = true
        defer { isImportingProfile = false }

        await performLoadingTask { [self] in
            _ = try await controller.refreshProfile(from: url, useProxy: useProxy)
            refreshProfiles()
            try await activateCurrentProfileAfterImport()
        }
    }

    func importLocalProfile(from url: URL) async {
        await performLoadingTask { [self] in
            _ = try controller.importProfile(from: url)
            refreshProfiles()
            try await activateCurrentProfileAfterImport()
        }
    }

    func profileContent(id: String) -> String? {
        do {
            return try controller.profileContent(id: id)
        } catch {
            errorMessage = displayMessage(for: error)
            return nil
        }
    }

    func refreshOverrides() {
        do {
            overrides = try controller.overrides()
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func refreshSubStoreStatus() {
        do {
            subStoreStatus = try controller.subStoreStatus()
            subStoreRuntimeStatus.configuration = subStoreStatus
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func refreshSubStoreRuntimeStatus() async {
        do {
            subStoreRuntimeStatus = try await controller.subStoreRuntimeStatus()
            subStoreStatus = subStoreRuntimeStatus.configuration
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func prepareSubStoreResources() {
        do {
            subStoreStatus = try controller.prepareSubStoreResources()
            subStoreRuntimeStatus.configuration = subStoreStatus
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func setSubStoreEnabled(_ isEnabled: Bool) async {
        await performLoadingTask { [self] in
            subStoreStatus = try await controller.setSubStoreEnabled(isEnabled)
            subStoreRuntimeStatus = try await controller.subStoreRuntimeStatus()
        }
    }

    func restartSubStoreService() async {
        await performLoadingTask { [self] in
            try await controller.restartSubStoreService()
            subStoreRuntimeStatus = try await controller.subStoreRuntimeStatus()
        }
    }

    func stopSubStoreService() async {
        await controller.stopSubStoreService()
        await refreshSubStoreRuntimeStatus()
    }

    func updateSubStoreStatus(_ status: SubStoreStatus) {
        do {
            try controller.updateSubStoreStatus(status)
            subStoreStatus = status
            subStoreRuntimeStatus.configuration = status
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func downloadSubStoreBundle(kind: SubStoreBundleKind, urlString: String) async {
        guard let url = URL(string: urlString) else {
            errorMessage = "Enter a valid Sub-Store bundle URL."
            return
        }

        await performLoadingTask { [self] in
            subStoreStatus = try await controller.downloadSubStoreBundle(kind: kind, from: url)
        }
    }

    func loadSubStoreEntries() async {
        do {
            async let subscriptions = controller.subStoreEntries(kind: .subscription)
            async let collections = controller.subStoreEntries(kind: .collection)
            let loadedSubscriptions = try await subscriptions
            let loadedCollections = try await collections
            subStoreEntries = loadedSubscriptions + loadedCollections
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func importSubStoreProfile(path: String, name: String?, useProxy: Bool) async {
        await performLoadingTask { [self] in
            _ = try await controller.importSubStoreProfile(path: path, name: name, useProxy: useProxy)
            refreshProfiles()
        }
    }

    func overrideContent(id: String) -> String? {
        do {
            return try controller.overrideContent(id: id)
        } catch {
            errorMessage = displayMessage(for: error)
            return nil
        }
    }

    func addLocalOverride(name: String, format: OverrideFormat, content: String, isGlobal: Bool) {
        do {
            _ = try controller.addLocalOverride(name: name, format: format, content: content, isGlobal: isGlobal)
            refreshOverrides()
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func addRemoteOverride(urlString: String, format: OverrideFormat, isGlobal: Bool) async {
        guard let url = URL(string: urlString) else {
            errorMessage = "Enter a valid override URL."
            return
        }

        await performLoadingTask { [self] in
            _ = try await controller.addRemoteOverride(url: url, format: format, isGlobal: isGlobal)
            refreshOverrides()
        }
    }

    func updateOverride(_ item: OverrideItem, content: String?) {
        do {
            try controller.updateOverride(item, content: content)
            refreshOverrides()
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func deleteOverride(_ item: OverrideItem) {
        do {
            try controller.deleteOverride(id: item.id)
            refreshOverrides()
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func updateProfile(
        id: String,
        name: String,
        remoteURLString: String?,
        autoUpdate: Bool,
        useProxy: Bool,
        rawYAML: String
    ) async {
        await performLoadingTask { [self] in
            let trimmedURL = remoteURLString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let remoteURL = trimmedURL.isEmpty ? nil : URL(string: trimmedURL)
            if !trimmedURL.isEmpty, remoteURL == nil {
                throw KumoError.invalidArguments("Enter a valid subscription URL.")
            }

            let wasCurrent = self.currentProfile?.id == id
            _ = try self.controller.updateProfile(
                id: id,
                name: name,
                remoteURL: remoteURL,
                autoUpdate: autoUpdate,
                useProxy: useProxy,
                rawYAML: rawYAML
            )
            self.refreshProfiles()
            try await self.reactivateCurrentProfileIfNeeded(wasCurrent, message: "Profile updated.")
        }
    }

    func refreshProfile(_ profile: ProfileSummary) async {
        await performLoadingTask { [self] in
            _ = try await self.controller.refreshProfile(id: profile.id)
            self.refreshProfiles()
            try await self.reactivateCurrentProfileIfNeeded(profile.isCurrent, message: "Profile refreshed.")
        }
    }

    func deleteProfile(_ profile: ProfileSummary) async {
        await performLoadingTask { [self] in
            let deletedCurrentProfile = try self.controller.deleteProfile(id: profile.id)
            self.refreshProfiles()
            try await self.reactivateCurrentProfileIfNeeded(deletedCurrentProfile, message: "Profile deleted.")
        }
    }

    func selectProfile(_ profile: ProfileSummary) async {
        await performLoadingTask { [self] in
            try self.controller.setCurrentProfile(id: profile.id)
            self.refreshProfiles()
            if self.status.state == .running {
                self.status = try self.controller.restart()
                try await self.controller.waitForControllerReady()
                self.startTrafficStream()
                await self.loadProxyGroups()
                await self.loadCoreConfiguration()
            }
        }
    }

    func setSystemProxyEnabled(_ isEnabled: Bool) {
        guard status.state == .running || !isEnabled else {
            errorMessage = "Start Kumo before enabling System Proxy."
            return
        }

        Task { @MainActor in
            do {
                _ = try await controller.setSystemProxy(isEnabled)
                status.systemProxyEnabled = isEnabled
                errorMessage = nil
            } catch {
                errorMessage = displayMessage(for: error)
            }
        }
    }

    func updateSystemProxySettings(_ settings: SystemProxySettings) {
        do {
            try controller.updateSystemProxySettings(settings)
            status.systemProxySettings = settings
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func refreshServiceModeStatus() {
        serviceModeStatus = controller.serviceModeStatus()
    }

    func refreshTunStatus() {
        do {
            tunStatus = try controller.tunStatus()
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func installServiceMode() async {
        await performLoadingTask { [self] in
            serviceModeStatus = try controller.installServiceMode()
            refreshStatus()
            refreshTunStatus()
        }
    }

    func uninstallServiceMode() async {
        await performLoadingTask { [self] in
            serviceModeStatus = try controller.uninstallServiceMode()
            refreshStatus()
            refreshTunStatus()
        }
    }

    func updateTunSettings(_ settings: TunSettings) {
        do {
            try controller.updateTunSettings(settings)
            var runtimeSettings = status.runtimeSettings ?? CoreRuntimeSettings(mixedPort: status.proxyPorts.mixedPort)
            runtimeSettings.tun = settings
            status.runtimeSettings = runtimeSettings
            tunStatus = try controller.tunStatus()
            coreConfiguration.tunEnabled = settings.isEnabled
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func applyTunSettings(_ settings: TunSettings) async {
        await performLoadingTask { [self] in
            tunStatus = try await controller.applyTunSettings(settings)
            refreshStatus()
            refreshServiceModeStatus()
            if status.state == .running {
                try await controller.waitForControllerReady()
                await loadCoreConfiguration()
                startTrafficStream()
            } else {
                var runtimeSettings = status.runtimeSettings ?? CoreRuntimeSettings(mixedPort: status.proxyPorts.mixedPort)
                runtimeSettings.tun = settings
                status.runtimeSettings = runtimeSettings
                coreConfiguration.tunEnabled = tunStatus.isEnabled
            }
        }
    }

    func setTunEnabled(_ isEnabled: Bool) async {
        await performLoadingTask { [self] in
            tunStatus = try await controller.setTunEnabled(isEnabled)
            refreshStatus()
            refreshServiceModeStatus()
            if status.state == .running {
                try await controller.waitForControllerReady()
                await loadCoreConfiguration()
                startTrafficStream()
            } else {
                coreConfiguration.tunEnabled = tunStatus.isEnabled
            }
        }
    }

    func startLogStream(level: String? = nil) {
        guard status.state == .running else { return }
        logStreamTask?.cancel()
        isStreamingLogs = true
        let selectedLevel = level ?? coreConfiguration.logLevel
        logStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                let stream = try self.controller.logStream(level: selectedLevel)
                for try await log in stream {
                    await MainActor.run {
                        self.appendLog(log)
                    }
                }
            } catch {
                await MainActor.run {
                    self.isStreamingLogs = false
                }
            }
        }
    }

    func stopLogStream() {
        logStreamTask?.cancel()
        logStreamTask = nil
        isStreamingLogs = false
    }

    private func startTrafficStream() {
        guard status.state == .running else { return }
        trafficStreamTask?.cancel()
        trafficStreamTask = Task { [weak self] in
            guard let self else { return }
            do {
                // The underlying websocket stream supervises its own reconnects and yields a zero
                // snapshot when the connection drops, so we no longer need to reset on errors here.
                let stream = try self.controller.trafficStream()
                for try await snapshot in stream {
                    await MainActor.run {
                        self.trafficSnapshot = snapshot
                        self.appendTrafficSample(from: snapshot)
                    }
                }
            } catch is CancellationError {
                return
            } catch {
                // Only reachable if KumoController couldn't construct the stream (e.g. state file
                // unreadable). Surface the disconnected state so the UI doesn't display stale data.
                await MainActor.run {
                    self.trafficSnapshot = TrafficSnapshot()
                    self.trafficHistory = []
                }
            }
        }
    }

    private func stopTrafficStream() {
        trafficStreamTask?.cancel()
        trafficStreamTask = nil
        trafficSnapshot = TrafficSnapshot()
        trafficHistory = []
    }

    private func appendTrafficSample(from snapshot: TrafficSnapshot) {
        let sample = TrafficSample(
            timestamp: Date(),
            upload: snapshot.uploadSpeed,
            download: snapshot.downloadSpeed
        )
        trafficHistory.append(sample)
        let capacity = 60
        if trafficHistory.count > capacity {
            trafficHistory.removeFirst(trafficHistory.count - capacity)
        }
    }

    func clearLogs() {
        logs = []
    }

    func loadPreferences() {
        preferences = controller.userPreferences()
        if !preferences.hasCompletedOnboarding {
            showOnboarding = true
        }
    }

    func updatePreferences(_ next: UserPreferences) {
        do {
            try controller.updateUserPreferences(next)
            preferences = next
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    /// Persists onboarding completion and dismisses the sheet. Called when the
    /// user reaches the final Done step or explicitly skips it.
    func completeOnboarding() {
        var next = preferences
        next.hasCompletedOnboarding = true
        updatePreferences(next)
        showOnboarding = false
    }

    /// Lets Settings reopen the onboarding flow without resetting the
    /// persisted completion flag. The flag will be re-saved when the user
    /// finishes the sheet again.
    func reopenOnboarding() {
        showOnboarding = true
    }

    func startUpdatePolling() {
        guard updatePollingTask == nil else { return }
        updatePollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: Self.updatePollingIntervalNanoseconds)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                await self?.checkForUpdate(source: .polling)
            }
        }
    }

    func stopUpdatePolling() {
        updatePollingTask?.cancel()
        updatePollingTask = nil
    }

    func checkForUpdate() async {
        await checkForUpdate(source: .manual)
    }

    private func checkForUpdate(source: AppUpdateCheckSource) async {
        guard !isCheckingForUpdates, !isPollingForUpdates else { return }
        guard !isDownloadingUpdate, !isInstallingUpdate else { return }

        switch source {
        case .manual:
            isCheckingForUpdates = true
        case .polling:
            isPollingForUpdates = true
        }
        defer {
            switch source {
            case .manual:
                isCheckingForUpdates = false
            case .polling:
                isPollingForUpdates = false
            }
        }

        do {
            let result = try await controller.checkAppUpdate(
                manifestURL: preferences.updateManifestURL,
                currentVersion: bundleShortVersion,
                channel: preferences.updateChannel
            )
            lastUpdateCheckResult = result
            if source == .manual {
                updateStatusMessage = result.update == nil ? "Kumo is up to date." : nil
            }
            if let update = result.update {
                appNotificationCoordinator.postUpdateAvailable(manifest: update)
            } else {
                appNotificationCoordinator.clearUpdateNotifications()
            }
            if source == .manual {
                errorMessage = nil
            }
        } catch {
            if source == .manual {
                errorMessage = displayMessage(for: error)
            }
        }
    }

    func downloadAndInstallUpdate(_ manifest: AppUpdateManifest) async {
        guard !isDownloadingUpdate, !isInstallingUpdate else { return }
        guard manifest.canInstallAutomatically else {
            NSWorkspace.shared.open(manifest.downloadURL)
            return
        }

        isDownloadingUpdate = true
        updateDownloadProgress = 0
        lastNotifiedDownloadBucket = 0
        updateStatusMessage = "Downloading \(manifest.version)..."
        appNotificationCoordinator.postUpdateProgress(
            manifest: manifest,
            message: "Downloading Kumo \(manifest.version)... 0%"
        )
        defer {
            isDownloadingUpdate = false
            updateDownloadProgress = nil
            lastNotifiedDownloadBucket = nil
        }

        do {
            let downloaded = try await controller.downloadAppUpdate(manifest: manifest) { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    self.updateDownloadProgress = progress
                    let percent = Int(progress * 100)
                    let bucket = max(0, min(10, percent / 10))
                    if bucket != self.lastNotifiedDownloadBucket {
                        self.lastNotifiedDownloadBucket = bucket
                        self.appNotificationCoordinator.postUpdateProgress(
                            manifest: manifest,
                            message: "Downloading Kumo \(manifest.version)... \(bucket * 10)%"
                        )
                    }
                }
            }

            updateStatusMessage = "Installing \(manifest.version)..."
            appNotificationCoordinator.postUpdateProgress(
                manifest: manifest,
                message: "Installing Kumo \(manifest.version)..."
            )
            isInstallingUpdate = true
            if status.systemProxyEnabled {
                setSystemProxyEnabled(false)
            }
            if status.state == .running {
                stopCore()
            }

            try controller.installAppUpdate(
                dmgURL: downloaded.fileURL,
                currentAppURL: Bundle.main.bundleURL,
                processID: ProcessInfo.processInfo.processIdentifier
            )
            updateStatusMessage = "Kumo will relaunch after installing \(manifest.version)."
            appNotificationCoordinator.postRestartReady(manifest: manifest)
            NSApplication.shared.terminate(nil)
        } catch {
            isInstallingUpdate = false
            updateStatusMessage = nil
            appNotificationCoordinator.clearUpdateNotifications()
            errorMessage = displayMessage(for: error)
        }
    }

    func handleNotificationAction(
        actionIdentifier: String,
        manifest: AppUpdateManifest?,
        version: String?
    ) async {
        let action = AppNotificationCoordinator.decodeAction(from: actionIdentifier)
        switch action {
        case .startUpdate:
            if let manifest = lastUpdateCheckResult?.update {
                await downloadAndInstallUpdate(manifest)
            } else if let manifest {
                await downloadAndInstallUpdate(manifest)
            } else {
                KumoAppContext.shared.openSettings()
            }
        case .remindLater:
            let version = version ?? lastUpdateCheckResult?.update?.version
            if let version {
                appNotificationCoordinator.snoozeReminder(for: version)
                updateStatusMessage = "Kumo \(version) reminder snoozed for 6 hours."
            }
        case .restartNow:
            NSApplication.shared.terminate(nil)
        case .openApp:
            KumoAppContext.shared.openMainWindow()
        }
    }

    func closeConnection(id: String) async {
        await performLoadingTask { [self] in
            try await controller.closeConnection(id: id)
            await loadInspectData()
        }
    }

    func closeConnections(ids: Set<String>) async {
        guard !ids.isEmpty else { return }
        await performLoadingTask { [self] in
            for id in ids {
                try await controller.closeConnection(id: id)
            }
            await loadInspectData()
        }
    }

    func closeAllConnections() async {
        await performLoadingTask { [self] in
            try await controller.closeConnections(matchingProxy: nil)
            await loadInspectData()
        }
    }

    var subStoreLogURL: URL {
        controller.paths.subStoreLogFile
    }

    var coreLogURL: URL {
        controller.paths.coreLogFile
    }

    private var bundleShortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private func performLoadingTask(_ operation: @MainActor () async throws -> Void) async {
        beginLoading()
        defer { endLoading() }

        do {
            try await operation()
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    private func refreshDueProfiles() async {
        do {
            let refreshed = try await controller.refreshDueProfiles()
            guard !refreshed.isEmpty else {
                return
            }

            let refreshedCurrentProfile = refreshed.contains { $0.id == currentProfile?.id }
            refreshProfiles()
            try await reactivateCurrentProfileIfNeeded(refreshedCurrentProfile, message: "Profiles auto-updated.")
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    private func reactivateCurrentProfileIfNeeded(_ shouldReactivate: Bool, message: String) async throws {
        guard shouldReactivate, status.state == .running else {
            return
        }

        status = try controller.restart()
        try await controller.waitForControllerReady()
        startTrafficStream()
        await loadProxyGroups()
        await loadCoreConfiguration()
        await loadInspectData()
        status.message = message
    }

    private func activateCurrentProfileAfterImport() async throws {
        let installResult: CoreInstallResult?

        if status.state == .running {
            installResult = nil
            status = try controller.restart()
        } else {
            installResult = try await installManagedCoreIfNeeded()
            status = try controller.start()
        }

        try await controller.waitForControllerReady()
        startTrafficStream()
        await loadProxyGroups()
        await loadCoreConfiguration()
        await loadInspectData()

        if let installResult {
            status.message = "Imported profile, installed Mihomo core \(installResult.version), and started."
        } else {
            status.message = "Imported profile and activated it."
        }
    }

    @discardableResult
    private func installManagedCoreIfNeeded() async throws -> CoreInstallResult? {
        let currentStatus = try controller.status()
        let candidates = try controller.coreCandidates()
        coreCandidates = candidates

        let managedCorePath = controller.paths.managedCoreExecutable.path
        let managedCoreInstalled = FileManager.default.isExecutableFile(atPath: managedCorePath)
        let shouldInstall = if currentStatus.corePath == nil {
            !managedCoreInstalled
        } else {
            candidates.isEmpty
        }

        guard shouldInstall else {
            return nil
        }

        isInstallingCore = true
        defer { isInstallingCore = false }

        let result = try await controller.installManagedCore()
        coreCandidates = try controller.coreCandidates()
        return result
    }

    private func beginLoading() {
        loadingTaskCount += 1
        isLoading = true
    }

    private func endLoading() {
        loadingTaskCount = max(0, loadingTaskCount - 1)
        isLoading = loadingTaskCount > 0
    }

    private func appendLog(_ log: LogEntry) {
        logs.append(log)
        if logs.count > 500 {
            logs.removeFirst(logs.count - 500)
        }
    }

    private func syncTrafficStreamWithStatus() {
        if status.state == .running {
            startTrafficStream()
        } else {
            stopTrafficStream()
        }
    }

    private func displayMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
