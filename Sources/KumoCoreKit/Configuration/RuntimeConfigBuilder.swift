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
        "log-level"
    ]

    public var endpoint: ControllerEndpoint
    public var proxyPorts: ProxyPortConfiguration
    public var mode: OutboundMode

    public init(
        endpoint: ControllerEndpoint = ControllerEndpoint(),
        proxyPorts: ProxyPortConfiguration = ProxyPortConfiguration(),
        mode: OutboundMode = .rule
    ) {
        self.endpoint = endpoint
        self.proxyPorts = proxyPorts
        self.mode = mode
    }

    public func build(profile: Profile) -> RuntimeConfig {
        let yaml = [
            normalizedProfileYAML(profile.rawYAML),
            controlledConfigYAML()
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")

        return RuntimeConfig(yaml: yaml, endpoint: endpoint, proxyPorts: proxyPorts)
    }

    public func write(profile: Profile, to url: URL) throws -> RuntimeConfig {
        let config = build(profile: profile)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try config.yaml.data(using: .utf8)?.write(to: url, options: .atomic)
        return config
    }

    private func normalizedProfileYAML(_ rawYAML: String) -> String {
        rawYAML
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                !isControlledTopLevelSetting(String(line))
            }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isControlledTopLevelSetting(_ line: String) -> Bool {
        guard !line.isEmpty, line == line.trimmingPrefix(while: \.isWhitespace) else {
            return false
        }

        let trimmedLine = line.trimmingCharacters(in: .whitespaces)
        guard !trimmedLine.hasPrefix("#"),
              let separatorIndex = trimmedLine.firstIndex(of: ":") else {
            return false
        }

        let key = String(trimmedLine[..<separatorIndex])
        return Self.controlledTopLevelKeys.contains(key)
    }

    private func controlledConfigYAML() -> String {
        """
        # Kumo controlled runtime settings
        external-controller: \(endpoint.host):\(endpoint.port)
        secret: "\(escaped(endpoint.secret))"
        mixed-port: \(proxyPorts.mixedPort)
        mode: \(mode.rawValue)
        allow-lan: false
        log-level: info
        """
    }

    private func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}
