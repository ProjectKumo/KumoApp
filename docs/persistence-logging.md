# Persistence and Logging

## Application Support Directory

Kumo stores local state under:

```text
~/Library/Application Support/Kumo/
```

`KumoPaths` centralizes all paths so GUI, CLI, tests, and future service code use the same layout.

## Directory Layout

```text
Kumo/
  profiles/
    default.yaml
  work/
    config.yaml
  logs/
    core.log
  state.json
```

## State File

`state.json` stores `CoreStatus`:

- core run state
- process identifier
- outbound mode
- controller endpoint
- mixed proxy port
- system proxy state
- last status message

This allows the CLI and GUI to share state without requiring a service in v1.

## Runtime Configuration

The generated Mihomo runtime configuration is written to:

```text
work/config.yaml
```

Mihomo is launched with the work directory so it reads the generated config.

## Logs

Core stdout and stderr are appended to:

```text
logs/core.log
```

The main UI intentionally does not expose full logs on the Overview screen. Full log inspection belongs in Advanced.

## Future Work

- Rotate logs.
- Add separate app and service logs.
- Add structured JSONL event logs for agents.
- Add `kumo logs` and `kumo doctor`.
- Add privacy review for logs before sharing diagnostics.
