import Foundation
import Network

private final class ConnectionProbeState: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resumeOnce(_ value: Bool, connection: NWConnection, continuation: CheckedContinuation<Bool, Never>) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        connection.cancel()
        continuation.resume(returning: value)
    }
}

public struct ShellCommand: Codable, Equatable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var environment: [String: String]?

    public init(executable: String, arguments: [String], environment: [String: String]? = nil) {
        self.executable = executable
        self.arguments = arguments
        self.environment = environment
    }
}

public struct SystemProxyCommandRunner: Sendable {
    public var run: @Sendable (ShellCommand) throws -> Void
    public var captureOutput: @Sendable (ShellCommand) throws -> String

    public init(
        run: @escaping @Sendable (ShellCommand) throws -> Void,
        captureOutput: @escaping @Sendable (ShellCommand) throws -> String
    ) {
        self.run = run
        self.captureOutput = captureOutput
    }

    public static let live = SystemProxyCommandRunner(
        run: { command in
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
        },
        captureOutput: { command in
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
    )
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
    private let commandRunner: SystemProxyCommandRunner

    public init(paths: KumoPaths = KumoPaths(), commandRunner: SystemProxyCommandRunner = .live) {
        self.stateStore = CoreStateStore(paths: paths)
        self.pacServer = PACServer()
        self.commandRunner = commandRunner
    }

    public func availableNetworkServices() throws -> [String] {
        let output = try commandRunner.captureOutput(
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

    public func activeNetworkService() throws -> String {
        let routeOutput = try commandRunner.captureOutput(
            ShellCommand(executable: "/sbin/route", arguments: ["-n", "get", "default"])
        )
        guard let interface = routeOutput
            .split(separator: "\n")
            .map({ String($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { $0.hasPrefix("interface:") })?
            .split(separator: " ")
            .last
            .map(String.init) else {
            throw KumoError.commandFailed("Unable to determine active network interface.")
        }

        let orderOutput = try commandRunner.captureOutput(
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-listnetworkserviceorder"])
        )
        return try Self.networkService(in: orderOutput, matchingDevice: interface)
    }

    public static func networkService(in serviceOrderOutput: String, matchingDevice device: String) throws -> String {
        let blocks = serviceOrderOutput.components(separatedBy: "\n\n")
        guard let block = blocks.first(where: { $0.contains("Device: \(device)") }) else {
            throw KumoError.commandFailed("Unable to find a network service for interface \(device).")
        }

        for line in block.split(separator: "\n") {
            let trimmed = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("("), let closeIndex = trimmed.firstIndex(of: ")") else {
                continue
            }
            return String(trimmed[trimmed.index(after: closeIndex)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw KumoError.commandFailed("Unable to parse network service for interface \(device).")
    }

    public func snapshot(networkService: String) throws -> SystemProxySnapshot {
        try SystemProxySnapshot(
            networkService: networkService,
            webProxy: commandRunner.captureOutput(
                ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-getwebproxy", networkService])
            ),
            secureWebProxy: commandRunner.captureOutput(
                ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-getsecurewebproxy", networkService])
            ),
            socksProxy: commandRunner.captureOutput(
                ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-getsocksfirewallproxy", networkService])
            ),
            bypassDomains: commandRunner.captureOutput(
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
                    let port = try await pacServer.start(script: Self.renderPACScript(configuration.pacScript, port: configuration.port))
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
            if isEnabled {
                try await verifyTargetPort(configuration: configuration)
            }
            try commands.forEach(commandRunner.run)
            try verifyAppliedState(isEnabled: isEnabled, configuration: configuration, pacURL: pacURL)
        }

        var status = try stateStore.load()
        status.systemProxyEnabled = isEnabled
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

    @discardableResult
    public func disableSynchronously(configuration: SystemProxyConfiguration = SystemProxyConfiguration()) throws -> [ShellCommand] {
        let commands = disableCommands(networkService: configuration.networkService)
            + pacDisableCommands(networkService: configuration.networkService)
        try commands.forEach(commandRunner.run)

        var status = try stateStore.load()
        status.systemProxyEnabled = false
        status.previousSystemProxySnapshot = nil
        try stateStore.save(status)

        return commands
    }

    public static func renderPACScript(_ script: String, port: Int) -> String {
        script.replacingOccurrences(of: "%mixed-port%", with: "\(port)")
    }

    private func verifyTargetPort(configuration: SystemProxyConfiguration) async throws {
        guard configuration.port > 0 else {
            throw KumoError.commandFailed("System proxy port must be greater than zero.")
        }
        let canConnect = await canConnect(to: configuration.host, port: configuration.port)
        guard canConnect else {
            throw KumoError.commandFailed("System proxy target \(configuration.host):\(configuration.port) is not accepting connections.")
        }
    }

    private func verifyAppliedState(isEnabled: Bool, configuration: SystemProxyConfiguration, pacURL: String?) throws {
        let webProxy = try commandRunner.captureOutput(
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-getwebproxy", configuration.networkService])
        )
        let secureWebProxy = try commandRunner.captureOutput(
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-getsecurewebproxy", configuration.networkService])
        )
        let socksProxy = try commandRunner.captureOutput(
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-getsocksfirewallproxy", configuration.networkService])
        )
        let autoProxy = try commandRunner.captureOutput(
            ShellCommand(executable: "/usr/sbin/networksetup", arguments: ["-getautoproxyurl", configuration.networkService])
        )

        if !isEnabled {
            guard [webProxy, secureWebProxy, socksProxy, autoProxy].allSatisfy({ $0.contains("Enabled: No") }) else {
                throw KumoError.commandFailed("macOS did not disable every Kumo-managed proxy setting for \(configuration.networkService).")
            }
            return
        }

        switch configuration.mode {
        case .manual:
            let expected = [webProxy, secureWebProxy, socksProxy]
            guard expected.allSatisfy({ output in
                output.contains("Enabled: Yes")
                    && output.contains("Server: \(configuration.host)")
                    && output.contains("Port: \(configuration.port)")
            }) else {
                throw KumoError.commandFailed("macOS did not apply manual proxy \(configuration.host):\(configuration.port) to \(configuration.networkService).")
            }
            guard autoProxy.contains("Enabled: No") else {
                throw KumoError.commandFailed("macOS auto proxy is still enabled after applying manual proxy.")
            }
        case .pac:
            guard [webProxy, secureWebProxy, socksProxy].allSatisfy({ $0.contains("Enabled: No") }) else {
                throw KumoError.commandFailed("macOS manual proxies are still enabled after applying PAC mode.")
            }
            guard let pacURL,
                  autoProxy.contains("Enabled: Yes"),
                  autoProxy.contains(pacURL) else {
                throw KumoError.commandFailed("macOS did not apply PAC proxy URL for \(configuration.networkService).")
            }
        }
    }

    private func canConnect(to host: String, port: Int) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                await withCheckedContinuation { continuation in
                    let connection = NWConnection(
                        host: NWEndpoint.Host(host),
                        port: NWEndpoint.Port(integerLiteral: UInt16(port)),
                        using: .tcp
                    )
                    let probeState = ConnectionProbeState()
                    connection.stateUpdateHandler = { connectionState in
                        switch connectionState {
                        case .ready:
                            probeState.resumeOnce(true, connection: connection, continuation: continuation)
                        case .failed, .cancelled:
                            probeState.resumeOnce(false, connection: connection, continuation: continuation)
                        default:
                            break
                        }
                    }
                    connection.start(queue: .global(qos: .utility))
                }
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(1))
                return false
            }
            guard let result = await group.next() else {
                return false
            }
            group.cancelAll()
            return result
        }
    }

}
