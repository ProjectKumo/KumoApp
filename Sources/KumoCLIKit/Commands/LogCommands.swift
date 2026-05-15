import ArgumentParser
import KumoCoreKit

extension KumoCommand {
    struct Logs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show Kumo logs.",
            subcommands: [Runtime.self, CLI.self, Path.self, Clean.self],
            defaultSubcommand: Runtime.self
        )

        struct Runtime: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "runtime", abstract: "Show recent Mihomo runtime logs.")
            @Option(name: .long, help: "Maximum number of log lines.")
            var limit: Int = 100
            @Option(name: .long, help: "Minimum log level.")
            var level: LogLevel?
            @OptionGroup var options: CLIOptions

            mutating func run() async throws {
                try options.install()
                let entries = try CLIRuntime.current.controller.recentLogs(limit: limit)
                let filtered = level.map { minimum in entries.filter { LogLevel(rawValue: $0.level) ?? .notice <= minimum } } ?? entries
                CLIRuntime.current.write(filtered) { entries in
                    entries.map { "[\($0.level)] \($0.message)" }.joined(separator: "\n")
                }
            }
        }

        struct CLI: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "cli", abstract: "Show recent Kumo CLI debug logs.")
            @Option(name: .long, help: "Maximum number of log files.")
            var limit: Int = 20
            @Option(name: .long, help: "Minimum log level.")
            var level: LogLevel?
            @OptionGroup var options: CLIOptions

            mutating func run() async throws {
                try options.install()
                let entries = CLIRuntime.current.debugLogStore.recentEntries(limit: limit, minimumLevel: level)
                CLIRuntime.current.write(entries) { entries in
                    entries.map { "\($0.createdAt) \($0.level.rawValue) \($0.summary)" }.joined(separator: "\n")
                }
            }
        }

        struct Path: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "path", abstract: "Show logs directory path.")
            @OptionGroup var options: CLIOptions
            mutating func run() async throws {
                try options.install()
                let path = CLIRuntime.current.controller.paths.logsDirectory.path
                CLIRuntime.current.write(["path": path]) { _ in path }
            }
        }

        struct Clean: AsyncParsableCommand {
            static let configuration = CommandConfiguration(commandName: "clean", abstract: "Clean old Kumo CLI debug logs.")
            @Flag(name: .long, help: "Preview files that would be removed.")
            var dryRun = false
            @OptionGroup var options: CLIOptions

            mutating func run() async throws {
                try options.install()
                let report = try CLIRuntime.current.debugLogStore.clean(dryRun: dryRun)
                CLIRuntime.current.write(report) { report in
                    let action = report.dryRun ? "would remove" : "removed"
                    return "\(action) \(report.wouldRemoveFiles) of \(report.matchedFiles) CLI log files"
                }
            }
        }
    }
}
