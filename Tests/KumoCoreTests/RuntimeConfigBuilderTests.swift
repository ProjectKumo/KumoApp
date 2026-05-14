import XCTest
@testable import KumoCoreKit

final class RuntimeConfigBuilderTests: XCTestCase {
    func testBuildAppendsControlledRuntimeSettings() throws {
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

        let runtime = try builder.build(profile: profile)

        XCTAssertTrue(runtime.yaml.contains("external-controller: 127.0.0.1:19097"))
        XCTAssertTrue(runtime.yaml.contains("mixed-port: 17890"))
        XCTAssertTrue(runtime.yaml.contains("mode: global"))
        XCTAssertTrue(runtime.yaml.contains("secret: \"secret\""))
        XCTAssertTrue(runtime.yaml.contains("find-process-mode: always"))
    }

    func testBuildReplacesProfileRuntimeSettingsWithControlledSettings() throws {
        let profile = Profile(
            name: "Remote",
            source: .inline,
            rawYAML: """
            mixed-port: 7890
            allow-lan: true
            mode: rule
            log-level: debug
            find-process-mode: off
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

        let runtime = try builder.build(profile: profile)

        XCTAssertFalse(runtime.yaml.contains("mixed-port: 7890"))
        XCTAssertFalse(runtime.yaml.contains("allow-lan: true"))
        XCTAssertFalse(runtime.yaml.contains("mode: rule"))
        XCTAssertFalse(runtime.yaml.contains("log-level: debug"))
        XCTAssertFalse(runtime.yaml.contains("find-process-mode: off"))
        XCTAssertFalse(runtime.yaml.contains("external-controller: 127.0.0.1:9090"))
        XCTAssertFalse(runtime.yaml.contains("secret: \"remote-secret\""))
        XCTAssertTrue(runtime.yaml.contains("mixed-port: 17890"))
        XCTAssertTrue(runtime.yaml.contains("allow-lan: false"))
        XCTAssertTrue(runtime.yaml.contains("mode: global"))
        XCTAssertTrue(runtime.yaml.contains("log-level: info"))
        XCTAssertTrue(runtime.yaml.contains("find-process-mode: always"))
        XCTAssertTrue(runtime.yaml.contains("external-controller: 127.0.0.1:19097"))
        XCTAssertTrue(runtime.yaml.contains("secret: \"local-secret\""))
        XCTAssertTrue(runtime.yaml.contains("proxy-groups:"))
    }

    func testBuildIncludesRuntimeSettingsAndOverridesBeforeControlledKeys() throws {
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
            findProcessMode: "strict",
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

        let runtime = try builder.build(profile: profile, overrideYAMLs: ["proxy-groups: []"])

        XCTAssertTrue(runtime.yaml.contains("proxy-groups: []"))
        XCTAssertTrue(runtime.yaml.contains("mixed-port: 19090"))
        XCTAssertTrue(runtime.yaml.contains("allow-lan: true"))
        XCTAssertTrue(runtime.yaml.contains("log-level: debug"))
        XCTAssertTrue(runtime.yaml.contains("ipv6: true"))
        XCTAssertTrue(runtime.yaml.contains("find-process-mode: strict"))
        XCTAssertTrue(runtime.yaml.contains("geo-auto-update: true"))
        XCTAssertTrue(runtime.yaml.contains("geo-update-interval: 12"))
        XCTAssertFalse(runtime.yaml.contains("mixed-port: 7890"))
    }

    func testOverridesReplaceEarlierTopLevelBlocks() throws {
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

        let runtime = try builder.build(
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

    func testOverridesAppendAndPrependRulesWithSparkleOperators() throws {
        let profile = Profile(
            name: "Test",
            source: .inline,
            rawYAML: """
            rules:
              - DOMAIN-SUFFIX,base.example,Proxy
            """
        )
        let builder = RuntimeConfigBuilder()

        let runtime = try builder.build(
            profile: profile,
            overrideYAMLs: [
                """
                rules+:
                  - MATCH,DIRECT
                """,
                """
                +rules:
                  - DOMAIN-SUFFIX,first.example,DIRECT
                """
            ]
        )

        XCTAssertLineOrder(
            runtime.yaml,
            [
                "DOMAIN-SUFFIX,first.example,DIRECT",
                "DOMAIN-SUFFIX,base.example,Proxy",
                "MATCH,DIRECT"
            ]
        )
        XCTAssertFalse(runtime.yaml.contains("rules+:"))
        XCTAssertFalse(runtime.yaml.contains("+rules:"))
    }

    func testOverridesApplyVergeStyleRuleSequenceOperators() throws {
        let profile = Profile(
            name: "Test",
            source: .inline,
            rawYAML: """
            rules:
              - DOMAIN-SUFFIX,remove.example,Proxy
              - DOMAIN-SUFFIX,base.example,Proxy
            """
        )
        let builder = RuntimeConfigBuilder()

        let runtime = try builder.build(
            profile: profile,
            overrideYAMLs: [
                """
                prepend-rules:
                  - DOMAIN-SUFFIX,first.example,DIRECT
                append-rules:
                  - MATCH,DIRECT
                delete-rules:
                  - DOMAIN-SUFFIX,remove.example,Proxy
                """
            ]
        )

        XCTAssertLineOrder(
            runtime.yaml,
            [
                "DOMAIN-SUFFIX,first.example,DIRECT",
                "DOMAIN-SUFFIX,base.example,Proxy",
                "MATCH,DIRECT"
            ]
        )
        XCTAssertFalse(runtime.yaml.contains("remove.example"))
        XCTAssertFalse(runtime.yaml.contains("prepend-rules:"))
        XCTAssertFalse(runtime.yaml.contains("append-rules:"))
        XCTAssertFalse(runtime.yaml.contains("delete-rules:"))
    }

    func testOverridesDeepMergeNestedMappings() throws {
        let profile = Profile(
            name: "Test",
            source: .inline,
            rawYAML: """
            sniffer:
              enable: true
              sniff:
                HTTP:
                  ports:
                    - 80
            """
        )
        let builder = RuntimeConfigBuilder()

        let runtime = try builder.build(
            profile: profile,
            overrideYAMLs: [
                """
                sniffer:
                  sniff:
                    TLS:
                      ports:
                        - 443
                """
            ]
        )

        XCTAssertTrue(runtime.yaml.contains("enable: true"))
        XCTAssertTrue(runtime.yaml.contains("HTTP:"))
        XCTAssertTrue(runtime.yaml.contains("TLS:"))
        XCTAssertTrue(runtime.yaml.contains("- 80"))
        XCTAssertTrue(runtime.yaml.contains("- 443"))
    }

    func testBangOverrideReplacesNestedMapping() throws {
        let profile = Profile(
            name: "Test",
            source: .inline,
            rawYAML: """
            sniffer:
              enable: true
              sniff:
                HTTP:
                  ports:
                    - 80
            """
        )
        let builder = RuntimeConfigBuilder()

        let runtime = try builder.build(
            profile: profile,
            overrideYAMLs: [
                """
                sniffer!:
                  enable: false
                """
            ]
        )

        XCTAssertTrue(runtime.yaml.contains("enable: false"))
        XCTAssertFalse(runtime.yaml.contains("HTTP:"))
        XCTAssertFalse(runtime.yaml.contains("- 80"))
    }

    func testBuildInjectsControlledTunAndDNSWhenEnabled() throws {
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

        let runtime = try builder.build(profile: profile)

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

    func testBuildPreservesProfileTunWhenKumoTunIsDisabled() throws {
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

        let runtime = try builder.build(profile: profile)

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

    func testRuntimeSettingsDecodesMissingFindProcessModeWithDefault() throws {
        let data = Data(
            """
            {
              "mixedPort": 7890,
              "allowLAN": false,
              "logLevel": "info",
              "ipv6": false,
              "geoData": {
                "geoIPURL": "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geoip-lite.dat",
                "geoSiteURL": "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/geosite.dat",
                "mmdbURL": "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/country-lite.mmdb",
                "asnURL": "https://github.com/MetaCubeX/meta-rules-dat/releases/download/latest/GeoLite2-ASN.mmdb",
                "autoUpdate": false,
                "updateIntervalHours": 24,
                "usesDatMode": false
              }
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(CoreRuntimeSettings.self, from: data)

        XCTAssertEqual(settings.findProcessMode, "always")
    }

    private func XCTAssertLineOrder(
        _ yaml: String,
        _ fragments: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        var lowerBound = yaml.startIndex
        for fragment in fragments {
            guard let range = yaml.range(of: fragment, range: lowerBound..<yaml.endIndex) else {
                XCTFail("Missing or out-of-order fragment: \(fragment)", file: file, line: line)
                return
            }
            lowerBound = range.upperBound
        }
    }
}
