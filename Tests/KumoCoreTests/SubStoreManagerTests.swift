import XCTest
@testable import KumoCoreKit

final class SubStoreManagerTests: XCTestCase {
    func testSubStoreStatusPersistsAndBuildsLocalURL() throws {
        let manager = SubStoreManager(paths: KumoPaths(applicationSupportDirectory: temporaryDirectory()))

        let enabled = try manager.markEnabled(true)
        let url = manager.webURL(for: enabled)

        XCTAssertTrue(enabled.isEnabled)
        XCTAssertEqual(enabled.backendPort, 38324)
        XCTAssertEqual(enabled.frontendPort, 38323)
        XCTAssertEqual(url?.absoluteString, "http://127.0.0.1:38323?api=http://127.0.0.1:38324")
    }

    func testCustomBackendURLIsPreferred() throws {
        let manager = SubStoreManager(paths: KumoPaths(applicationSupportDirectory: temporaryDirectory()))
        let status = SubStoreStatus(
            isEnabled: true,
            usesCustomBackend: true,
            customBackendURL: URL(string: "https://sub.example.com")
        )

        XCTAssertEqual(manager.webURL(for: status), URL(string: "https://sub.example.com"))
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
