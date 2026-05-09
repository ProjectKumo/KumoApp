import Foundation

public struct KumoBackupManifest: Codable, Equatable, Sendable {
    public var formatVersion: Int
    public var createdAt: Date
    public var appName: String

    public init(formatVersion: Int = 1, createdAt: Date = Date(), appName: String = "Kumo") {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.appName = appName
    }
}

public struct KumoBackupResult: Codable, Equatable, Sendable {
    public var destinationPath: String
    public var manifest: KumoBackupManifest

    public init(destinationPath: String, manifest: KumoBackupManifest) {
        self.destinationPath = destinationPath
        self.manifest = manifest
    }
}

public struct KumoBackupManager: Sendable {
    private let paths: KumoPaths

    public init(paths: KumoPaths = KumoPaths()) {
        self.paths = paths
    }

    @discardableResult
    public func exportBackup(to destination: URL) throws -> KumoBackupResult {
        try paths.prepare()
        try prepareEmptyDirectory(destination)

        let manifest = KumoBackupManifest()
        try makeEncoder().encode(manifest).write(to: manifestURL(in: destination), options: .atomic)

        try copyIfPresent(paths.profilesDirectory, to: destination.appendingPathComponent("profiles", isDirectory: true))
        try copyIfPresent(paths.overridesDirectory, to: destination.appendingPathComponent("overrides", isDirectory: true))
        try copyIfPresent(paths.subStoreDirectory, to: destination.appendingPathComponent("substore", isDirectory: true))
        try copyIfPresent(paths.stateFile, to: destination.appendingPathComponent("state.json"))

        return KumoBackupResult(destinationPath: destination.path, manifest: manifest)
    }

    @discardableResult
    public func importBackup(from source: URL) throws -> KumoBackupManifest {
        let manifest = try makeDecoder().decode(KumoBackupManifest.self, from: Data(contentsOf: manifestURL(in: source)))
        guard manifest.formatVersion == 1 else {
            throw KumoError.invalidArguments("Unsupported backup format version \(manifest.formatVersion).")
        }

        try paths.prepare()
        try replaceIfPresent(source.appendingPathComponent("profiles", isDirectory: true), with: paths.profilesDirectory)
        try replaceIfPresent(source.appendingPathComponent("overrides", isDirectory: true), with: paths.overridesDirectory)
        try replaceIfPresent(source.appendingPathComponent("substore", isDirectory: true), with: paths.subStoreDirectory)
        try replaceIfPresent(source.appendingPathComponent("state.json"), with: paths.stateFile)
        return manifest
    }

    private func manifestURL(in directory: URL) -> URL {
        directory.appendingPathComponent("manifest.json")
    }

    private func prepareEmptyDirectory(_ directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func copyIfPresent(_ source: URL, to destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            return
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func replaceIfPresent(_ source: URL, with destination: URL) throws {
        guard FileManager.default.fileExists(atPath: source.path) else {
            return
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.copyItem(at: source, to: destination)
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
