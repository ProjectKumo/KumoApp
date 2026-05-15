import ArgumentParser
import Foundation

public enum KumoCLIEntrypoint {
    public static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let options = RuntimeOptions(arguments: arguments)
        let runtime = CLIRuntime(options: options)

        do {
            if try await handleBuiltIn(arguments: arguments, runtime: runtime) {
                return
            }

            var command = try KumoCommand.parseAsRoot(arguments)
            if var asyncCommand = command as? AsyncParsableCommand {
                try await asyncCommand.run()
            } else {
                try command.run()
            }
            try runtime.finish(success: true)
        } catch {
            runtime.writeError(error)
            try? runtime.finish(success: false)
            Foundation.exit(1)
        }
    }

    private static func handleBuiltIn(arguments: [String], runtime: CLIRuntime) async throws -> Bool {
        let normalized = arguments.filter { !$0.hasPrefix("--color") && $0 != "always" && $0 != "auto" && $0 != "never" }
        if normalized.isEmpty || normalized == ["--help"] || normalized == ["-h"] {
            runtime.writeText(HelpText.topLevel)
            return true
        }
        if normalized == ["-l"] || normalized == ["--long"] {
            runtime.writeText(HelpText.long)
            return true
        }
        if normalized == ["--version"] || normalized == ["-v"] {
            runtime.writeText(KumoCommand.configuration.version)
            return true
        }
        return false
    }
}
