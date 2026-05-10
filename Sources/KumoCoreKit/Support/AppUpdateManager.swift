import CryptoKit
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
    public var assetName: String?
    public var minimumSystemVersion: String?

    public init(
        version: String,
        channel: AppUpdateChannel = .stable,
        downloadURL: URL,
        sha256: String? = nil,
        releaseNotes: String? = nil,
        assetName: String? = nil,
        minimumSystemVersion: String? = nil
    ) {
        self.version = version
        self.channel = channel
        self.downloadURL = downloadURL
        self.sha256 = sha256
        self.releaseNotes = releaseNotes
        self.assetName = assetName
        self.minimumSystemVersion = minimumSystemVersion
    }

    public var canInstallAutomatically: Bool {
        downloadURL.pathExtension.localizedCaseInsensitiveCompare("dmg") == .orderedSame
            && sha256?.isEmpty == false
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

public struct AppUpdateDownloadResult: Equatable, Sendable {
    public var manifest: AppUpdateManifest
    public var fileURL: URL
    public var sha256: String

    public init(manifest: AppUpdateManifest, fileURL: URL, sha256: String) {
        self.manifest = manifest
        self.fileURL = fileURL
        self.sha256 = sha256
    }
}

public struct AppUpdateManager: Sendable {
    public static let defaultRepository = "stvlynn/KumoApp"

    public init() {}

    public static func defaultFeedURL(
        channel: AppUpdateChannel,
        repository: String = defaultRepository
    ) -> URL {
        switch channel {
        case .stable:
            URL(string: "https://github.com/\(repository)/releases/latest/download/latest.yml")!
        case .beta:
            URL(string: "https://github.com/\(repository)/releases/download/pre-release/latest.yml")!
        }
    }

    public func checkForUpdate(
        manifestURL: URL?,
        currentVersion: String,
        channel: AppUpdateChannel = .stable
    ) async throws -> AppUpdateCheckResult {
        let feedURL = manifestURL ?? Self.defaultFeedURL(channel: channel)
        let (data, response) = try await URLSession.shared.data(from: feedURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw KumoError.controllerResponse(httpResponse.statusCode, String(decoding: data, as: UTF8.self))
        }

        let manifest = try Self.decodeManifest(data)
        guard manifest.channel == channel,
              Self.compareVersions(manifest.version, currentVersion) == .orderedDescending else {
            return AppUpdateCheckResult(currentVersion: currentVersion, update: nil)
        }

        return AppUpdateCheckResult(currentVersion: currentVersion, update: manifest)
    }

    public func downloadUpdate(
        manifest: AppUpdateManifest,
        to directory: URL,
        progress: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> AppUpdateDownloadResult {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(downloadFileName(for: manifest))
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }

        let temporaryURL = try await DownloadDelegate.download(from: manifest.downloadURL, progress: progress)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)

        guard let expectedSHA256 = manifest.sha256?.trimmingCharacters(in: .whitespacesAndNewlines),
              !expectedSHA256.isEmpty else {
            throw KumoError.invalidArguments("The update manifest does not include a SHA-256 checksum.")
        }

        let actualSHA256 = try Self.sha256Hex(for: destination)
        guard actualSHA256.localizedCaseInsensitiveCompare(expectedSHA256) == .orderedSame else {
            try? FileManager.default.removeItem(at: destination)
            throw KumoError.invalidArguments("Update checksum mismatch. Expected \(expectedSHA256), got \(actualSHA256).")
        }

        progress(1)
        return AppUpdateDownloadResult(manifest: manifest, fileURL: destination, sha256: actualSHA256)
    }

    public static func decodeManifest(_ data: Data) throws -> AppUpdateManifest {
        if let manifest = try? JSONDecoder().decode(AppUpdateManifest.self, from: data) {
            return manifest
        }
        return try decodeYAMLManifest(String(decoding: data, as: UTF8.self))
    }

    public static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }
        return .orderedSame
    }

    public static func sha256Hex(for fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func downloadFileName(for manifest: AppUpdateManifest) -> String {
        if let assetName = manifest.assetName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !assetName.isEmpty {
            return assetName
        }
        let lastPathComponent = manifest.downloadURL.lastPathComponent
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }
        return "Kumo-macos-\(manifest.version)-arm64.dmg"
    }

    private static func decodeYAMLManifest(_ yaml: String) throws -> AppUpdateManifest {
        let values = parseTopLevelYAML(yaml)
        guard let version = values["version"], !version.isEmpty else {
            throw KumoError.invalidArguments("Update manifest is missing version.")
        }
        guard let rawDownloadURL = values["downloadURL"] ?? values["downloadUrl"] ?? values["download_url"],
              let downloadURL = URL(string: rawDownloadURL) else {
            throw KumoError.invalidArguments("Update manifest is missing a valid downloadURL.")
        }
        let channel = AppUpdateChannel(rawValue: values["channel"] ?? "") ?? .stable
        return AppUpdateManifest(
            version: version,
            channel: channel,
            downloadURL: downloadURL,
            sha256: values["sha256"],
            releaseNotes: values["releaseNotes"] ?? values["release_notes"],
            assetName: values["assetName"] ?? values["asset_name"],
            minimumSystemVersion: values["minimumSystemVersion"] ?? values["minimum_system_version"]
        )
    }

    private static func parseTopLevelYAML(_ yaml: String) -> [String: String] {
        var values: [String: String] = [:]
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var index = 0

        while index < lines.count {
            let line = lines[index]
            index += 1
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty,
                  !line.trimmingCharacters(in: .whitespaces).hasPrefix("#"),
                  !line.hasPrefix(" "),
                  !line.hasPrefix("\t"),
                  let separator = line.firstIndex(of: ":") else {
                continue
            }

            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value == "|" || value == ">" {
                var block: [String] = []
                while index < lines.count {
                    let blockLine = lines[index]
                    guard blockLine.hasPrefix(" ") || blockLine.hasPrefix("\t") || blockLine.isEmpty else {
                        break
                    }
                    block.append(blockLine.trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                value = block.joined(separator: value == ">" ? " " : "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            }
            values[key] = unquote(value)
        }

        return values
    }

    private static func unquote(_ value: String) -> String {
        guard value.count >= 2 else { return value }
        if (value.hasPrefix("\"") && value.hasSuffix("\""))
            || (value.hasPrefix("'") && value.hasSuffix("'")) {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version
            .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
            .split { character in
                character == "." || character == "-" || character == "+"
            }
            .map { component in
                let numericPrefix = component.prefix { $0.isNumber }
                return Int(numericPrefix) ?? 0
            }
    }
}

private final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var didResume = false

    private init(progress: @escaping @Sendable (Double) -> Void) {
        self.progress = progress
    }

    static func download(
        from url: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let delegate = DownloadDelegate(progress: progress)
        let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.start(session.downloadTask(with: url), continuation: continuation)
        }
    }

    private func start(_ task: URLSessionDownloadTask, continuation: CheckedContinuation<URL, Error>) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
        task.resume()
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(min(0.99, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(location.pathExtension)
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            resume(.success(destination))
        } catch {
            resume(.failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        if let error {
            resume(.failure(error))
        }
    }

    private func resume(_ result: Result<URL, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume, let continuation else { return }
        didResume = true
        self.continuation = nil
        continuation.resume(with: result)
    }
}
