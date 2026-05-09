import Foundation
import Observation
import KumoCoreKit

@MainActor
@Observable
final class KumoAppStore {
    var status = CoreStatus()
    var proxyGroups: [ProxyGroup] = []
    var profiles: [ProfileSummary] = []
    var currentProfile: ProfileSummary?
    var coreConfiguration = CoreConfigurationSnapshot()
    var rules: [RuleEntry] = []
    var connections: [ConnectionEntry] = []
    var logs: [LogEntry] = []
    var coreCandidates: [CoreCandidate] = []
    var errorMessage: String?
    var isLoading = false
    var isImportingProfile = false
    var isInstallingCore = false
    var isTestingDelay = false

    private let controller = KumoController()
    private var loadingTaskCount = 0

    func refreshAll() async {
        refreshStatus()
        refreshProfiles()
        await refreshDueProfiles()
        refreshCoreCandidates()
        refreshProfiles()
        await loadProxyGroups()
        await loadCoreConfiguration()
        await loadInspectData()
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
    }

    func startCore() async {
        await performLoadingTask { [self] in
            let installResult = try await self.installManagedCoreIfNeeded()
            self.status = try self.controller.start()
            try await self.controller.waitForControllerReady()
            self.refreshProfiles()
            await self.loadProxyGroups()
            await self.loadCoreConfiguration()
            if let installResult {
                self.status.message = "Installed Mihomo core \(installResult.version) and started."
            }
        }
    }

    func stopCore() {
        do {
            status = try controller.stop()
            proxyGroups = []
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func setMode(_ mode: OutboundMode) async {
        await performLoadingTask { [self] in
            try await self.controller.setMode(mode)
            self.status.mode = mode
            self.coreConfiguration.mode = mode
        }
    }

    func loadProxyGroups() async {
        guard status.state == .running else {
            proxyGroups = []
            return
        }

        do {
            proxyGroups = try await controller.proxyGroups()
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
    }

    func loadCoreConfiguration() async {
        guard status.state == .running else {
            coreConfiguration = CoreConfigurationSnapshot(
                mode: status.mode,
                mixedPort: status.proxyPorts.mixedPort
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

        do {
            _ = try controller.setSystemProxy(isEnabled)
            status.systemProxyEnabled = isEnabled
            errorMessage = nil
        } catch {
            errorMessage = displayMessage(for: error)
        }
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

    private func displayMessage(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
