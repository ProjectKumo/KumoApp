import XCTest
@testable import KumoCoreKit

final class CoreStateStoreTests: XCTestCase {
    func testStateStorePersistsStatus() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let store = CoreStateStore(paths: paths)
        let status = CoreStatus(
            state: .running,
            pid: 42,
            mode: .direct,
            systemProxyEnabled: true,
            message: "ok"
        )

        try store.save(status)

        XCTAssertEqual(try store.load(), status)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
