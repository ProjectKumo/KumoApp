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

    public var managedCoreDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("cores", isDirectory: true)
    }

    public var managedCoreExecutable: URL {
        managedCoreDirectory.appendingPathComponent("mihomo")
    }

    public var stateFile: URL {
        applicationSupportDirectory.appendingPathComponent("state.json")
    }

    public var runtimeConfigFile: URL {
        workDirectory.appendingPathComponent("config.yaml")
    }

    public var coreLogFile: URL {
        logsDirectory.appendingPathComponent("core.log")
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
            at: managedCoreDirectory,
            withIntermediateDirectories: true
        )
    }
}
