import Foundation
import KumoCoreKit

await KumoCLI.main()

enum KumoCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let wantsJSON = arguments.contains("--json")
        let filteredArguments = arguments.filter { $0 != "--json" }
        let controller = KumoController()

        do {
            try await run(arguments: filteredArguments, controller: controller, wantsJSON: wantsJSON)
        } catch {
            writeError(error, asJSON: wantsJSON)
            Foundation.exit(1)
        }
    }

    private static func run(
        arguments: [String],
        controller: KumoController,
        wantsJSON: Bool
    ) async throws {
        guard let command = arguments.first else {
            printUsage()
            return
        }

        switch command {
        case "status":
            let status = try controller.status()
            write(status, asJSON: wantsJSON) { status in
                "\(status.state.rawValue) mode=\(status.mode.rawValue) pid=\(status.pid.map(String.init) ?? "-")"
            }
        case "start":
            let corePath = value(after: "--core", in: arguments)
            if corePath == nil {
                try await installManagedCoreIfNeeded(controller: controller)
            }
            let status = try controller.start(corePath: corePath)
            write(status, asJSON: wantsJSON) { "started pid=\($0.pid.map(String.init) ?? "-")" }
        case "stop":
            let status = try controller.stop()
            write(status, asJSON: wantsJSON) { _ in "stopped" }
        case "restart":
            let corePath = value(after: "--core", in: arguments)
            if corePath == nil {
                try await installManagedCoreIfNeeded(controller: controller)
            }
            let status = try controller.restart(corePath: corePath)
            write(status, asJSON: wantsJSON) { "restarted pid=\($0.pid.map(String.init) ?? "-")" }
        case "mode":
            guard arguments.count >= 2, let mode = OutboundMode(rawValue: arguments[1]) else {
                throw KumoError.invalidArguments("Usage: kumo mode <rule|global|direct>")
            }
            try await controller.setMode(mode)
            write(["mode": mode.rawValue], asJSON: wantsJSON) { _ in "mode \(mode.rawValue)" }
        case "proxies":
            let groups = try await controller.proxyGroups()
            write(groups, asJSON: wantsJSON) { groups in
                groups.map { "\($0.name): \($0.selectedProxyName ?? "-")" }.joined(separator: "\n")
            }
        case "select":
            guard arguments.count >= 3 else {
                throw KumoError.invalidArguments("Usage: kumo select <group> <proxy>")
            }
            try await controller.selectProxy(group: arguments[1], name: arguments[2])
            write(["group": arguments[1], "proxy": arguments[2]], asJSON: wantsJSON) { _ in
                "selected \(arguments[2]) for \(arguments[1])"
            }
        case "profile":
            try await runProfileCommand(arguments: arguments, controller: controller, wantsJSON: wantsJSON)
        case "logs":
            let limit = value(after: "--limit", in: arguments).flatMap(Int.init) ?? 100
            let logs = try controller.recentLogs(limit: limit)
            write(logs, asJSON: wantsJSON) { logs in
                logs.map { "[\($0.level)] \($0.message)" }.joined(separator: "\n")
            }
        case "connections":
            try await runConnectionsCommand(arguments: arguments, controller: controller, wantsJSON: wantsJSON)
        case "providers":
            let report = ProviderReport(
                proxies: try await controller.proxyProviders(),
                rules: try await controller.ruleProviders()
            )
            write(report, asJSON: wantsJSON) { report in
                [
                    "Proxy providers: \(report.proxies.count)",
                    "Rule providers: \(report.rules.count)"
                ].joined(separator: "\n")
            }
        case "runtime-events":
            let limit = value(after: "--limit", in: arguments).flatMap(Int.init) ?? 100
            let events = try controller.runtimeEvents(limit: limit)
            write(events, asJSON: wantsJSON) { events in
                events.map { "\($0.time): \($0.kind) \($0.message)" }.joined(separator: "\n")
            }
        case "doctor":
            let report = try DoctorReport(
                status: controller.status(),
                currentProfile: controller.currentProfile(),
                coreCandidates: controller.coreCandidates()
            )
            write(report, asJSON: wantsJSON) { report in
                [
                    "State: \(report.status.state.rawValue)",
                    "Profile: \(report.currentProfile.name)",
                    "Core candidates: \(report.coreCandidates.count)"
                ].joined(separator: "\n")
            }
        case "config":
            try runConfigCommand(arguments: arguments, controller: controller, wantsJSON: wantsJSON)
        case "backup":
            try runBackupCommand(arguments: arguments, controller: controller, wantsJSON: wantsJSON)
        case "sysproxy":
            try await runSystemProxyCommand(arguments: arguments, controller: controller, wantsJSON: wantsJSON)
        case "core":
            try await runCoreCommand(arguments: arguments, controller: controller, wantsJSON: wantsJSON)
        case "service":
            try runServiceCommand(arguments: arguments, controller: controller, wantsJSON: wantsJSON)
        case "tun":
            try await runTunCommand(arguments: arguments, controller: controller, wantsJSON: wantsJSON)
        default:
            throw KumoError.invalidArguments("Unknown command: \(command)")
        }
    }

    private static func installManagedCoreIfNeeded(controller: KumoController) async throws {
        let status = try controller.status()
        let candidates = try controller.coreCandidates()
        let managedCorePath = controller.paths.managedCoreExecutable.path
        let managedCoreInstalled = FileManager.default.isExecutableFile(atPath: managedCorePath)
        let shouldInstall = if status.corePath == nil {
            !managedCoreInstalled
        } else {
            candidates.isEmpty
        }

        guard shouldInstall else {
            return
        }

        _ = try await controller.installManagedCore()
    }

    private static func runCoreCommand(
        arguments: [String],
        controller: KumoController,
        wantsJSON: Bool
    ) async throws {
        guard arguments.count >= 2, arguments[1] == "install" else {
            throw KumoError.invalidArguments("Usage: kumo core install [--json]")
        }

        let result = try await controller.installManagedCore()
        write(result, asJSON: wantsJSON) { "installed \(result.version) at \($0.path)" }
    }

    private static func runProfileCommand(
        arguments: [String],
        controller: KumoController,
        wantsJSON: Bool
    ) async throws {
        guard arguments.count >= 3, arguments[1] == "refresh", let url = URL(string: arguments[2]) else {
            throw KumoError.invalidArguments("Usage: kumo profile refresh <url>")
        }

        let profile = try await controller.refreshProfile(from: url)
        write(profile, asJSON: wantsJSON) { profile in "refreshed \(profile.name)" }
    }

    private static func runConnectionsCommand(
        arguments: [String],
        controller: KumoController,
        wantsJSON: Bool
    ) async throws {
        if arguments.contains("--close-all") {
            try await controller.closeConnections()
            write(["closed": "all"], asJSON: wantsJSON) { _ in "closed all connections" }
            return
        }

        if let id = value(after: "--close", in: arguments) {
            try await controller.closeConnection(id: id)
            write(["closed": id], asJSON: wantsJSON) { _ in "closed \(id)" }
            return
        }

        let connections = try await controller.connections()
        write(connections, asJSON: wantsJSON) { connections in
            connections.map { connection in
                "\(connection.host) \(connection.chain.joined(separator: " > "))"
            }.joined(separator: "\n")
        }
    }

    private static func runConfigCommand(
        arguments: [String],
        controller: KumoController,
        wantsJSON: Bool
    ) throws {
        guard arguments.count >= 2, arguments[1] == "path" else {
            throw KumoError.invalidArguments("Usage: kumo config path [--json]")
        }

        let paths = CLIPaths(paths: controller.paths)
        write(paths, asJSON: wantsJSON) { paths in
            paths.applicationSupportDirectory
        }
    }

    private static func runBackupCommand(
        arguments: [String],
        controller: KumoController,
        wantsJSON: Bool
    ) throws {
        guard arguments.count >= 3 else {
            throw KumoError.invalidArguments("Usage: kumo backup <export|import> <path> [--json]")
        }

        let url = URL(fileURLWithPath: arguments[2])
        switch arguments[1] {
        case "export":
            let result = try controller.exportBackup(to: url)
            write(result, asJSON: wantsJSON) { "exported backup to \($0.destinationPath)" }
        case "import":
            let manifest = try controller.importBackup(from: url)
            write(manifest, asJSON: wantsJSON) { manifest in "imported backup from \(manifest.createdAt)" }
        default:
            throw KumoError.invalidArguments("Usage: kumo backup <export|import> <path> [--json]")
        }
    }

    private static func runSystemProxyCommand(
        arguments: [String],
        controller: KumoController,
        wantsJSON: Bool
    ) async throws {
        guard arguments.count >= 2 else {
            throw KumoError.invalidArguments("Usage: kumo sysproxy <on|off> [--dry-run]")
        }

        let dryRun = arguments.contains("--dry-run")
        let isEnabled: Bool
        switch arguments[1] {
        case "on":
            isEnabled = true
        case "off":
            isEnabled = false
        default:
            throw KumoError.invalidArguments("Usage: kumo sysproxy <on|off> [--dry-run]")
        }

        let commands = try await controller.setSystemProxy(isEnabled, dryRun: dryRun)
        write(commands, asJSON: wantsJSON) { commands in
            commands.map { ([ $0.executable ] + $0.arguments).joined(separator: " ") }.joined(separator: "\n")
        }
    }

    private static func runServiceCommand(
        arguments: [String],
        controller: KumoController,
        wantsJSON: Bool
    ) throws {
        guard arguments.count >= 2 else {
            throw KumoError.invalidArguments("Usage: kumo service <status|install|uninstall> [--json]")
        }

        let status: ServiceModeStatus
        switch arguments[1] {
        case "status":
            status = controller.serviceModeStatus()
        case "install":
            status = try controller.installServiceMode()
        case "uninstall":
            status = try controller.uninstallServiceMode()
        default:
            throw KumoError.invalidArguments("Usage: kumo service <status|install|uninstall> [--json]")
        }

        write(status, asJSON: wantsJSON) { status in
            [
                "installed=\(status.isInstalled)",
                "running=\(status.isRunning)",
                "available=\(status.isAvailable)",
                "privileged=\(status.isCurrentProcessPrivileged)"
            ].joined(separator: " ")
        }
    }

    private static func runTunCommand(
        arguments: [String],
        controller: KumoController,
        wantsJSON: Bool
    ) async throws {
        guard arguments.count >= 2 else {
            throw KumoError.invalidArguments("Usage: kumo tun <status|enable|disable> [--json]")
        }

        let status: TunStatus
        switch arguments[1] {
        case "status":
            status = try controller.tunStatus()
        case "enable":
            status = try await controller.setTunEnabled(true)
        case "disable":
            status = try await controller.setTunEnabled(false)
        default:
            throw KumoError.invalidArguments("Usage: kumo tun <status|enable|disable> [--json]")
        }

        write(status, asJSON: wantsJSON) { status in
            [
                "enabled=\(status.isEnabled)",
                "running=\(status.isRunning)",
                "requiresService=\(status.requiresService)"
            ].joined(separator: " ")
        }
    }

    private static func write<T: Encodable>(
        _ value: T,
        asJSON wantsJSON: Bool,
        text: (T) -> String
    ) {
        if wantsJSON {
            writeJSON(CLIResponse(ok: true, data: value))
        } else {
            print(text(value))
        }
    }

    private static func writeError(_ error: Error, asJSON wantsJSON: Bool) {
        let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        if wantsJSON {
            writeJSON(CLIResponse<String>(ok: false, error: message))
        } else {
            fputs("error: \(message)\n", stderr)
        }
    }

    private static func writeJSON<T: Encodable>(_ value: T) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(value),
           let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func printUsage() {
        print(
            """
            Usage:
              kumo status [--json]
              kumo start [--core <path>] [--json]
              kumo stop [--json]
              kumo restart [--core <path>] [--json]
              kumo mode <rule|global|direct> [--json]
              kumo proxies [--json]
              kumo select <group> <proxy> [--json]
              kumo logs [--limit <count>] [--json]
              kumo connections [--close <id>|--close-all] [--json]
              kumo providers [--json]
              kumo runtime-events [--limit <count>] [--json]
              kumo doctor [--json]
              kumo config path [--json]
              kumo backup export <path> [--json]
              kumo backup import <path> [--json]
              kumo core install [--json]
              kumo profile refresh <url> [--json]
              kumo sysproxy <on|off> [--dry-run] [--json]
              kumo service <status|install|uninstall> [--json]
              kumo tun <status|enable|disable> [--json]
            """
        )
    }
}

private struct ProviderReport: Encodable {
    var proxies: [ProxyProviderEntry]
    var rules: [RuleProviderEntry]
}

private struct DoctorReport: Encodable {
    var status: CoreStatus
    var currentProfile: ProfileSummary
    var coreCandidates: [CoreCandidate]
}

private struct CLIPaths: Encodable {
    var applicationSupportDirectory: String
    var profilesDirectory: String
    var workDirectory: String
    var logsDirectory: String
    var runtimeConfigFile: String
    var stateFile: String

    init(paths: KumoPaths) {
        self.applicationSupportDirectory = paths.applicationSupportDirectory.path
        self.profilesDirectory = paths.profilesDirectory.path
        self.workDirectory = paths.workDirectory.path
        self.logsDirectory = paths.logsDirectory.path
        self.runtimeConfigFile = paths.runtimeConfigFile.path
        self.stateFile = paths.stateFile.path
    }
}
