import Foundation
import Yams

public struct RuntimeConfig: Equatable, Sendable {
    public var yaml: String
    public var endpoint: ControllerEndpoint
    public var proxyPorts: ProxyPortConfiguration
}

public struct RuntimeConfigBuilder: Sendable {
    private static let controlledTopLevelKeys: Set<String> = [
        "external-controller",
        "secret",
        "port",
        "socks-port",
        "redir-port",
        "tproxy-port",
        "mixed-port",
        "mode",
        "allow-lan",
        "log-level",
        "ipv6",
        "find-process-mode",
        "geodata-mode",
        "geo-auto-update",
        "geo-update-interval",
        "geox-url"
    ]

    public var endpoint: ControllerEndpoint
    public var proxyPorts: ProxyPortConfiguration
    public var mode: OutboundMode
    public var runtimeSettings: CoreRuntimeSettings

    public init(
        endpoint: ControllerEndpoint = ControllerEndpoint(),
        proxyPorts: ProxyPortConfiguration = ProxyPortConfiguration(),
        mode: OutboundMode = .rule,
        runtimeSettings: CoreRuntimeSettings = CoreRuntimeSettings()
    ) {
        var effectiveRuntimeSettings = runtimeSettings
        if effectiveRuntimeSettings.mixedPort == CoreRuntimeSettings().mixedPort {
            effectiveRuntimeSettings.mixedPort = proxyPorts.mixedPort
        }
        self.endpoint = endpoint
        self.proxyPorts = ProxyPortConfiguration(mixedPort: effectiveRuntimeSettings.mixedPort)
        self.mode = mode
        self.runtimeSettings = effectiveRuntimeSettings
    }

    public func build(profile: Profile, overrideYAMLs: [String] = []) throws -> RuntimeConfig {
        let yaml = try mergedRuntimeYAML(profileYAML: profile.rawYAML, overrideYAMLs: overrideYAMLs)

        return RuntimeConfig(yaml: yaml, endpoint: endpoint, proxyPorts: proxyPorts)
    }

    public func write(profile: Profile, overrideYAMLs: [String] = [], to url: URL) throws -> RuntimeConfig {
        let config = try build(profile: profile, overrideYAMLs: overrideYAMLs)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try config.yaml.data(using: .utf8)?.write(to: url, options: .atomic)
        return config
    }

