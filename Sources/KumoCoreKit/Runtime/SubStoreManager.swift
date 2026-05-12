import Foundation

public struct SubStoreLaunchPlan: Codable, Equatable, Sendable {
    public var backendCommand: ShellCommand?
    public var backendURL: URL?

    public init(backendCommand: ShellCommand? = nil, backendURL: URL? = nil) {
        self.backendCommand = backendCommand
        self.backendURL = backendURL
    }
}

public struct SubStoreManager: Sendable {
    private let paths: KumoPaths
    private let bundledResourceDirectory: URL?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(paths: KumoPaths = KumoPaths(), bundledResourceDirectory: URL? = nil) {
        self.paths = paths
        self.bundledResourceDirectory = bundledResourceDirectory
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func status() throws -> SubStoreStatus {
        guard FileManager.default.fileExists(atPath: statusFile.path) else {
            return SubStoreStatus()
        }
        let data = try Data(contentsOf: statusFile)
        return try decoder.decode(SubStoreStatus.self, from: data)
    }

    public func updateStatus(_ status: SubStoreStatus) throws {
        try paths.prepare()
        let data = try encoder.encode(status)
        try data.write(to: statusFile, options: .atomic)
    }

    @discardableResult
    public func prepareResources() throws -> SubStoreStatus {
        let sourceDirectory = try sourceResourceDirectory()
        let manifest = try manifest(in: sourceDirectory)

        try paths.prepare()
        try FileManager.default.removeItemIfExists(at: paths.subStoreResourcesDirectory)
        try FileManager.default.createDirectory(
            at: paths.subStoreResourcesDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.copyItem(at: sourceDirectory, to: paths.subStoreResourcesDirectory)

        let nodeURL = installedURL(for: manifest.nodeExecutableRelativePath)
        try validateInstalledResources(manifest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nodeURL.path)

        var nextStatus = try status()
        nextStatus.installedResourceVersion = manifest.version
        nextStatus.lastResourceInstallAt = Date()
        nextStatus.lastUpdatedAt = Date()
        nextStatus.localBackendPath = installedURL(for: manifest.backendBundleRelativePath).path
        nextStatus.lastError = nil
        try updateStatus(nextStatus)
        return nextStatus
    }

    public func backendURL(for status: SubStoreStatus) -> URL? {
        if status.usesCustomBackend {
            return status.customBackendURL
        }
        guard let backendPort = status.backendPort else {
            return nil
        }
        return URL(string: "http://\(backendBindHost(for: status)):\(backendPort)")
    }

    public func launchPlan(for status: SubStoreStatus, mixedPort: Int? = nil) throws -> SubStoreLaunchPlan {
        guard status.isEnabled, !status.usesCustomBackend else {
            return SubStoreLaunchPlan(backendURL: backendURL(for: status))
        }

        try validateInstalledResources(try installedManifest())
        guard let backendPort = status.backendPort else {
            throw KumoError.invalidArguments("Sub-Store backend port is not configured.")
        }

        let command = ShellCommand(
            executable: paths.subStoreNodeExecutable.path,
            arguments: [paths.subStoreBackendBundle.path],
            environment: backendEnvironment(for: status, backendPort: backendPort, mixedPort: mixedPort)
        )

        return SubStoreLaunchPlan(
            backendCommand: command,
            backendURL: backendURL(for: status)
        )
    }

    public func markEnabled(_ isEnabled: Bool) throws -> SubStoreStatus {
        var nextStatus = try status()
        nextStatus.isEnabled = isEnabled
        if isEnabled {
            nextStatus.backendPort = nextStatus.backendPort ?? 38324
            nextStatus.host = backendBindHost(for: nextStatus)
        }
        try updateStatus(nextStatus)
        return nextStatus
    }

    public func resourcesInstalled() -> Bool {
        guard let manifest = try? installedManifest() else {
            return false
        }
        return (try? validateInstalledResources(manifest)) != nil
    }

    private var statusFile: URL {
        paths.subStoreStatusFile
    }

    private func backendBindHost(for status: SubStoreStatus) -> String {
        status.allowsLAN ? "0.0.0.0" : "127.0.0.1"
    }

    private func sourceResourceDirectory() throws -> URL {
        if let bundledResourceDirectory {
            return bundledResourceDirectory
        }
        guard let resourceURL = Bundle.module.resourceURL else {
            throw KumoError.commandFailed("Sub-Store bundled resources were not found in KumoCoreKit.")
        }
        return resourceURL.appendingPathComponent("SubStore", isDirectory: true)
    }

    private func manifest(in directory: URL) throws -> SubStoreResourceManifest {
        let url = directory.appendingPathComponent("manifest.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode(SubStoreResourceManifest.self, from: data)
    }

    private func installedManifest() throws -> SubStoreResourceManifest {
        try manifest(in: paths.subStoreResourcesDirectory)
    }

    private func installedURL(for relativePath: String) -> URL {
        paths.subStoreResourcesDirectory.appendingPathComponent(relativePath)
    }

    private func validateInstalledResources(_ manifest: SubStoreResourceManifest) throws {
        let nodeURL = installedURL(for: manifest.nodeExecutableRelativePath)
        let backendURL = installedURL(for: manifest.backendBundleRelativePath)

        guard FileManager.default.fileExists(atPath: nodeURL.path) else {
            throw KumoError.commandFailed("Bundled Node executable is missing at \(nodeURL.path).")
        }
        guard FileManager.default.fileExists(atPath: backendURL.path) else {
            throw KumoError.commandFailed("Sub-Store backend bundle is missing at \(backendURL.path).")
        }
    }

    private func backendEnvironment(for status: SubStoreStatus, backendPort: Int, mixedPort: Int?) -> [String: String] {
        var environment = [
            "SUB_STORE_BACKEND_API_PORT": "\(backendPort)",
            "SUB_STORE_BACKEND_API_HOST": backendBindHost(for: status),
            "SUB_STORE_DATA_BASE_PATH": paths.subStoreDataDirectory.path,
            "SUB_STORE_BACKEND_CUSTOM_NAME": "Kumo",
            "SUB_STORE_BACKEND_SYNC_CRON": status.syncCron,
            "SUB_STORE_BACKEND_DOWNLOAD_CRON": status.downloadCron,
            "SUB_STORE_BACKEND_UPLOAD_CRON": status.uploadCron,
            "SUB_STORE_MMDB_COUNTRY_PATH": paths.workDirectory.appendingPathComponent("country.mmdb").path,
            "SUB_STORE_MMDB_ASN_PATH": paths.workDirectory.appendingPathComponent("ASN.mmdb").path
        ]

        if status.usesProxy, let mixedPort, mixedPort > 0 {
            let proxy = "http://127.0.0.1:\(mixedPort)"
            environment["HTTP_PROXY"] = proxy
            environment["HTTPS_PROXY"] = proxy
            environment["ALL_PROXY"] = proxy
        }

        return environment
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
