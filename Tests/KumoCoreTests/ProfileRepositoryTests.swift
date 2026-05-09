import XCTest
@testable import KumoCoreKit

final class ProfileRepositoryTests: XCTestCase {
    func testProfileCRUDPersistsMetadataAndFallsBackAfterDelete() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let repository = ProfileRepository(paths: paths)
        let remoteURL = try XCTUnwrap(URL(string: "https://example.com/sub.yaml"))
        let profile = Profile(
            name: "Example Remote",
            source: .remote(remoteURL),
            rawYAML: "proxies: []",
            updatedAt: Date()
        )

        let saved = try repository.saveProfile(profile, preferredID: "example")

        XCTAssertEqual(saved.kind, .remote)
        XCTAssertEqual(saved.remoteURL, remoteURL)
        XCTAssertTrue(saved.isCurrent)

        let updated = try repository.updateProfile(
            id: saved.id,
            name: "Renamed",
            remoteURL: remoteURL,
            autoUpdate: false,
            useProxy: true,
            rawYAML: "proxies:\n  - name: direct\n"
        )

        XCTAssertEqual(updated.name, "Renamed")
        XCTAssertEqual(updated.kind, .remote)
        XCTAssertFalse(updated.autoUpdate)
        XCTAssertTrue(updated.useProxy)
        XCTAssertEqual(try repository.profileContent(id: saved.id), "proxies:\n  - name: direct\n")

        let deletedCurrentProfile = try repository.deleteProfile(id: saved.id)

        XCTAssertTrue(deletedCurrentProfile)
        XCTAssertEqual(try repository.currentProfileSummary().id, "default")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
