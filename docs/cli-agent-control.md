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
- Exit code `0` means success.
- Exit code `1` means the command failed and `error` explains why.
- Command names should remain stable even if implementation moves to a service later.

## Shared Control Layer

The CLI must not bypass `KumoCoreKit`. If the app later introduces `KumoService`, the CLI should switch to service-backed calls while keeping command names and JSON schemas compatible.

## Future Work

- Add shell completion.
- Add `kumo logs`.
- Add `kumo doctor`.
- Add `kumo config path`.
- Add JSON schemas for automation consumers.
