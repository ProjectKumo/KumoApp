# CLI and Agent Control

## Purpose

The `kumo` executable provides a stable control surface for humans, shell scripts, and coding agents. It uses the same `KumoCoreKit` facade as the SwiftUI app.

## Installing `kumo` on PATH

`Kumo.app/Contents/Helpers/kumo` ships with the app bundle (`Helpers/` rather
than `MacOS/` so the CLI does not collide with the GUI's case-insensitive
`Contents/MacOS/Kumo`). The recommended install path is the first-run
onboarding sheet (also reachable via Settings > General > Command Line Tool),
which symlinks the bundled binary to `/usr/local/bin/kumo` after a one-time
macOS administrator authorization prompt. The same flow is wrapped by
`KumoController.cliLinkStatus()` / `installCLILink()` / `uninstallCLILink()`
for programmatic use. Manual `ln -s` is supported but no longer required for
new installs.

`swift run kumo` is only a source-tree development smoke test. User-facing
installs must be validated through the bundled helper binary and, when
installed, the `/usr/local/bin/kumo` symlink that points at it.

## Command Design

Commands are intentionally close to user goals:

```bash
kumo status --json
kumo start --core /path/to/mihomo
kumo stop
kumo restart
kumo mode rule
kumo mode global
kumo mode direct
kumo proxies --json
kumo select "Proxy" "HK-01"
kumo profile refresh "https://example.com/sub.yaml"
kumo sysproxy on --dry-run --json
kumo service status --json
kumo service install
kumo tun enable --json
kumo substore status --json
kumo skills status --json
kumo skills install --agent codex --dry-run --json
kumo completion zsh
kumo logs cli --limit 5
```

## CLI Interaction Conventions

Kumo follows the parts of npm's CLI interaction model that make command-line
tools discoverable and scriptable:

- `kumo --help` / `kumo -h` shows common tasks, all command names, and next-step
  help prompts.
- `kumo -l` / `kumo --long` expands command descriptions, usage, options, and
  aliases.
- `kumo <command> -h` and `kumo help <term>` provide command-level help.
- `kumo --version` prints only the version string.
- `kumo completion <zsh|bash|fish>` writes a shell completion script to stdout.
- Conservative aliases are allowed for low-risk read paths: `status` → `st`,
  `proxies` → `proxy`, and `config` → `c`.
- Commands that can write system or user state should support `--dry-run` where
  a meaningful preview is possible.

## Output Modes

The default output is readable text. `--json` returns a stable wrapper:

```json
{
  "ok": true,
  "data": {},
  "error": null
}
```

Errors use the same wrapper with `ok: false`.

`--json` output is always plain JSON on stdout. It must not include ANSI escape
codes, progress text, warnings, or diagnostic logs. Human-readable diagnostics
go to stderr in text mode.

## Terminal Rendering

Text mode uses light ANSI styling only when stdout/stderr are interactive TTYs.
Rendering is disabled when output is piped or redirected, when `--json` is used,
when `NO_COLOR` is set, when `CLICOLOR=0`, or when `--color never` is passed.
`--color always|auto|never` defaults to `auto`.

Visible status labels are ASCII so color is never the only signal:

- `[ok]` for healthy success.
- `[warn]` for warnings or partial readiness.
- `[error]` for failures.
- `[dry-run]` for previews.

## CLI Logging

Kumo uses npm-style log controls:

- `--loglevel <silent|error|warn|notice|http|info|verbose|silly>` controls
  terminal diagnostics. The default is `notice`.
- `--silent` is equivalent to `--loglevel silent`; `--verbose` is equivalent to
  `--loglevel verbose`; `-d` is equivalent to `--loglevel info`.
- Normal command results are written to stdout. Logs, warnings, progress, timing
  output, and diagnostics are written to stderr.
- `--logs-dir <path>` overrides the CLI debug log directory. By default CLI logs
  live under `logs/cli/`.
- `--logs-max <count>` limits retained CLI debug logs. `--logs-max=0` disables
  debug log files.
