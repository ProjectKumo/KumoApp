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
    public var bypassList: [String]
    public var mode: SystemProxyMode
    public var pacScript: String

    public init(
        networkService: String = "Wi-Fi",
        host: String = "127.0.0.1",
        port: Int = 7890,
        bypassList: [String] = SystemProxySettings.defaultBypassList,
        mode: SystemProxyMode = .manual,
        pacScript: String = ""
    ) {
        self.networkService = networkService
        self.host = host
        self.port = port
        self.bypassList = bypassList
        self.mode = mode
        self.pacScript = pacScript
    }
}

public struct SystemProxyController: Sendable {
    private let stateStore: CoreStateStore
    private let pacServer: PACServer

    public init(paths: KumoPaths = KumoPaths()) {
        self.stateStore = CoreStateStore(paths: paths)
        self.pacServer = PACServer()
    }

    public func availableNetworkServices() throws -> [String] {
        let output = try runCapturingOutput(
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-listallnetworkservices"])
        )
        return output
            .split(separator: "\n")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("An asterisk") }
            .map { service in
                var normalized = service
                if normalized.hasPrefix("*") {
                    normalized.removeFirst()
                }
                return normalized.trimmingCharacters(in: .whitespacesAndNewlines)
            }
    }

    public func snapshot(networkService: String) throws -> SystemProxySnapshot {
        try SystemProxySnapshot(
            networkService: networkService,
            webProxy: runCapturingOutput(
                ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-getwebproxy", networkService])
            ),
            secureWebProxy: runCapturingOutput(
                ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-getsecurewebproxy", networkService])
            ),
            socksProxy: runCapturingOutput(
                ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-getsocksfirewallproxy", networkService])
            ),
            bypassDomains: runCapturingOutput(
                ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-getproxybypassdomains", networkService])
            )
        )
    }

    /// Manual proxy enable commands (web / secure web / socks + bypass).
    public func enableCommands(configuration: SystemProxyConfiguration) -> [ShellCommand] {
        var commands = [
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
        if !configuration.bypassList.isEmpty {
            commands.append(
                ShellCommand(
                    executable: "/usr/sbin/networksetup",
                    arguments: ["-setproxybypassdomains", configuration.networkService] + configuration.bypassList
                )
            )
        }
        return commands
    }

    /// Disable manual web/secure/socks proxies. Used both when turning off
    /// system proxy entirely and when switching from manual to PAC.
    public func disableCommands(networkService: String = "Wi-Fi") -> [ShellCommand] {
        [
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-setwebproxystate", networkService, "off"]),
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-setsecurewebproxystate", networkService, "off"]),
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-setsocksfirewallproxystate", networkService, "off"])
        ]
    }

    /// PAC enable commands (set autoproxy URL + turn autoproxy state on).
    public func pacEnableCommands(networkService: String, pacURL: String) -> [ShellCommand] {
        [
            ShellCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxyurl", networkService, pacURL]
            ),
            ShellCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", networkService, "on"]
            )
        ]
    }

    /// PAC disable commands (turn autoproxy state off).
    public func pacDisableCommands(networkService: String) -> [ShellCommand] {
        [
            ShellCommand(
                executable: "/usr/sbin/networksetup",
                arguments: ["-setautoproxystate", networkService, "off"]
            )
        ]
    }

    /// Apply system proxy settings, branching on `configuration.mode`.
    /// PAC mode starts a local `PACServer` and points macOS at it via
    /// `-setautoproxyurl`; manual mode uses the legacy `-setwebproxy` family.
    /// In `dryRun` no PAC server is started and no commands are executed,
    /// but the would-be commands are returned for inspection.
    @discardableResult
    public func setEnabled(
        _ isEnabled: Bool,
        configuration: SystemProxyConfiguration = SystemProxyConfiguration(),
        dryRun: Bool = false
    ) async throws -> [ShellCommand] {
        let commands: [ShellCommand]
        var pacURL: String?

        if isEnabled {
            switch configuration.mode {
            case .manual:
                if !dryRun {
                    await pacServer.stop()
                }
                commands = enableCommands(configuration: configuration)
                    + pacDisableCommands(networkService: configuration.networkService)
            case .pac:
                if dryRun {
                    pacURL = "http://127.0.0.1:0/proxy.pac"
                } else {
                    let port = try await pacServer.start(script: configuration.pacScript)
                    pacURL = "http://127.0.0.1:\(port)/proxy.pac"
                }
                commands = disableCommands(networkService: configuration.networkService)
                    + pacEnableCommands(networkService: configuration.networkService, pacURL: pacURL ?? "http://127.0.0.1:0/proxy.pac")
            }
        } else {
            if !dryRun {
                await pacServer.stop()
            }
            commands = disableCommands(networkService: configuration.networkService)
                + pacDisableCommands(networkService: configuration.networkService)
        }

        let previousSnapshot: SystemProxySnapshot?
        if !dryRun && isEnabled {
            previousSnapshot = try snapshot(networkService: configuration.networkService)
        } else {
            previousSnapshot = nil
        }

        if !dryRun {
            try commands.forEach(run)
        }

        var status = try stateStore.load()
        status.systemProxyEnabled = isEnabled
        status.proxyPorts = ProxyPortConfiguration(mixedPort: configuration.port)
        var settings = SystemProxySettings(
            networkService: configuration.networkService,
            host: configuration.host,
            port: configuration.port,
            bypassList: configuration.bypassList
        )
        settings.mode = configuration.mode
        settings.pacScript = configuration.pacScript
        status.systemProxySettings = settings
        if isEnabled {
            status.previousSystemProxySnapshot = previousSnapshot
        } else {
            status.previousSystemProxySnapshot = nil
        }
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

    private func runCapturingOutput(_ command: ShellCommand) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments

        let output = Pipe()
        let error = Pipe()
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = error.fileHandleForReading.readDataToEndOfFile()
            throw KumoError.commandFailed(String(decoding: data, as: UTF8.self))
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
