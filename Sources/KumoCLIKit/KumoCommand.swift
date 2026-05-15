import ArgumentParser

public struct KumoCommand: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "kumo",
        abstract: "Control Kumo from the command line.",
        version: "0.0.1",
        subcommands: [
            Status.self,
            Start.self,
            Stop.self,
            Restart.self,
            Mode.self,
            Proxies.self,
            Select.self,
            Logs.self,
            Connections.self,
            Providers.self,
            RuntimeEvents.self,
            Doctor.self,
            Config.self,
            Backup.self,
            Core.self,
            Profile.self,
            Sysproxy.self,
            Service.self,
            Tun.self,
            Substore.self,
            Skills.self,
            Completion.self,
            Help.self
        ]
    )

    public init() {}

    public mutating func run() async throws {
        CLIRuntime.current.writeText(HelpText.topLevel)
    }
}
