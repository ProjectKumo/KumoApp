import Foundation

public struct KumoPaths: Sendable {
    public var applicationSupportDirectory: URL

    public init(applicationSupportDirectory: URL? = nil) {
        if let applicationSupportDirectory {
            self.applicationSupportDirectory = applicationSupportDirectory
        } else {
            let baseDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.applicationSupportDirectory = baseDirectory.appendingPathComponent("Kumo", isDirectory: true)
        }
    }

    public var profilesDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("profiles", isDirectory: true)
    }

    public var workDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("work", isDirectory: true)
    }

    public var logsDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("logs", isDirectory: true)
    }

    public var overridesDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("overrides", isDirectory: true)
    }

    public var overrideFilesDirectory: URL {
        overridesDirectory.appendingPathComponent("files", isDirectory: true)
    }

    public var subStoreDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("substore", isDirectory: true)
    }

    public var subStoreStatusFile: URL {
        subStoreDirectory.appendingPathComponent("status.json")
    }

    public var subStoreResourcesDirectory: URL {
        subStoreDirectory.appendingPathComponent("resources", isDirectory: true)
    }

    public var subStoreResourceManifestFile: URL {
        subStoreResourcesDirectory.appendingPathComponent("manifest.json")
    }

    public var subStoreNodeExecutable: URL {
        subStoreResourcesDirectory.appendingPathComponent("node/bin/node")
    }

    public var subStoreBackendBundle: URL {
        subStoreResourcesDirectory.appendingPathComponent("backend/sub-store.bundle.js")
    }

    public var subStoreDataDirectory: URL {
        subStoreDirectory.appendingPathComponent("data", isDirectory: true)
    }

    public var subStoreTempDirectory: URL {
        subStoreDirectory.appendingPathComponent("temp", isDirectory: true)
    }

    public var appUpdatesDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("updates", isDirectory: true)
    }

    public var appUpdateDownloadsDirectory: URL {
        appUpdatesDirectory.appendingPathComponent("downloads", isDirectory: true)
    }

    public var appUpdateInstallerLogFile: URL {
        logsDirectory.appendingPathComponent("app-update-installer.log")
    }

    public var managedCoreDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("cores", isDirectory: true)
    }

    public var managedCoreExecutable: URL {
        managedCoreDirectory.appendingPathComponent("mihomo")
    }

    public var stateFile: URL {
        applicationSupportDirectory.appendingPathComponent("state.json")
    }

    public var agentSkillsStateFile: URL {
        applicationSupportDirectory.appendingPathComponent("agent-skills-state.json")
    }

    public var runtimeConfigFile: URL {
        workDirectory.appendingPathComponent("config.yaml")
    }

    public var coreLogFile: URL {
        logsDirectory.appendingPathComponent("core.log")
    }

    public var runtimeEventsFile: URL {
        logsDirectory.appendingPathComponent("runtime-events.jsonl")
    }

    public var serviceSocketFile: URL {
        applicationSupportDirectory.appendingPathComponent("kumo-service.sock")
    }

    public var serviceStatusFile: URL {
        applicationSupportDirectory.appendingPathComponent("service-status.json")
    }

    public var serviceCredentialsFile: URL {
        applicationSupportDirectory.appendingPathComponent("service-credentials.json")
    }

    public var serviceLogFile: URL {
        logsDirectory.appendingPathComponent("kumo-service.log")
    }

    public var serviceExecutableFile: URL {
        URL(fileURLWithPath: "/Library/PrivilegedHelperTools/io.kumo.KumoService")
    }

    public var serviceLaunchDaemonPlistFile: URL {
        URL(fileURLWithPath: "/Library/LaunchDaemons/io.kumo.KumoService.plist")
    }

    public var subStoreLogFile: URL {
        logsDirectory.appendingPathComponent("substore.log")
    }

    public var overridesMetadataFile: URL {
        overridesDirectory.appendingPathComponent("overrides.json")
    }

    public func prepare() throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: profilesDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: workDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: overridesDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: overrideFilesDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: subStoreDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: subStoreDataDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: subStoreTempDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: appUpdatesDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: appUpdateDownloadsDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: managedCoreDirectory,
            withIntermediateDirectories: true
        )
    }
}
