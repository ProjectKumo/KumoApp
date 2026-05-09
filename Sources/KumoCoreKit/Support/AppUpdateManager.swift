import Foundation

public enum AppUpdateChannel: String, Codable, CaseIterable, Sendable {
    case stable
    case beta
}

public struct AppUpdateManifest: Codable, Equatable, Sendable {
    public var version: String
    public var channel: AppUpdateChannel
    public var downloadURL: URL
    public var sha256: String?
    public var releaseNotes: String?

    public init(
        version: String,
        channel: AppUpdateChannel = .stable,
        downloadURL: URL,
        sha256: String? = nil,
        releaseNotes: String? = nil
    ) {
        self.version = version
        self.channel = channel
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.releaseNotes = releaseNotes
    }
}

public struct AppUpdateCheckResult: Codable, Equatable, Sendable {
    public var currentVersion: String
    public var update: AppUpdateManifest?

    public init(currentVersion: String, update: AppUpdateManifest?) {
        self.currentVersion = currentVersion
        self.update = update
    }
}

public struct AppUpdateManager: Sendable {
    public init() {}

    public func checkForUpdate(
        manifestURL: URL,
        currentVersion: String,
        channel: AppUpdateChannel = .stable
    ) async throws -> AppUpdateCheckResult {
        let (data, response) = try await URLSession.shared.data(from: manifestURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw KumoError.controllerResponse(httpResponse.statusCode, String(decoding: data, as: UTF8.self))
        }

        let manifest = try JSONDecoder().decode(AppUpdateManifest.self, from: data)
        guard manifest.channel == channel, manifest.version != currentVersion else {
            return AppUpdateCheckResult(currentVersion: currentVersion, update: nil)
        }

        return AppUpdateCheckResult(currentVersion: currentVersion, update: manifest)
    }
}