- `--timing` writes a process-specific timing JSON file and may print a timing
  summary to stderr in text mode.
- Logs redact profile URL tokens, controller secrets, authorization headers,
  basic auth passwords, and similar credentials before writing terminal or file
  output.

`kumo logs` has two log surfaces:

- `kumo logs [runtime] [--limit <count>] [--level <level>] [--json]` shows
  Mihomo/runtime logs.
- `kumo logs cli [--limit <count>] [--level <level>] [--json]` shows Kumo CLI
  debug log summaries.
- `kumo logs path` prints the logs directory.
- `kumo logs clean [--dry-run] [--json]` cleans old CLI debug and timing logs.

## Agent-Friendly Behavior

Agent workflows need predictable behavior:

- `--json` should be supported for every command.
- Dry-run should be available for commands that change system settings.
- Agent skill installation should use `kumo skills ... --dry-run` before writing
  into user or project agent skill directories.
- Exit code `0` means success.
- Exit code `1` means the command failed and `error` explains why.
- Command names should remain stable even if implementation moves to a service later.

## Agent Skills

`kumo skills` installs the bundled `kumo-cli` Agent Skill into supported coding
agent skill directories. The CLI and macOS Integrations UI both use the same
`KumoCoreKit` target mapping and install state.

Supported agents:

- `cursor` → `~/.cursor/skills` globally, `.cursor/skills` for project scope.
- `claude` → `~/.claude/skills` globally, `.claude/skills` for project scope.
- `codex` → `$CODEX_HOME/skills` or `~/.codex/skills` globally.
- `gemini` → `~/.gemini/skills` globally.
- `agents` → `~/.agents/skills` globally, `.agents/skills` for project scope.
- `all` → every target supported by the selected scope.

Commands:

```bash
kumo skills status [--agent <cursor|claude|codex|gemini|agents|all>] [--scope <global|project>] [--json]
kumo skills install [--agent <cursor|claude|codex|gemini|agents|all>] [--scope <global|project>] [--dry-run] [--force] [--json]
kumo skills uninstall [--agent <cursor|claude|codex|gemini|agents|all>] [--scope <global|project>] [--dry-run] [--json]
```

Install is non-destructive by default. If a destination skill directory already
exists and was not recorded as installed by Kumo, the command fails unless the
caller explicitly passes `--force`.

`codex` and `gemini` do not support project scope. `--agent all --scope project`
targets only agents with project-scope support.

## App Intents (GUI surface)

The macOS app additionally exposes the following App Intents (via
`KumoIntents.swift`) so Shortcuts, Siri, and Spotlight can drive Kumo
without spawning a CLI process:

- `Start Kumo`
- `Stop Kumo`
- `Refresh Kumo`
- `Set Kumo Mode` (parameter: `KumoModeChoice` ↔ `OutboundMode`)
- `Toggle Kumo System Proxy` (parameter: `enable: Bool`)

App Intents call back into the live `KumoAppStore`, so their effects are
identical to triggering the same flow from the GUI. They require the
`Kumo.app` bundle (not `swift run`).

## Shared Control Layer

The CLI must not bypass `KumoCoreKit`. When `KumoService` is installed and
reachable, the same commands switch to service-backed calls while keeping
command names and JSON schemas compatible:

- `kumo start|stop|restart` delegates Mihomo lifecycle to the helper.
- `kumo sysproxy on|off` delegates protected system proxy changes to the helper
  unless `--dry-run` is used.
- `kumo tun enable|disable` delegates TUN state changes to the helper and fails
  clearly when no helper or privileged process can manage `utun`.
- `kumo service install|uninstall|status` reports LaunchDaemon/socket state and
  uses macOS administrator authorization for install and uninstall.
- `kumo substore status|prepare|start|stop|restart` manages bundled Sub-Store
  resources and the same local lifecycle used by the SwiftUI app.

App Intents follow the same rule: when service mode lands, intents should
hit service endpoints rather than `KumoAppStore` directly so they keep
working when the GUI is closed.

## Future Work

- Add JSON schemas for automation consumers.
