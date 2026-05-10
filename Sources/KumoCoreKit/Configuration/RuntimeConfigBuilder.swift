import Foundation

public struct RuntimeConfig: Equatable, Sendable {
    public var yaml: String
    public var endpoint: ControllerEndpoint
    public var proxyPorts: ProxyPortConfiguration
}

public struct RuntimeConfigBuilder: Sendable {
    private static let controlledTopLevelKeys: Set<String> = [
        "external-controller",
        "secret",
        "mixed-port",
        "mode",
        "allow-lan",
        "log-level",
        "ipv6",
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

    public func build(profile: Profile, overrideYAMLs: [String] = []) -> RuntimeConfig {
        let yaml = mergedRuntimeYAML(profileYAML: profile.rawYAML, overrideYAMLs: overrideYAMLs)

        return RuntimeConfig(yaml: yaml, endpoint: endpoint, proxyPorts: proxyPorts)
    }

    public func write(profile: Profile, overrideYAMLs: [String] = [], to url: URL) throws -> RuntimeConfig {
        let config = build(profile: profile, overrideYAMLs: overrideYAMLs)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try config.yaml.data(using: .utf8)?.write(to: url, options: .atomic)
        return config
    }

    private func mergedRuntimeYAML(profileYAML: String, overrideYAMLs: [String]) -> String {
        var document = TopLevelYAMLDocument(rawYAML: profileYAML)

        for overrideYAML in overrideYAMLs {
            document.merge(TopLevelYAMLDocument(rawYAML: overrideYAML))
        }

        document.removeTopLevelKeys(controlledTopLevelKeys())

        return [
            document.renderedYAML(),
            controlledConfigYAML()
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    fileprivate static func topLevelKey(in line: String) -> String? {
        guard !line.isEmpty, line == line.trimmingPrefix(while: \.isWhitespace) else {
            return nil
        }

        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard !trimmedLine.hasPrefix("#"),
              let separatorIndex = trimmedLine.firstIndex(of: ":") else {
            return nil
        }

        let key = String(trimmedLine[..<separatorIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
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
        geodata-mode: \(runtimeSettings.geoData.usesDatMode ? "true" : "false")
        geo-auto-update: \(runtimeSettings.geoData.autoUpdate ? "true" : "false")
        geo-update-interval: \(runtimeSettings.geoData.updateIntervalHours)
        geox-url:
          geoip: "\(escaped(runtimeSettings.geoData.geoIPURL))"
          geosite: "\(escaped(runtimeSettings.geoData.geoSiteURL))"
          mmdb: "\(escaped(runtimeSettings.geoData.mmdbURL))"
          asn: "\(escaped(runtimeSettings.geoData.asnURL))"
        """

        guard let tun = runtimeSettings.tun, tun.isEnabled else {
            return base
        }

        return [base, controlledTunYAML(tun)].joined(separator: "\n\n")
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func controlledTopLevelKeys() -> Set<String> {
        guard runtimeSettings.tun?.isEnabled == true else {
            return Self.controlledTopLevelKeys
        }
        return Self.controlledTopLevelKeys.union(["tun", "dns"])
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
        lines.append(contentsOf: [
            "dns:",
            "  enable: \(tun.dnsEnabled ? "true" : "false")",
            "  ipv6: \(runtimeSettings.ipv6 ? "true" : "false")",
            "  enhanced-mode: \(tun.dnsEnhancedMode)",
            "  fake-ip-range: \(tun.fakeIPRange)",
            "  nameserver:"
        ])
        lines.append(contentsOf: yamlList(tun.nameservers, indent: "    "))
        return lines.joined(separator: "\n")
    }

    private func yamlList(_ values: [String], indent: String) -> [String] {
        values.map { "\(indent)- \(escapedScalar($0))" }
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

private struct TopLevelYAMLDocument {
    fileprivate struct Block {
        var key: String?
        var lines: [String]
    }

    private var blocks: [Block]

    init(rawYAML: String) {
        self.blocks = Self.parse(rawYAML)
    }

    mutating func merge(_ override: TopLevelYAMLDocument) {
        for block in override.blocks where !block.isEmpty {
            guard let key = block.key,
                  let index = blocks.firstIndex(where: { $0.key == key }) else {
                blocks.append(block)
                continue
            }

            blocks[index] = block
        }
    }

    mutating func removeTopLevelKeys(_ keys: Set<String>) {
        blocks.removeAll { block in
            guard let key = block.key else {
                return false
            }
            return keys.contains(key)
        }
    }

    func renderedYAML() -> String {
        blocks
            .filter { !$0.isEmpty }
            .map { $0.rendered }
            .joined(separator: "\n\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parse(_ rawYAML: String) -> [Block] {
        var blocks: [Block] = []
        var currentBlock: Block?

        func finishCurrentBlock() {
            guard let block = currentBlock, !block.isEmpty else {
                currentBlock = nil
                return
            }
            blocks.append(block)
            currentBlock = nil
        }

        for line in rawYAML.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if let key = RuntimeConfigBuilder.topLevelKey(in: line) {
                finishCurrentBlock()
                currentBlock = Block(key: key, lines: [line])
                continue
            }

            if currentBlock == nil {
                currentBlock = Block(key: nil, lines: [])
            }

            currentBlock?.lines.append(line)
        }

        finishCurrentBlock()
        return blocks
    }
}

private extension TopLevelYAMLDocument.Block {
    var isEmpty: Bool {
        lines.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    var rendered: String {
        lines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
