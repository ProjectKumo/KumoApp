import XCTest
@testable import KumoCoreKit

final class TunServiceModeTests: XCTestCase {
    func testSetTunEnabledFailsAndRollsBackWhenServiceUnavailable() async throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let controller = KumoController(paths: paths)

        do {
            _ = try await controller.setTunEnabled(true)
            XCTFail("Expected TUN enable to require service mode.")
        } catch KumoError.serviceUnavailable {
            let status = try controller.status()
            XCTAssertFalse(status.runtimeSettings?.tun?.isEnabled ?? false)
            XCTAssertTrue(status.tunStatus?.requiresService ?? false)
            XCTAssertNotNil(status.tunStatus?.lastError)
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
