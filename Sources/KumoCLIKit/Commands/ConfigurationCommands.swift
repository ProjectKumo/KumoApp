import ArgumentParser
import Foundation
import KumoCoreKit

extension KumoCommand {
    struct Config: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show Kumo configuration paths.",
            subcommands: [Path.self, List.self],
            defaultSubcommand: Path.self,
            aliases: ["c"]
        )

        struct Path: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show the application support path.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let paths = CLIPaths(paths: CLIRuntime.current.controller.paths)
                CLIRuntime.current.write(paths) { $0.applicationSupportDirectory }
            }
        }

        struct List: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "List Kumo CLI-visible paths.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let paths = CLIPaths(paths: CLIRuntime.current.controller.paths)
                CLIRuntime.current.write(paths) { paths in
                    [
                        "applicationSupportDirectory=\(paths.applicationSupportDirectory)",
                        "profilesDirectory=\(paths.profilesDirectory)",
                        "workDirectory=\(paths.workDirectory)",
                        "logsDirectory=\(paths.logsDirectory)",
                        "runtimeConfigFile=\(paths.runtimeConfigFile)",
                        "stateFile=\(paths.stateFile)"
                    ].joined(separator: "\n")
                }
            }
        }
    }

    struct Backup: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Export or import Kumo backup data.",
            subcommands: [Export.self, Import.self]
        )

        struct Export: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Export a Kumo backup.")
            @Argument(help: "Destination directory.")
            var path: String
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let result = try CLIRuntime.current.controller.exportBackup(to: URL(fileURLWithPath: path))
                CLIRuntime.current.write(result) { "exported backup to \($0.destinationPath)" }
            }
        }

        struct Import: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Import a Kumo backup.")
            @Argument(help: "Source backup directory.")
            var path: String
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let manifest = try CLIRuntime.current.controller.importBackup(from: URL(fileURLWithPath: path))
                CLIRuntime.current.write(manifest) { "imported backup from \($0.createdAt)" }
            }
        }
    }

    struct Core: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage the managed Mihomo core.",
            subcommands: [Install.self]
        )

        struct Install: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Install the managed Mihomo core.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let result = try await CLIRuntime.current.controller.installManagedCore()
                CLIRuntime.current.write(result) { "installed \($0.version) at \($0.path)" }
            }
        }
    }

    struct Profile: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage profiles.",
            subcommands: [Refresh.self]
        )

        struct Refresh: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Refresh or import a remote profile URL.")
            @Argument(help: "Remote subscription URL.")
            var url: String
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                guard let parsedURL = URL(string: url), parsedURL.scheme != nil else {
                    throw ValidationError("Invalid profile URL: \(url)")
                }
                let profile = try await CLIRuntime.current.controller.refreshProfile(from: parsedURL)
                CLIRuntime.current.write(profile) { "refreshed \($0.name)" }
            }
        }
    }

    struct Sysproxy: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Enable or disable macOS system proxy.")

        @Argument(help: "System proxy state: on or off.")
        var state: OnOff
        @Flag(name: .long, help: "Preview networksetup commands without changing system settings.")
        var dryRun = false
        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            let commands = try await CLIRuntime.current.controller.setSystemProxy(state == .on, dryRun: dryRun)
            CLIRuntime.current.write(commands) { commands in
                let text = commands.map { ([ $0.executable ] + $0.arguments).joined(separator: " ") }.joined(separator: "\n")
                return dryRun ? text : "system proxy \(state.rawValue)"
            }
        }
    }

    struct Service: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage Kumo service mode.",
            subcommands: [Status.self, Install.self, Uninstall.self]
        )

        struct Status: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show service mode state.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                write(CLIRuntime.current.controller.serviceModeStatus())
            }
        }

        struct Install: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Install service mode.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                write(try CLIRuntime.current.controller.installServiceMode())
            }
        }

        struct Uninstall: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Uninstall service mode.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                write(try CLIRuntime.current.controller.uninstallServiceMode())
            }
        }

        private static func write(_ status: ServiceModeStatus) {
            CLIRuntime.current.write(status) { status in
                [
                    "installed=\(status.isInstalled)",
                    "running=\(status.isRunning)",
                    "available=\(status.isAvailable)",
                    "privileged=\(status.isCurrentProcessPrivileged)"
                ].joined(separator: " ")
            }
        }
    }

    struct Tun: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Manage TUN state.",
            subcommands: [Status.self, Enable.self, Disable.self]
        )

        struct Status: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show TUN state.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                write(try CLIRuntime.current.controller.tunStatus())
            }
        }

        struct Enable: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Enable TUN.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                write(try await CLIRuntime.current.controller.setTunEnabled(true))
            }
        }

        struct Disable: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Disable TUN.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                write(try await CLIRuntime.current.controller.setTunEnabled(false))
            }
        }

        private static func write(_ status: TunStatus) {
            CLIRuntime.current.write(status) { status in
                "enabled=\(status.isEnabled) running=\(status.isRunning) requiresService=\(status.requiresService)"
            }
        }
    }

    struct Substore: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "substore",
            abstract: "Manage bundled Sub-Store resources and runtime.",
            subcommands: [Status.self, Prepare.self, Start.self, Stop.self, Restart.self]
        )

        struct Status: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Show Sub-Store state.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let status = try await CLIRuntime.current.controller.subStoreRuntimeStatus()
                CLIRuntime.current.write(status) { status in
                    [
                        "enabled=\(status.configuration.isEnabled)",
                        "backend=\(status.isBackendRunning)",
                        "url=\(status.backendURL?.absoluteString ?? "-")",
                        "resources=\(status.resourcesInstalled)"
                    ].joined(separator: " ")
                }
            }
        }

        struct Prepare: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Prepare bundled Sub-Store resources.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let status = try CLIRuntime.current.controller.prepareSubStoreResources()
                CLIRuntime.current.write(status) { "prepared Sub-Store resources \($0.installedResourceVersion ?? "-")" }
            }
        }

        struct Start: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Start Sub-Store.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let status = try await CLIRuntime.current.controller.setSubStoreEnabled(true)
                CLIRuntime.current.write(status) { _ in "started Sub-Store" }
            }
        }

        struct Stop: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Stop Sub-Store.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let status = try await CLIRuntime.current.controller.setSubStoreEnabled(false)
                CLIRuntime.current.write(status) { _ in "stopped Sub-Store" }
            }
        }

        struct Restart: AsyncParsableCommand {
            static let configuration = CommandConfiguration(abstract: "Restart Sub-Store.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                try await CLIRuntime.current.controller.restartSubStoreService()
                let status = try await CLIRuntime.current.controller.subStoreRuntimeStatus()
                CLIRuntime.current.write(status) { _ in "restarted Sub-Store" }
            }
        }
    }
}
