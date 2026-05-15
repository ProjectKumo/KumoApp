import ArgumentParser
import Foundation
import KumoCoreKit

extension KumoCommand {
    struct Connections: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List or close active connections.")

        @Option(name: .long, help: "Close a specific connection id.")
        var close: String?
        @Flag(name: .long, help: "Close all active connections.")
        var closeAll = false
        @OptionGroup var options: CLIOptions

        mutating func validate() throws {
            if close != nil && closeAll {
                throw ValidationError("Use either --close <id> or --close-all, not both.")
            }
        }

        mutating func run() async throws {
            try options.install()
            if closeAll {
                try await CLIRuntime.current.controller.closeConnections()
                CLIRuntime.current.write(["closed": "all"]) { _ in "closed all connections" }
                return
            }
            if let close {
                try await CLIRuntime.current.controller.closeConnection(id: close)
                CLIRuntime.current.write(["closed": close]) { _ in "closed \(close)" }
                return
            }
            let connections = try await CLIRuntime.current.controller.connections()
            CLIRuntime.current.write(connections) { connections in
                connections.map { "\($0.host) \($0.chain.joined(separator: " > "))" }.joined(separator: "\n")
            }
        }
    }

    struct Skills: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage bundled Kumo agent skills.",
            subcommands: [Status.self, Install.self, Uninstall.self]
        )

        struct Status: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show agent skill installation state.")
            @OptionGroup var selection: SkillSelection
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let installer = try AgentSkillsInstaller(paths: CLIRuntime.current.controller.paths)
                let status = try installer.status(
                    targets: try selection.targets(),
                    scope: selection.scope,
                    projectWorkingDirectory: currentDirectoryURL()
                )
                CLIRuntime.current.write(status) { status in
                    status.targets.map { targetStatus in
                        [
                            targetStatus.target.rawValue,
                            "scope=\(targetStatus.scope.rawValue)",
                            "installed=\(targetStatus.installed)",
                            "upToDate=\(targetStatus.upToDate)",
                            "path=\(targetStatus.destinationRoot)"
                        ].joined(separator: " ")
                    }.joined(separator: "\n")
                }
            }
        }

        struct Install: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Install bundled Kumo agent skills.", aliases: ["add"])
            @OptionGroup var selection: SkillSelection
            @Flag(name: .long, help: "Preview installation without writing files.")
            var dryRun = false
            @Flag(name: .long, help: "Replace an existing untracked skill directory.")
            var force = false
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let installer = try AgentSkillsInstaller(paths: CLIRuntime.current.controller.paths)
                let report = try installer.install(
                    targets: try selection.targets(),
                    scope: selection.scope,
                    projectWorkingDirectory: currentDirectoryURL(),
                    dryRun: dryRun,
                    force: force
                )
                CLIRuntime.current.write(report) { report in
                    let action = report.dryRun ? "[dry-run] would install" : "installed"
                    return "\(action) \(report.copiedSkillIds.joined(separator: ", ")) to \(report.destinationRoots.joined(separator: ", "))"
                }
            }
        }

        struct Uninstall: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Uninstall bundled Kumo agent skills.")
            @OptionGroup var selection: SkillSelection
            @Flag(name: .long, help: "Preview uninstall without writing files.")
            var dryRun = false
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let installer = try AgentSkillsInstaller(paths: CLIRuntime.current.controller.paths)
                let report = try installer.uninstall(
                    targets: try selection.targets(),
                    scope: selection.scope,
                    projectWorkingDirectory: currentDirectoryURL(),
                    dryRun: dryRun
                )
                CLIRuntime.current.write(report) { report in
                    let action = report.dryRun ? "[dry-run] would uninstall" : "uninstalled"
                    return "\(action) \(report.copiedSkillIds.joined(separator: ", ")) from \(report.destinationRoots.joined(separator: ", "))"
                }
            }
        }
    }
}
