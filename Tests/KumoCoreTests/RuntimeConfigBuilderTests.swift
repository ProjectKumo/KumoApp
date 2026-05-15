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
            port: 47890
            socks-port: 47891
            redir-port: 47892
            tproxy-port: 47893
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

        XCTAssertFalse(runtime.yaml.contains("port: 47890"))
        XCTAssertFalse(runtime.yaml.contains("socks-port: 47891"))
        XCTAssertFalse(runtime.yaml.contains("redir-port: 47892"))
        XCTAssertFalse(runtime.yaml.contains("tproxy-port: 47893"))
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
                device: "utun9"
            ),
            dns: DnsSettings(
                isEnabled: true,
                nameserver: ["https://example.com/dns-query"]
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
              "mtu": 1500
            }
            """.utf8
        )

        let settings = try JSONDecoder().decode(TunSettings.self, from: data)

        XCTAssertTrue(settings.isEnabled)
        XCTAssertFalse(settings.autoRedirect)
        XCTAssertFalse(settings.disableICMPForwarding)
        XCTAssertEqual(settings.dnsHijack, ["any:53"])
    }

    func testBuildInjectsFullDnsSettingsWhenEnabled() throws {
        let profile = Profile(
            name: "Test",
            source: .inline,
            rawYAML: """
            rules:
              - MATCH,DIRECT
            """
        )
        let settings = CoreRuntimeSettings(
            mixedPort: 19090,
            dns: DnsSettings(
                isEnabled: true,
                listen: "0.0.0.0:53",
                ipv6: true,
                ipv6Timeout: 200,
                preferH3: true,
                enhancedMode: "fake-ip",
                fakeIPRange: "198.18.0.1/16",
                fakeIPRange6: "fc00::/18",
                fakeIPFilter: ["+.lan"],
                fakeIPFilterMode: "blacklist",
                useHosts: true,
                useSystemHosts: true,
                respectRules: true,
                defaultNameserver: ["223.5.5.5"],
                nameserver: ["https://doh.pub/dns-query"],
                fallback: ["https://1.1.1.1/dns-query"],
                fallbackFilter: ["geoip": .bool(true), "geoip-code": .single("CN"), "ipcidr": .multiple(["100.100.100.100/32"])],
                proxyServerNameserver: ["https://dns.alidns.com/dns-query"],
                directNameserver: ["https://dns.alidns.com/dns-query"],
                directNameserverFollowPolicy: true,
                nameserverPolicy: ["geosite:cn": .single("223.5.5.5")],
                proxyServerNameserverPolicy: ["geosite:cn": .single("https://dns.alidns.com/dns-query")],
                cacheAlgorithm: "arc",
                hosts: ["localhost": .single("127.0.0.1")]
            ),
            sniffer: SnifferSettings(
                isEnabled: true,
                httpOverrideDestination: true,
                httpPorts: [80, 8080],
                tlsPorts: [443, 8443],
                quicPorts: [443]
            )
        )
        let builder = RuntimeConfigBuilder(runtimeSettings: settings)

        let runtime = try builder.build(profile: profile)

        // DNS assertions
        XCTAssertTrue(runtime.yaml.contains("dns:\n  enable: true"))
        XCTAssertTrue(runtime.yaml.contains("listen: \"0.0.0.0:53\""))
        XCTAssertTrue(runtime.yaml.contains("ipv6: true"))
        XCTAssertTrue(runtime.yaml.contains("ipv6-timeout: 200"))
        XCTAssertTrue(runtime.yaml.contains("prefer-h3: true"))
        XCTAssertTrue(runtime.yaml.contains("fake-ip-filter-mode: blacklist"))
        XCTAssertTrue(runtime.yaml.contains("use-hosts: true"))
        XCTAssertTrue(runtime.yaml.contains("use-system-hosts: true"))
        XCTAssertTrue(runtime.yaml.contains("respect-rules: true"))
        XCTAssertTrue(runtime.yaml.contains("fallback:\n    - \"https://1.1.1.1/dns-query\""))
        XCTAssertTrue(runtime.yaml.contains("fallback-filter:\n    geoip: true\n    geoip-code: \"CN\"\n    ipcidr:\n      - \"100.100.100.100/32\""))
        XCTAssertTrue(runtime.yaml.contains("direct-nameserver-follow-policy: true"))
        XCTAssertTrue(runtime.yaml.contains("nameserver-policy:\n    geosite:cn: \"223.5.5.5\""))
        XCTAssertTrue(runtime.yaml.contains("proxy-server-nameserver-policy:\n    geosite:cn: \"https://dns.alidns.com/dns-query\""))
        XCTAssertTrue(runtime.yaml.contains("cache-algorithm: arc"))
        XCTAssertTrue(runtime.yaml.contains("hosts:\n  localhost: \"127.0.0.1\""))

        // Sniffer assertions
        XCTAssertTrue(runtime.yaml.contains("sniffer:\n  enable: true"))
        XCTAssertTrue(runtime.yaml.contains("sniff:"))
        XCTAssertTrue(runtime.yaml.contains("HTTP:"))
        XCTAssertTrue(runtime.yaml.contains("override-destination: true"))
        XCTAssertTrue(runtime.yaml.contains("- 80"))
        XCTAssertTrue(runtime.yaml.contains("- 8080"))
        XCTAssertTrue(runtime.yaml.contains("TLS:"))
        XCTAssertTrue(runtime.yaml.contains("- 443"))
        XCTAssertTrue(runtime.yaml.contains("- 8443"))
        XCTAssertTrue(runtime.yaml.contains("QUIC:"))
        XCTAssertTrue(runtime.yaml.contains("- 443"))
    }

    func testSnifferHTTPOverrideDestinationWithoutPorts() throws {
        let profile = Profile(
            name: "Test",
            source: .inline,
            rawYAML: """
            rules:
              - MATCH,DIRECT
            """
        )
        let settings = CoreRuntimeSettings(
            sniffer: SnifferSettings(
                isEnabled: true,
                httpOverrideDestination: true,
                httpPorts: [],
                tlsPorts: [443]
            )
        )
        let builder = RuntimeConfigBuilder(runtimeSettings: settings)

        let runtime = try builder.build(profile: profile)

        XCTAssertTrue(runtime.yaml.contains("sniff:"))
        XCTAssertTrue(runtime.yaml.contains("HTTP:"))
        XCTAssertTrue(runtime.yaml.contains("override-destination: true"))
        XCTAssertFalse(runtime.yaml.contains("HTTP:\n      ports:"))
        XCTAssertTrue(runtime.yaml.contains("TLS:\n      ports:"))
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
