import XCTest
@testable import KumoCoreKit

final class SystemProxyControllerTests: XCTestCase {
    func testSystemProxyEnableCommandsUseMixedPort() async throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let controller = SystemProxyController(paths: paths)

        let commands = try await controller.setEnabled(
            true,
            configuration: SystemProxyConfiguration(networkService: "Wi-Fi", host: "127.0.0.1", port: 17890),
            dryRun: true
        )

        XCTAssertTrue(commands.allSatisfy { $0.executable == "/usr/sbin/networksetup" })
        XCTAssertTrue(commands.contains { $0.arguments.contains("-setwebproxy") })
        XCTAssertTrue(commands.contains { $0.arguments.contains("17890") })
        XCTAssertTrue(commands.contains { $0.arguments.contains("-setproxybypassdomains") })
        // Manual mode should also assert PAC mode is off.
        XCTAssertTrue(commands.contains { $0.arguments.contains("-setautoproxystate") })
    }

    func testSystemProxyDisableCommandsTurnServicesOff() async throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let controller = SystemProxyController(paths: paths)

        let commands = try await controller.setEnabled(false, dryRun: true)

        XCTAssertTrue(commands.allSatisfy { $0.arguments.last == "off" })
        XCTAssertTrue(commands.contains { $0.arguments.contains("-setwebproxystate") })
        XCTAssertTrue(commands.contains { $0.arguments.contains("-setautoproxystate") })
    }

    func testSystemProxyPACModeUsesAutoProxyURL() async throws {
        let paths = KumoPaths(applicationSupportDirectory: temporaryDirectory())
        let controller = SystemProxyController(paths: paths)

        let commands = try await controller.setEnabled(
            true,
            configuration: SystemProxyConfiguration(
                networkService: "Wi-Fi",
                host: "127.0.0.1",
                port: 17890,
                mode: .pac,
                pacScript: "function FindProxyForURL() { return 'DIRECT'; }"
            ),
            dryRun: true
        )

        XCTAssertTrue(commands.contains { $0.arguments.contains("-setautoproxyurl") })
        XCTAssertTrue(commands.contains { args in
            args.arguments.contains("-setautoproxystate") && args.arguments.last == "on"
        })
        // PAC mode should also turn manual proxies off.
        XCTAssertTrue(commands.contains { args in
            args.arguments.contains("-setwebproxystate") && args.arguments.last == "off"
        })
    }

    func testRenderPACScriptReplacesMixedPortPlaceholder() {
        let script = "return \"PROXY 127.0.0.1:%mixed-port%; SOCKS5 127.0.0.1:%mixed-port%; DIRECT;\";"

        let rendered = SystemProxyController.renderPACScript(script, port: 17890)

        XCTAssertFalse(rendered.contains("%mixed-port%"))
        XCTAssertTrue(rendered.contains("127.0.0.1:17890"))
    }

    func testNetworkServiceParserMatchesDefaultInterface() throws {
        let output = """
        An asterisk (*) denotes that a network service is disabled.
        (1) Thunderbolt Bridge
        (Hardware Port: Thunderbolt Bridge, Device: bridge0)

        (2) Wi-Fi
        (Hardware Port: Wi-Fi, Device: en0)
        """

        let service = try SystemProxyController.networkService(in: output, matchingDevice: "en0")

        XCTAssertEqual(service, "Wi-Fi")
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
