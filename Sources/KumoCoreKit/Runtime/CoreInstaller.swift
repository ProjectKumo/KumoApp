import Darwin
import Foundation

public struct CoreInstallResult: Codable, Equatable, Sendable {
    public var version: String
    public var path: String

    public init(version: String, path: String) {
        self.version = version
        self.path = path
    }
}

public struct CoreInstaller: Sendable {
    private let paths: KumoPaths
    private let releasesURL = URL(string: "https://api.github.com/repos/MetaCubeX/mihomo/releases/latest")!

    public init(paths: KumoPaths = KumoPaths()) {
        self.paths = paths
    }

    public func installLatestMihomo() async throws -> CoreInstallResult {
        let release = try await latestRelease()
        let asset = try assetForCurrentMac(in: release)
        let archiveURL = try await download(asset: asset)

        try paths.prepare()
        let installedURL = try installGzipArchive(archiveURL)
        return CoreInstallResult(version: release.tagName, path: installedURL.path)
    }

    private func latestRelease() async throws -> GitHubRelease {
        let (data, response) = try await URLSession.shared.data(from: releasesURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw KumoError.coreInstallFailed("GitHub returned HTTP \(httpResponse.statusCode).")
        }
        return try JSONDecoder().decode(GitHubRelease.self, from: data)
    }

    private func assetForCurrentMac(in release: GitHubRelease) throws -> GitHubAsset {
        let architecture = currentArchitecture
        let candidates = release.assets
            .filter { asset in
                let name = asset.name.lowercased()
                return name.hasSuffix(".gz")
                    && name.contains("mihomo-darwin-\(architecture)")
                    && !name.contains("metacubexd")
            }
            .sorted { lhs, rhs in
                assetScore(lhs.name) > assetScore(rhs.name)
            }

        guard let asset = candidates.first else {
            throw KumoError.coreInstallFailed("No macOS \(architecture) mihomo asset found in \(release.tagName).")
        }
        return asset
    }

    private var currentArchitecture: String {
        #if arch(arm64)
        "arm64"
        #else
        "amd64"
        #endif
    }

    private func assetScore(_ name: String) -> Int {
        let lowercased = name.lowercased()
        var score = 0
        if !lowercased.contains("compatible") {
            score += 10
        }
        if !lowercased.contains("go120") {
            score += 5
        }
        return score
    }

    private func download(asset: GitHubAsset) async throws -> URL {
        let (temporaryURL, response) = try await URLSession.shared.download(from: asset.browserDownloadURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw KumoError.coreInstallFailed("Asset download returned HTTP \(httpResponse.statusCode).")
        }

        let fileManager = FileManager.default
        let destination = fileManager.temporaryDirectory
            .appendingPathComponent("kumo-\(UUID().uuidString)")
            .appendingPathExtension("gz")
        try fileManager.moveItem(at: temporaryURL, to: destination)
        return destination
    }

    private func installGzipArchive(_ archiveURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let installingURL = paths.managedCoreDirectory.appendingPathComponent("mihomo.installing")
        let destinationURL = paths.managedCoreExecutable

        try? fileManager.removeItem(at: installingURL)
        fileManager.createFile(atPath: installingURL.path, contents: nil)

        let output = try FileHandle(forWritingTo: installingURL)
        defer {
            try? output.close()
            try? fileManager.removeItem(at: archiveURL)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/gunzip")
        process.arguments = ["-c", archiveURL.path]
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = (process.standardError as? Pipe)
                .flatMap { String(data: $0.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) }
                ?? "gunzip failed with status \(process.terminationStatus)."
            throw KumoError.coreInstallFailed(message)
        }

        try? fileManager.removeItem(at: destinationURL)
        try fileManager.moveItem(at: installingURL, to: destinationURL)
        chmod(destinationURL.path, S_IRUSR | S_IWUSR | S_IXUSR | S_IRGRP | S_IXGRP | S_IROTH | S_IXOTH)
        return destinationURL
    }
}

private struct GitHubRelease: Decodable {
    var tagName: String
    var assets: [GitHubAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case assets
    }
}

private struct GitHubAsset: Decodable {
    var name: String
    var browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}
