import Foundation

public struct SubStoreLaunchPlan: Codable, Equatable, Sendable {
    public var backendCommand: ShellCommand?
    public var frontendURL: URL?

    public init(backendCommand: ShellCommand? = nil, frontendURL: URL? = nil) {
        self.backendCommand = backendCommand
        self.frontendURL = frontendURL
    }
}

public struct SubStoreManager: Sendable {
    private let paths: KumoPaths
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(paths: KumoPaths = KumoPaths()) {
        self.paths = paths
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

    public func webURL(for status: SubStoreStatus) -> URL? {
        if status.usesCustomBackend {
            return status.customBackendURL
        }
        guard let frontendPort = status.frontendPort,
              let backendPort = status.backendPort else {
            return nil
        }
        return URL(string: "http://127.0.0.1:\(frontendPort)?api=http://127.0.0.1:\(backendPort)")
    }

    public func launchPlan(for status: SubStoreStatus) -> SubStoreLaunchPlan {
        let frontendURL = webURL(for: status)
        guard status.isEnabled,
              !status.usesCustomBackend,
              let backendPath = status.localBackendPath,
              let backendPort = status.backendPort else {
            return SubStoreLaunchPlan(frontendURL: frontendURL)
        }

        return SubStoreLaunchPlan(
            backendCommand: ShellCommand(
                executable: backendPath,
                arguments: ["--port", "\(backendPort)"]
            ),
            frontendURL: frontendURL
        )
    }

    public func markEnabled(_ isEnabled: Bool) throws -> SubStoreStatus {
        var nextStatus = try status()
        nextStatus.isEnabled = isEnabled
        if isEnabled {
            nextStatus.backendPort = nextStatus.backendPort ?? 38324
            nextStatus.frontendPort = nextStatus.frontendPort ?? 38323
        }
        try updateStatus(nextStatus)
        return nextStatus
    }

    @discardableResult
    public func downloadBundle(kind: SubStoreBundleKind, from url: URL) async throws -> SubStoreStatus {
        try paths.prepare()
        let (temporaryURL, _) = try await URLSession.shared.download(from: url)
        let destination = bundleURL(for: kind, sourceURL: url)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        var nextStatus = try status()
        switch kind {
        case .frontend:
            nextStatus.frontendDownloadURL = url
            nextStatus.localFrontendPath = destination.path
            nextStatus.frontendPort = nextStatus.frontendPort ?? 38323
        case .backend:
            nextStatus.backendDownloadURL = url
            nextStatus.localBackendPath = destination.path
            nextStatus.backendPort = nextStatus.backendPort ?? 38324
        }
        nextStatus.lastUpdatedAt = Date()
        try updateStatus(nextStatus)
        return nextStatus
    }

    private var statusFile: URL {
        paths.subStoreDirectory.appendingPathComponent("status.json")
    }

    private func bundleURL(for kind: SubStoreBundleKind, sourceURL: URL) -> URL {
        let fileName = sourceURL.lastPathComponent.isEmpty ? "\(kind.rawValue).bundle" : sourceURL.lastPathComponent
        return paths.subStoreDirectory
            .appendingPathComponent(kind.rawValue, isDirectory: true)
            .appendingPathComponent(fileName)
    }
}
