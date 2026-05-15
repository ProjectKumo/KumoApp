import ArgumentParser

extension KumoCommand {
    struct Completion: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Generate shell completion scripts.")

        @Argument(help: "Shell name: zsh, bash, or fish.")
        var shell: CompletionShell?
        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            guard let shell else {
                CLIRuntime.current.writeText(HelpText.completion)
                return
            }
            CLIRuntime.current.writeText(CompletionScripts.script(for: shell))
        }
    }

    struct Help: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Show detailed help for a topic.")

        @Argument(help: "Help topic or command path.")
        var terms: [String] = []
        @OptionGroup var options: CLIOptions

        mutating func run() async throws {
            try options.install()
            CLIRuntime.current.writeText(HelpText.topic(terms))
        }
    }
}
