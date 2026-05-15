enum HelpText {
    static let topLevel = """
    kumo <command>

    Usage:

    kumo status --json          show current Kumo runtime state
    kumo start                  start Kumo with the managed Mihomo core
    kumo doctor --json          inspect runtime, profile, and core candidates
    kumo proxies                list proxy groups and selected proxies
    kumo skills install --dry-run --json
                                 preview agent skill installation
    kumo <command> -h           quick help on a command
    kumo -l                     display usage info for all commands
    kumo help <term>            show detailed help for a topic

    All commands:

        backup, completion, config, connections, core, doctor,
        help, logs, mode, profile, providers, proxies, restart,
        service, skills, start, status, stop, substore, sysproxy,
        tun, runtime-events

    Kumo CLI binary:
        Kumo.app/Contents/Helpers/kumo

    Installed command:
        /usr/local/bin/kumo -> Kumo.app/Contents/Helpers/kumo

    kumo@0.0.1
    """

    static let long = """
    \(topLevel)

    status          Show current Kumo runtime state

                    Usage:
                    kumo status [--json]

                    Options:
                    [--json] [--color <always|auto|never>]
                    [--loglevel <silent|error|warn|notice|http|info|verbose|silly>]

                    aliases: st

                    Run "kumo help status" for more info

    skills          Manage bundled Kumo agent skills

                    Usage:
                    kumo skills status [--agent <agent|all>] [--scope <global|project>] [--json]
                    kumo skills install [--agent <agent|all>] [--scope <global|project>] [--dry-run] [--force] [--json]
                    kumo skills uninstall [--agent <agent|all>] [--scope <global|project>] [--dry-run] [--json]

                    Options:
                    [--agent <cursor|claude|codex|gemini|agents|all>]
                    [--scope <global|project>] [--dry-run] [--force] [--json]

                    Run "kumo help skills" for more info
    """

    static let completion = """
    Tab Completion for kumo

    Usage:
    kumo completion <zsh|bash|fish>

    Examples:
    kumo completion zsh > ~/.zsh/completions/_kumo
    kumo completion bash > /usr/local/etc/bash_completion.d/kumo
    """

    static func topic(_ terms: [String]) -> String {
        let key = terms.joined(separator: " ")
        switch key {
        case "", "kumo":
            return topLevel
        case "json":
            return """
            Kumo JSON output

            Usage:
            kumo <command> --json

            Successful commands write:
            {
              "data": {},
              "error": null,
              "ok": true
            }

            Failed commands write:
            {
              "data": null,
              "error": "message",
              "ok": false
            }

            JSON output is written to stdout. Human-readable errors are written to stderr only when --json is not used.
            Exit code 0 means success. Exit code 1 means failure.
            """
        case "skills", "skills install":
            return """
            Install bundled Kumo agent skills

            Usage:
            kumo skills install [--agent <agent|all>] [--scope <global|project>] [--dry-run] [--force] [--json]

            Options:
            [--agent <cursor|claude|codex|gemini|agents|all>]
            [--scope <global|project>]
            [--dry-run]
            [--force]
            [--json]

            alias: add

            Run "kumo help skills install" for more info
            """
        default:
            return "No detailed help found for \(key).\nRun \"kumo --help\" for more info."
        }
    }
}

enum CompletionScripts {
    static func script(for shell: CompletionShell) -> String {
        switch shell {
        case .zsh:
            return """
            #compdef kumo
            # Generated completion script for kumo
            _arguments '1: :((status start stop restart mode proxies proxy select logs connections providers runtime-events doctor config c backup core profile sysproxy service tun substore skills completion help))'
            """
        case .bash:
            return """
            # Generated completion script for kumo
            complete -W "status start stop restart mode proxies proxy select logs connections providers runtime-events doctor config c backup core profile sysproxy service tun substore skills completion help" kumo
            """
        case .fish:
            return """
            # Generated completion script for kumo
            complete -c kumo -f -a "status start stop restart mode proxies proxy select logs connections providers runtime-events doctor config c backup core profile sysproxy service tun substore skills completion help"
            """
        }
    }
}
