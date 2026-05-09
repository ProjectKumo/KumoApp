import XCTest
@testable import KumoCoreKit

final class SystemProxyControllerTests: XCTestCase {
    func testSystemProxyEnableCommandsUseMixedPort() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let controller = SystemProxyController(paths: paths)

        let commands = try controller.setEnabled(
            true,
            configuration: SystemProxyConfiguration(networkService: "Wi-Fi", host: "127.0.0.1", port: 17890),
            dryRun: true
        )

        XCTAssertEqual(commands.count, 3)
        XCTAssertTrue(commands.allSatisfy { $0.executable == "/usr/sbin/networksetup" })
        XCTAssertTrue(commands.contains { $0.arguments.contains("-setwebproxy") })
        XCTAssertTrue(commands.contains { $0.arguments.contains("17890") })
    }

    func testSystemProxyDisableCommandsTurnServicesOff() throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let controller = SystemProxyController(paths: paths)

        let commands = try controller.setEnabled(false, dryRun: true)

        XCTAssertEqual(commands.count, 3)
        XCTAssertTrue(commands.allSatisfy { $0.arguments.last == "off" })
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
