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

    func testBuildIncludesRuntimeSettingsAndOverridesBeforeControlledKeys() {
        let profile = Profile(
            name: "Test",
            source: .inline,
            rawYAML: """
            mixed-port: 7890
            rules:
              - MATCH,DIRECT
            """
        )
        let settings = CoreRuntimeSettings(
            mixedPort: 19090,
            allowLAN: true,
            logLevel: "debug",
            ipv6: true,
            geoData: GeoDataSettings(
                geoIPURL: "https://example.com/geoip.dat",
                geoSiteURL: "https://example.com/geosite.dat",
                mmdbURL: "https://example.com/mmdb",
                asnURL: "https://example.com/asn",
                autoUpdate: true,
                updateIntervalHours: 12,
                usesDatMode: true
            )
        )
        let builder = RuntimeConfigBuilder(runtimeSettings: settings)

        let runtime = builder.build(profile: profile, overrideYAMLs: ["proxy-groups: []"])

        XCTAssertTrue(runtime.yaml.contains("proxy-groups: []"))
        XCTAssertTrue(runtime.yaml.contains("mixed-port: 19090"))
        XCTAssertTrue(runtime.yaml.contains("allow-lan: true"))
        XCTAssertTrue(runtime.yaml.contains("log-level: debug"))
        XCTAssertTrue(runtime.yaml.contains("ipv6: true"))
        XCTAssertTrue(runtime.yaml.contains("geo-auto-update: true"))
        XCTAssertTrue(runtime.yaml.contains("geo-update-interval: 12"))
        XCTAssertFalse(runtime.yaml.contains("mixed-port: 7890"))
    }

    func testOverridesReplaceEarlierTopLevelBlocks() {
        let profile = Profile(
            name: "Test",
            source: .inline,
            rawYAML: """
            proxies:
              - name: old
                type: direct
            rules:
              - MATCH,DIRECT
            """
        )
        let builder = RuntimeConfigBuilder()

        let runtime = builder.build(
            profile: profile,
            overrideYAMLs: [
                """
                proxies:
                  - name: replacement
                    type: direct
                """
            ]
        )

        XCTAssertFalse(runtime.yaml.contains("name: old"))
        XCTAssertTrue(runtime.yaml.contains("name: replacement"))
        XCTAssertTrue(runtime.yaml.contains("rules:"))
    }

    func testBuildInjectsControlledTunAndDNSWhenEnabled() {
        let profile = Profile(
            name: "Test",
            source: .inline,
            rawYAML: """
            tun:
              enable: false
            dns:
              enable: false
            rules:
              - MATCH,DIRECT
            """
        )
        let settings = CoreRuntimeSettings(
            mixedPort: 19090,
            tun: TunSettings(
                isEnabled: true,
                stack: "mixed",
                disableICMPForwarding: true,
                dnsHijack: ["any:53"],
                routeExcludeAddress: ["100.64.0.0/10"],
                device: "utun9",
                nameservers: ["https://example.com/dns-query"]
            )
        )
        let builder = RuntimeConfigBuilder(runtimeSettings: settings)

        let runtime = builder.build(profile: profile)

        XCTAssertTrue(runtime.yaml.contains("tun:\n  enable: true"))
        XCTAssertTrue(runtime.yaml.contains("stack: mixed"))
        XCTAssertTrue(runtime.yaml.contains("disable-icmp-forwarding: true"))
        XCTAssertTrue(runtime.yaml.contains("dns-hijack:\n    - \"any:53\""))
        XCTAssertTrue(runtime.yaml.contains("route-exclude-address:\n    - 100.64.0.0/10"))
        XCTAssertTrue(runtime.yaml.contains("device: utun9"))
        XCTAssertTrue(runtime.yaml.contains("dns:\n  enable: true"))
        XCTAssertTrue(runtime.yaml.contains("nameserver:\n    - \"https://example.com/dns-query\""))
        XCTAssertFalse(runtime.yaml.contains("tun:\n  enable: false"))
    }

    func testBuildPreservesProfileTunWhenKumoTunIsDisabled() {
        let profile = Profile(
            name: "Test",
            source: .inline,
            rawYAML: """
            tun:
              enable: true
            rules:
              - MATCH,DIRECT
            """
        )
        let builder = RuntimeConfigBuilder(runtimeSettings: CoreRuntimeSettings(tun: TunSettings(isEnabled: false)))

        let runtime = builder.build(profile: profile)

        XCTAssertTrue(runtime.yaml.contains("tun:\n  enable: true"))
    }

    func testTunSettingsDecodesMissingNewFieldsWithDefaults() throws {
        let data = Data(
            """
            {
              "isEnabled": true,
              "stack": "mixed",
              "autoRoute": true,
              "autoDetectInterface": true,
              "strictRoute": false,
              "dnsHijack": ["any:53"],
              "routeExcludeAddress": [],
              "mtu": 1500,
              "dnsEnabled": true,
              "dnsEnhancedMode": "fake-ip",
              "fakeIPRange": "198.18.0.1/16",
              "nameservers": ["https://doh.pub/dns-query"]
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(TunSettings.self, from: data)

        XCTAssertTrue(settings.isEnabled)
        XCTAssertFalse(settings.autoRedirect)
        XCTAssertFalse(settings.disableICMPForwarding)
        XCTAssertEqual(settings.nameservers, ["https://doh.pub/dns-query"])
    }
}
