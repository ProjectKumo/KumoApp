import XCTest
@testable import KumoCoreKit

final class UserPreferencesTests: XCTestCase {
    func testDecodingLegacyPayloadDefaultsHasCompletedOnboardingToFalse() throws {
        let legacyJSON = """
        {
          "launchAtLogin": true,
          "hideMenuBarIcon": false,
          "quitOnLastWindowClose": true,
          "updateChannel": "beta",
          "updateManifestURL": null
        }
        """.data(using: .utf8)!

        let preferences = try JSONDecoder().decode(UserPreferences.self, from: legacyJSON)

        XCTAssertTrue(preferences.launchAtLogin)
        XCTAssertFalse(preferences.hideMenuBarIcon)
        XCTAssertTrue(preferences.quitOnLastWindowClose)
        XCTAssertEqual(preferences.updateChannel, .beta)
        XCTAssertNil(preferences.updateManifestURL)
        XCTAssertFalse(preferences.hasCompletedOnboarding)
    }

    func testEncodingRoundTripPreservesHasCompletedOnboarding() throws {
        var preferences = UserPreferences()
        preferences.hasCompletedOnboarding = true

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(UserPreferences.self, from: data)

        XCTAssertTrue(decoded.hasCompletedOnboarding)
    }

    func testStoreSavesAndLoadsHasCompletedOnboarding() throws {
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: scratch)
        }

        let store = UserPreferencesStore(paths: KumoPaths(applicationSupportDirectory: scratch))
        var preferences = store.load()
        XCTAssertFalse(preferences.hasCompletedOnboarding)

        preferences.hasCompletedOnboarding = true
        try store.save(preferences)

        let reloaded = store.load()
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }
}
