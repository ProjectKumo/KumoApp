import XCTest
@testable import KumoCoreKit

final class AppUpdateManagerTests: XCTestCase {
    func testDefaultFeedURLsMatchGitHubReleaseChannels() {
        XCTAssertEqual(
            AppUpdateManager.defaultFeedURL(channel: .stable).absoluteString,
            "https://github.com/stvlynn/KumoApp/releases/latest/download/latest.yml"
        )
        XCTAssertEqual(
            AppUpdateManager.defaultFeedURL(channel: .beta).absoluteString,
            "https://github.com/stvlynn/KumoApp/releases/download/pre-release/latest.yml"
        )
    }

    func testDecodeYAMLManifest() throws {
        let yaml = """
        version: 0.0.2
        channel: stable
        downloadURL: https://github.com/stvlynn/KumoApp/releases/download/0.0.2/Kumo-macos-0.0.2-arm64.dmg
        assetName: Kumo-macos-0.0.2-arm64.dmg
        sha256: abc123
        releaseNotes: |
          First line
          Second line
        """

        let manifest = try AppUpdateManager.decodeManifest(Data(yaml.utf8))

        XCTAssertEqual(manifest.version, "0.0.2")
        XCTAssertEqual(manifest.channel, .stable)
        XCTAssertEqual(manifest.assetName, "Kumo-macos-0.0.2-arm64.dmg")
        XCTAssertEqual(manifest.sha256, "abc123")
        XCTAssertEqual(manifest.releaseNotes, "First line\nSecond line")
        XCTAssertTrue(manifest.canInstallAutomatically)
    }

    func testDecodeJSONManifest() throws {
        let json = """
        {
          "version": "0.0.3",
          "channel": "beta",
          "downloadURL": "https://example.com/Kumo.dmg",
          "sha256": "def456"
        }
        """

        let manifest = try AppUpdateManager.decodeManifest(Data(json.utf8))

        XCTAssertEqual(manifest.version, "0.0.3")
        XCTAssertEqual(manifest.channel, .beta)
        XCTAssertEqual(manifest.downloadURL.absoluteString, "https://example.com/Kumo.dmg")
        XCTAssertEqual(manifest.sha256, "def456")
    }

    func testSemanticVersionComparison() {
        XCTAssertEqual(AppUpdateManager.compareVersions("0.0.10", "0.0.2"), .orderedDescending)
        XCTAssertEqual(AppUpdateManager.compareVersions("v1.0.0", "1.0"), .orderedSame)
        XCTAssertEqual(AppUpdateManager.compareVersions("0.0.1", "0.0.2"), .orderedAscending)
    }

    func testSHA256Hex() throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try Data("kumo".utf8).write(to: fileURL)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        XCTAssertEqual(
            try AppUpdateManager.sha256Hex(for: fileURL),
            "2be7a151e93b9c2f5f1bb63e50c362e1f67b7ecf10267beb983517571b84d743"
        )
    }
}
