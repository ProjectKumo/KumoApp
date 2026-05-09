import XCTest
@testable import KumoCoreKit

final class RuntimeConfigBuilderTests: XCTestCase {
    func testBuildAppendsControlledRuntimeSettings() {
        let profile = Profile(
            name: "Test",
            source: .inline,
            rawYAML: """
            proxies: []
            rules:
              - MATCH,DIRECT
            """
        )
        let builder = RuntimeConfigBuilder(
            endpoint: ControllerEndpoint(port: 19097, secret: "secret"),
            proxyPorts: ProxyPortConfiguration(mixedPort: 17890),
            mode: .global
        )

        let runtime = builder.build(profile: profile)

        XCTAssertTrue(runtime.yaml.contains("external-controller: 127.0.0.1:19097"))
        XCTAssertTrue(runtime.yaml.contains("mixed-port: 17890"))
        XCTAssertTrue(runtime.yaml.contains("mode: global"))
        XCTAssertTrue(runtime.yaml.contains("secret: \"secret\""))
    }

    func testBuildReplacesProfileRuntimeSettingsWithControlledSettings() {
        let profile = Profile(
            name: "Remote",
            source: .inline,
            rawYAML: """
            mixed-port: 7890
            allow-lan: true
            mode: rule
            log-level: debug
            external-controller: 127.0.0.1:9090
            secret: "remote-secret"
            proxies: []
            proxy-groups:
              - name: Proxy
                type: select
                proxies:
                  - DIRECT
            rules:
              - MATCH,DIRECT
            """
        )
        let builder = RuntimeConfigBuilder(
            endpoint: ControllerEndpoint(port: 19097, secret: "local-secret"),
            proxyPorts: ProxyPortConfiguration(mixedPort: 17890),
            mode: .global
        )

        let runtime = builder.build(profile: profile)

        XCTAssertFalse(runtime.yaml.contains("mixed-port: 7890"))
        XCTAssertFalse(runtime.yaml.contains("allow-lan: true"))
        XCTAssertFalse(runtime.yaml.contains("mode: rule"))
        XCTAssertFalse(runtime.yaml.contains("log-level: debug"))
        XCTAssertFalse(runtime.yaml.contains("external-controller: 127.0.0.1:9090"))
        XCTAssertFalse(runtime.yaml.contains("secret: \"remote-secret\""))
        XCTAssertTrue(runtime.yaml.contains("mixed-port: 17890"))
        XCTAssertTrue(runtime.yaml.contains("allow-lan: false"))
        XCTAssertTrue(runtime.yaml.contains("mode: global"))
        XCTAssertTrue(runtime.yaml.contains("log-level: info"))
        XCTAssertTrue(runtime.yaml.contains("external-controller: 127.0.0.1:19097"))
        XCTAssertTrue(runtime.yaml.contains("secret: \"local-secret\""))
        XCTAssertTrue(runtime.yaml.contains("proxy-groups:"))
    }
}
