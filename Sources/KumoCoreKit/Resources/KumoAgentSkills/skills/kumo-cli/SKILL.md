---
name: kumo-cli
description: Drive Kumo from coding agents and automation through the `kumo` command-line interface. Use when starting, stopping, inspecting, configuring, or troubleshooting Kumo, Mihomo runtime state, profiles, proxies, system proxy, TUN, service mode, or Kumo agent skill installation.
---

# Kumo CLI

## Quick Start

Run `kumo doctor --json` first when diagnosing state. Use `--json` whenever parsing output.
Use the installed `kumo` command, which should resolve to `/usr/local/bin/kumo`
and then to `Kumo.app/Contents/Helpers/kumo`. `swift run kumo` is only for
source-tree development checks.

## When to Use

- Control Kumo lifecycle, mode, profiles, proxies, system proxy, TUN, or service mode.
- Inspect current runtime state before changing configuration.
- Install, update, or inspect Kumo's bundled agent skills.

## Output Contract

- JSON responses use `{ "ok": true|false, "data": ..., "error": ... }` and
  always include all three keys.
- Exit code `0` means success.
- Exit code `1` means failure; read `error` when `ok` is false.
- Prefer stable command names and JSON fields over parsing human-readable output.
- `--json` stdout is always plain JSON with no ANSI color, progress, or logs.
- Diagnostics and log output go to stderr in text mode.

## Discoverability

- `kumo --help` or `kumo -h` shows common commands.
- `kumo -l` shows long command usage.
- `kumo <command> -h` and `kumo help <term>` show focused help.
- `kumo completion zsh|bash|fish` emits shell completion scripts.

## Command Workflow

1. Start with `kumo doctor --json` for a broad snapshot.
2. Use focused read commands such as `kumo status --json`, `kumo proxies --json`, or `kumo service status --json`.
3. Use `--dry-run` before commands that can change macOS settings or installed skills.
4. After a write command, re-run the narrow status command to verify the result.

## Skill Installation Commands

- `kumo skills status --json`
- `kumo skills status --agent cursor --json`
- `kumo skills install --agent codex --dry-run --json`
- `kumo skills install --agent all --scope global --json`
- `kumo skills uninstall --agent cursor --scope global --dry-run --json`

Supported agents are `cursor`, `claude`, `codex`, `gemini`, `agents`, and `all` where documented.
`codex` and `gemini` do not support project scope.

## Logging Commands

- `kumo logs path`
- `kumo logs cli --limit 5`
- `kumo logs clean --dry-run --json`

Use `--loglevel <silent|error|warn|notice|http|info|verbose|silly>` to adjust
diagnostic verbosity. Prefer `--silent --json` for automation that only needs
machine-readable results.

## Safety Rules

- Do not edit generated runtime YAML unless the user explicitly asks for raw file changes.
- Prefer `kumo` or the Kumo app over direct writes to Kumo state files.
- Do not pass `--force` to skill installation unless the user intends to replace an existing skill directory.
- When working inside the Kumo repository, use `docs/interfaces/cli-agent-control.md` for the detailed CLI contract.