    private func mergedRuntimeYAML(profileYAML: String, overrideYAMLs: [String]) throws -> String {
        var document = try StructuredYAMLDocument(rawYAML: profileYAML)

        for overrideYAML in overrideYAMLs {
            try document.merge(StructuredYAMLDocument(rawYAML: overrideYAML))
        }

        document.removeTopLevelKeys(controlledTopLevelKeys())

        return [
            try document.renderedYAML(),
            controlledConfigYAML()
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    private func controlledConfigYAML() -> String {
        let base = """
        # Kumo controlled runtime settings
        external-controller: \(endpoint.host):\(endpoint.port)
        secret: "\(escaped(endpoint.secret))"
        mixed-port: \(runtimeSettings.mixedPort)
        mode: \(mode.rawValue)
        allow-lan: \(runtimeSettings.allowLAN ? "true" : "false")
        log-level: \(runtimeSettings.logLevel)
        ipv6: \(runtimeSettings.ipv6 ? "true" : "false")
        find-process-mode: \(runtimeSettings.findProcessMode)
        geodata-mode: \(runtimeSettings.geoData.usesDatMode ? "true" : "false")
        geo-auto-update: \(runtimeSettings.geoData.autoUpdate ? "true" : "false")
        geo-update-interval: \(runtimeSettings.geoData.updateIntervalHours)
        geox-url:
          geoip: "\(escaped(runtimeSettings.geoData.geoIPURL))"
          geosite: "\(escaped(runtimeSettings.geoData.geoSiteURL))"
          mmdb: "\(escaped(runtimeSettings.geoData.mmdbURL))"
          asn: "\(escaped(runtimeSettings.geoData.asnURL))"
        """

        var blocks: [String] = [base]

        if let tun = runtimeSettings.tun, tun.isEnabled {
            blocks.append(controlledTunYAML(tun))
        }

        if let dns = runtimeSettings.dns, dns.isEnabled {
            blocks.append(controlledDnsYAML(dns))
        }

        if let sniffer = runtimeSettings.sniffer, sniffer.isEnabled {
            blocks.append(controlledSnifferYAML(sniffer))
        }

        if let dns = runtimeSettings.dns, !dns.hosts.isEmpty {
            blocks.append(controlledHostsYAML(dns.hosts))
        }

        return blocks.joined(separator: "\n\n")
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func controlledTopLevelKeys() -> Set<String> {
        var keys = Self.controlledTopLevelKeys
        if runtimeSettings.tun?.isEnabled == true {
            keys.insert("tun")
        }
        if runtimeSettings.dns?.isEnabled == true {
            keys.insert("dns")
        }
        if runtimeSettings.sniffer?.isEnabled == true {
            keys.insert("sniffer")
        }
        if let dns = runtimeSettings.dns, !dns.hosts.isEmpty {
            keys.insert("hosts")
        }
        return keys
    }

    private func controlledTunYAML(_ tun: TunSettings) -> String {
        var lines = [
            "# Kumo controlled TUN settings",
            "tun:",
            "  enable: true",
            "  stack: \(tun.stack)",
            "  auto-route: \(tun.autoRoute ? "true" : "false")",
            "  auto-redirect: \(tun.autoRedirect ? "true" : "false")",
            "  auto-detect-interface: \(tun.autoDetectInterface ? "true" : "false")",
            "  strict-route: \(tun.strictRoute ? "true" : "false")",
            "  disable-icmp-forwarding: \(tun.disableICMPForwarding ? "true" : "false")",
            "  dns-hijack:",
        ]
        lines.append(contentsOf: yamlList(tun.dnsHijack, indent: "    "))
        if !tun.routeExcludeAddress.isEmpty {
            lines.append("  route-exclude-address:")
            lines.append(contentsOf: yamlList(tun.routeExcludeAddress, indent: "    "))
        }
        lines.append("  mtu: \(tun.mtu)")
        if let device = normalizedTunDevice(tun.device) {
            lines.append("  device: \(device)")
        }
        return lines.joined(separator: "\n")
    }

    private func controlledDnsYAML(_ dns: DnsSettings) -> String {
        var lines = [
            "# Kumo controlled DNS settings",
            "dns:",
            "  enable: \(dns.isEnabled ? "true" : "false")",
            "  ipv6: \(dns.ipv6 ? "true" : "false")",
            "  enhanced-mode: \(dns.enhancedMode)",
            "  fake-ip-range: \(dns.fakeIPRange)",
        ]
        if !dns.listen.isEmpty {
            lines.append("  listen: \(escapedScalar(dns.listen))")
        }
        lines.append("  ipv6-timeout: \(dns.ipv6Timeout)")
        lines.append("  prefer-h3: \(dns.preferH3 ? "true" : "false")")
        if !dns.fakeIPRange6.isEmpty {
            lines.append("  fake-ip-range6: \(dns.fakeIPRange6)")
        }
        if !dns.fakeIPFilter.isEmpty {
            lines.append("  fake-ip-filter:")
            lines.append(contentsOf: yamlList(dns.fakeIPFilter, indent: "    "))
        }
        if !dns.fakeIPFilterMode.isEmpty {
            lines.append("  fake-ip-filter-mode: \(dns.fakeIPFilterMode)")
        }
        lines.append("  use-hosts: \(dns.useHosts ? "true" : "false")")
        lines.append("  use-system-hosts: \(dns.useSystemHosts ? "true" : "false")")
        lines.append("  respect-rules: \(dns.respectRules ? "true" : "false")")
        if !dns.defaultNameserver.isEmpty {
            lines.append("  default-nameserver:")
            lines.append(contentsOf: yamlList(dns.defaultNameserver, indent: "    "))
        }
        if !dns.nameserver.isEmpty {
            lines.append("  nameserver:")
            lines.append(contentsOf: yamlList(dns.nameserver, indent: "    "))
        }
        if !dns.fallback.isEmpty {
            lines.append("  fallback:")
            lines.append(contentsOf: yamlList(dns.fallback, indent: "    "))
        }
        if !dns.fallbackFilter.isEmpty {
            lines.append("  fallback-filter:")
            lines.append(contentsOf: yamlFallbackFilterDict(dns.fallbackFilter, indent: "    "))
        }
        if !dns.proxyServerNameserver.isEmpty {
            lines.append("  proxy-server-nameserver:")
            lines.append(contentsOf: yamlList(dns.proxyServerNameserver, indent: "    "))
        }
        if !dns.directNameserver.isEmpty {
            lines.append("  direct-nameserver:")
            lines.append(contentsOf: yamlList(dns.directNameserver, indent: "    "))
        }
        lines.append("  direct-nameserver-follow-policy: \(dns.directNameserverFollowPolicy ? "true" : "false")")
        if !dns.nameserverPolicy.isEmpty {
            lines.append("  nameserver-policy:")
            lines.append(contentsOf: yamlPolicyDict(dns.nameserverPolicy, indent: "    "))
        }
        if !dns.proxyServerNameserverPolicy.isEmpty {
            lines.append("  proxy-server-nameserver-policy:")
            lines.append(contentsOf: yamlPolicyDict(dns.proxyServerNameserverPolicy, indent: "    "))
        }
        if !dns.cacheAlgorithm.isEmpty {
            lines.append("  cache-algorithm: \(dns.cacheAlgorithm)")
        }
        return lines.joined(separator: "\n")
    }

    private func controlledHostsYAML(_ hosts: [String: PolicyValue]) -> String {
        var lines = [
            "# Kumo controlled hosts",
            "hosts:"
        ]
        lines.append(contentsOf: yamlPolicyDict(hosts, indent: "  "))
        return lines.joined(separator: "\n")
    }

    private func controlledSnifferYAML(_ sniffer: SnifferSettings) -> String {
        var lines = [
            "# Kumo controlled Sniffer settings",
            "sniffer:",
            "  enable: \(sniffer.isEnabled ? "true" : "false")",
            "  parse-pure-ip: \(sniffer.parsePureIP ? "true" : "false")",
            "  force-dns-mapping: \(sniffer.forceDNSMapping ? "true" : "false")",
            "  override-destination: \(sniffer.overrideDestination ? "true" : "false")",
        ]
        if !sniffer.httpPorts.isEmpty || !sniffer.tlsPorts.isEmpty || !sniffer.quicPorts.isEmpty || sniffer.httpOverrideDestination {
            lines.append("  sniff:")
            if !sniffer.httpPorts.isEmpty || sniffer.httpOverrideDestination {
                lines.append("    HTTP:")
                if !sniffer.httpPorts.isEmpty {
                    lines.append("      ports:")
                    lines.append(contentsOf: sniffer.httpPorts.map { "        - \($0)" })
                }
                if sniffer.httpOverrideDestination {
                    lines.append("      override-destination: true")
                }
            }
            if !sniffer.tlsPorts.isEmpty {
                lines.append("    TLS:")
                lines.append("      ports:")
                lines.append(contentsOf: sniffer.tlsPorts.map { "        - \($0)" })
            }
            if !sniffer.quicPorts.isEmpty {
                lines.append("    QUIC:")
                lines.append("      ports:")
                lines.append(contentsOf: sniffer.quicPorts.map { "        - \($0)" })
            }
        }
        if !sniffer.skipDomain.isEmpty {
            lines.append("  skip-domain:")
            lines.append(contentsOf: yamlList(sniffer.skipDomain, indent: "    "))
        }
        if !sniffer.forceDomain.isEmpty {
            lines.append("  force-domain:")
            lines.append(contentsOf: yamlList(sniffer.forceDomain, indent: "    "))
        }
        if !sniffer.skipDstAddress.isEmpty {
            lines.append("  skip-dst-address:")
            lines.append(contentsOf: yamlList(sniffer.skipDstAddress, indent: "    "))
        }
        if !sniffer.skipSrcAddress.isEmpty {
            lines.append("  skip-src-address:")
            lines.append(contentsOf: yamlList(sniffer.skipSrcAddress, indent: "    "))
        }
        return lines.joined(separator: "\n")
    }

    private func yamlList(_ values: [String], indent: String) -> [String] {
        values.map { "\(indent)- \(escapedScalar($0))" }
    }

    private func yamlPolicyDict(_ dict: [String: PolicyValue], indent: String) -> [String] {
        dict.sorted(by: { $0.key < $1.key }).flatMap { key, value -> [String] in
            switch value {
            case .single(let s):
                return ["\(indent)\(key): \(quotedScalar(s))"]
            case .multiple(let arr):
                if arr.isEmpty {
                    return ["\(indent)\(key): []"]
                }
                return ["\(indent)\(key):"] + arr.map { "\(indent)  - \(quotedScalar($0))" }
            }
        }
    }

    private func yamlFallbackFilterDict(_ dict: [String: FallbackFilterValue], indent: String) -> [String] {
        dict.sorted(by: { $0.key < $1.key }).flatMap { key, value -> [String] in
            switch value {
            case .bool(let b):
                return ["\(indent)\(key): \(b ? "true" : "false")"]
            case .single(let s):
                return ["\(indent)\(key): \(quotedScalar(s))"]
            case .multiple(let arr):
                if arr.isEmpty {
                    return ["\(indent)\(key): []"]
                }
                return ["\(indent)\(key):"] + arr.map { "\(indent)  - \(quotedScalar($0))" }
            }
        }
    }

    private func quotedScalar(_ value: String) -> String {
        "\"\(escaped(value))\""
    }

    private func escapedScalar(_ value: String) -> String {
        guard value.rangeOfCharacter(from: CharacterSet(charactersIn: ":#{}[]&,*?|-<>=!%@`\"'")) != nil else {
            return value
        }
        return "\"\(escaped(value))\""
    }

    private func normalizedTunDevice(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        #if os(macOS)
        return value.hasPrefix("utun") ? value : nil
        #else
        return value
        #endif
    }
}

private struct StructuredYAMLDocument {
    private var mapping: [String: Any]

    init(rawYAML: String) throws {
        let trimmed = rawYAML.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            self.mapping = [:]
            return
        }

        guard let loaded = try Yams.load(yaml: rawYAML) else {
            self.mapping = [:]
            return
        }

        self.mapping = loaded as? [String: Any] ?? [:]
    }

    mutating func merge(_ override: StructuredYAMLDocument) {
        mapping.mergeRuntimeOverride(override.mapping)
    }

    mutating func removeTopLevelKeys(_ keys: Set<String>) {
        for key in keys {
            mapping.removeValue(forKey: key)
        }
    }

    func renderedYAML() throws -> String {
        guard !mapping.isEmpty else {
            return ""
        }

        return try Yams.dump(object: mapping)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension Dictionary where Key == String, Value == Any {
    mutating func mergeRuntimeOverride(_ override: [String: Any]) {
        for (rawKey, overrideValue) in override {
            if applySequenceOperator(rawKey: rawKey, overrideValue: overrideValue) {
                continue
            }

            let key = Self.unwrappedKey(rawKey)
            if rawKey.hasSuffix("!") {
                self[key] = overrideValue
                continue
            }

            if var current = self[key] as? [String: Any],
               let nestedOverride = overrideValue as? [String: Any] {
                current.mergeRuntimeOverride(nestedOverride)
                self[key] = current
            } else {
                self[key] = overrideValue
            }
        }
    }

    private mutating func applySequenceOperator(rawKey: String, overrideValue: Any) -> Bool {
        if rawKey.hasPrefix("+"), let values = overrideValue as? [Any] {
            prepend(values, to: Self.unwrappedKey(String(rawKey.dropFirst())))
            return true
        }

        if rawKey.hasSuffix("+"), let values = overrideValue as? [Any] {
            append(values, to: Self.unwrappedKey(String(rawKey.dropLast())))
            return true
        }

        if rawKey.hasPrefix("prepend-"), let values = overrideValue as? [Any] {
            prepend(values, to: String(rawKey.dropFirst("prepend-".count)))
            return true
        }

        if rawKey.hasPrefix("append-"), let values = overrideValue as? [Any] {
            append(values, to: String(rawKey.dropFirst("append-".count)))
            return true
        }

        if rawKey.hasPrefix("delete-"), let values = overrideValue as? [Any] {
            delete(values, from: String(rawKey.dropFirst("delete-".count)))
            return true
        }

        return false
    }

    private mutating func prepend(_ values: [Any], to key: String) {
        let existing = self[key] as? [Any] ?? []
        self[key] = values + existing
    }

    private mutating func append(_ values: [Any], to key: String) {
        let existing = self[key] as? [Any] ?? []
        self[key] = existing + values
    }

    private mutating func delete(_ values: [Any], from key: String) {
        let namesToDelete = Set(values.compactMap(Self.sequenceItemName))
        guard !namesToDelete.isEmpty else {
            return
        }

        let existing = self[key] as? [Any] ?? []
        self[key] = existing.filter { item in
            guard let name = Self.sequenceItemName(item) else {
                return true
            }
            return !namesToDelete.contains(name)
        }
    }

    private static func sequenceItemName(_ value: Any) -> String? {
        if let value = value as? String {
            return value
        }
        if let mapping = value as? [String: Any],
           let name = mapping["name"] as? String {
            return name
        }
        return nil
    }

    private static func unwrappedKey(_ key: String) -> String {
        let key = key.hasSuffix("!") ? String(key.dropLast()) : key
        guard key.hasPrefix("<"), key.hasSuffix(">") else {
            return key
        }
        return String(key.dropFirst().dropLast())
    }
}
