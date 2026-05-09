import Foundation

public struct ShellCommand: Codable, Equatable, Sendable {
    public var executable: String
    public var arguments: [String]

    public init(executable: String, arguments: [String]) {
        self.executable = executable
        self.arguments = arguments
    }
}

public struct SystemProxyConfiguration: Codable, Equatable, Sendable {
    public var networkService: String
    public var host: String
    public var port: Int

    public init(networkService: String = "Wi-Fi", host: String = "127.0.0.1", port: Int = 7890) {
        self.networkService = networkService
        self.host = host
        self.port = port
    }
}

public struct SystemProxyController: Sendable {
    private let stateStore: CoreStateStore

    public init(paths: KumoPaths = KumoPaths()) {
        self.stateStore = CoreStateStore(paths: paths)
    }

    public func enableCommands(configuration: SystemProxyConfiguration) -> [ShellCommand] {
        [
            ShellCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setwebproxy", configuration.networkService, configuration.host, "\(configuration.port)"]
            ),
            ShellCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setsecurewebproxy", configuration.networkService, configuration.host, "\(configuration.port)"]
            ),
            ShellCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setsocksfirewallproxy", configuration.networkService, configuration.host, "\(configuration.port)"]
            )
        ]
    }

    public func disableCommands(networkService: String = "Wi-Fi") -> [ShellCommand] {
        [
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-setwebproxystate", networkService, "off"]),
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-setsecurewebproxystate", networkService, "off"]),
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-setsocksfirewallproxystate", networkService, "off"])
        ]
    }

    @discardableResult
    public func setEnabled(
        _ isEnabled: Bool,
        configuration: SystemProxyConfiguration = SystemProxyConfiguration(),
        dryRun: Bool = false
    ) throws -> [ShellCommand] {
        let commands = isEnabled
            ? enableCommands(configuration: configuration)
            : disableCommands(networkService: configuration.networkService)

        if !dryRun {
            try commands.forEach(run)
        }

        var status = try stateStore.load()
        status.systemProxyEnabled = isEnabled
        status.proxyPorts = ProxyPortConfiguration(mixedPort: configuration.port)
        try stateStore.save(status)

        return commands
    }

    private func run(_ command: ShellCommand) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments

        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            throw KumoError.commandFailed(String(decoding: data, as: UTF8.self))
        }
    }
}
