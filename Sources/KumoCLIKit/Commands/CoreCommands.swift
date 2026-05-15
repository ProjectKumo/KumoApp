import ArgumentParser
import Foundation
import KumoCoreKit

extension KumoCommand {
    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Show current Kumo runtime state.",
            aliases: ["st"]
        )

        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            let status = try CLIRuntime.current.controller.status()
            CLIRuntime.current.write(status) { status in
                let prefix = status.state == .running ? "[ok] " : ""
                return "\(prefix)\(status.state.rawValue) mode=\(status.mode.rawValue) pid=\(status.pid.map(String.init) ?? "-")"
            }
        }
    }

    struct Start: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Start Kumo with the managed Mihomo core.")

        @Option(name: .long, help: "Use a specific Mihomo core executable.")
        var core: String?
        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            if core == nil {
                try await installManagedCoreIfNeeded()
            }
            let status = try CLIRuntime.current.controller.start(corePath: core)
            CLIRuntime.current.write(status) { "started pid=\($0.pid.map(String.init) ?? "-")" }
        }
    }

    struct Stop: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Stop Kumo.")

        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            let status = try CLIRuntime.current.controller.stop()
            CLIRuntime.current.write(status) { _ in "stopped" }
        }
    }

    struct Restart: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Restart Kumo.")

        @Option(name: .long, help: "Use a specific Mihomo core executable.")
        var core: String?
        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            if core == nil {
                try await installManagedCoreIfNeeded()
            }
            let status = try CLIRuntime.current.controller.restart(corePath: core)
            CLIRuntime.current.write(status) { "restarted pid=\($0.pid.map(String.init) ?? "-")" }
        }
    }

    struct Mode: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Set outbound mode.")

        @Argument(help: "Outbound mode: rule, global, or direct.")
        var mode: OutboundMode
        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            try await CLIRuntime.current.controller.setMode(mode)
            CLIRuntime.current.write(["mode": mode.rawValue]) { _ in "mode \(mode.rawValue)" }
        }
    }

    struct Proxies: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List proxy groups and selected proxies.",
            aliases: ["proxy"]
        )

        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            let groups = try await CLIRuntime.current.controller.proxyGroups()
            CLIRuntime.current.write(groups) { groups in
                groups.map { "\($0.name): \($0.selectedProxyName ?? "-")" }.joined(separator: "\n")
            }
        }
    }

    struct Select: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Select a proxy for a group.")

        @Argument(help: "Proxy group name.")
        var group: String
        @Argument(help: "Proxy name.")
        var proxy: String
        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            try await CLIRuntime.current.controller.selectProxy(group: group, name: proxy)
            CLIRuntime.current.write(["group": group, "proxy": proxy]) { _ in "selected \(proxy) for \(group)" }
        }
    }

    struct Providers: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show proxy and rule provider counts.")

        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            let report = ProviderReport(
                proxies: try await CLIRuntime.current.controller.proxyProviders(),
                rules: try await CLIRuntime.current.controller.ruleProviders()
            )
            CLIRuntime.current.write(report) { report in
                "Proxy providers: \(report.proxies.count)\nRule providers: \(report.rules.count)"
            }
        }
    }

    struct RuntimeEvents: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "runtime-events",
            abstract: "Show recent Kumo runtime events."
        )

        @Option(name: .long, help: "Maximum number of events.")
        var limit: Int = 100
        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            let events = try CLIRuntime.current.controller.runtimeEvents(limit: limit)
            CLIRuntime.current.write(events) { events in
                events.map { "\($0.time): \($0.kind) \($0.message)" }.joined(separator: "\n")
            }
        }
    }

    struct Doctor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Inspect runtime, profile, and core candidates.")

        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            let runtime = CLIRuntime.current
            let report = try runtime.measure("doctor") {
                try DoctorReport(
                    status: runtime.measure("status") { try runtime.controller.status() },
                    currentProfile: runtime.measure("profile") { try runtime.controller.currentProfile() },
                    coreCandidates: runtime.measure("core-candidates") { try runtime.controller.coreCandidates() }
                )
            }
            runtime.write(report) { report in
                "State: \(report.status.state.rawValue)\nProfile: \(report.currentProfile.name)\nCore candidates: \(report.coreCandidates.count)"
            }
        }
    }
}
