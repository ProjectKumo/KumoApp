# CLI and Agent Control

## Purpose

The `kumo` executable provides a stable control surface for humans, shell scripts, and coding agents. It uses the same `KumoCoreKit` facade as the SwiftUI app.

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
```

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

- Add shell completion.
- Add JSON schemas for automation consumers.
