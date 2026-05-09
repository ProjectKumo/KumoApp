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
    profiles-metadata.json
    current.txt
  overrides/
    overrides.json
    files/
  work/
    config.yaml
  logs/
    core.log
    substore.log
  cores/
    mihomo
  substore/
    status.json
    backend/
    frontend/
  state.json
  preferences.json
```

## Backup Format

Kumo can export a directory backup containing:

- `manifest.json`
- `profiles/`
- `overrides/`
- `substore/`
- `state.json`

The first backup format is directory-based rather than zip-based so it remains
transparent, testable, and easy for agents to inspect. A future UI can wrap the
same manifest in a compressed archive or sync it to WebDAV without changing the
CoreKit import/export contract.

## State File

`state.json` stores `CoreStatus`:

- core run state
- process identifier
- outbound mode
- controller endpoint
- mixed proxy port
- system proxy state (including PAC `mode` and `pacScript`)
- controlled runtime settings
- last status message

This allows the CLI and GUI to share state without requiring a service in v1.

## User Preferences

`preferences.json` stores `UserPreferences` (UI lifecycle preferences that do
not affect Mihomo runtime):

- `launchAtLogin` — synced with `SMAppService.mainApp` by `KumoAppDelegate`.
- `hideMenuBarIcon` — persisted; runtime hide requires future
  `NSStatusItem` migration (`MenuBarExtra` Scene cannot toggle visibility).
- `quitOnLastWindowClose` — read by
  `applicationShouldTerminateAfterLastWindowClosed`.
- `updateChannel` (`stable` / `beta`) and `updateManifestURL` — feed
  `AppUpdateManager.checkForUpdate(...)`.

Decoding falls back to defaults so a missing or corrupted file never blocks
launch.

## Sub-Store

`substore/status.json` (`SubStoreStatus`) stores enable flag, custom backend
URL, downloaded bundle paths, and configured ports. `SubStoreSupervisor`
launches the backend Process when Sub-Store is enabled and tees stdout +
stderr into `logs/substore.log`. Stopping Sub-Store terminates the process
and closes the log handle.

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

Sub-Store backend stdout and stderr are appended to:

```text
logs/substore.log
```

Each Sub-Store launch writes a header line (`[ISO timestamp] starting <executable> <args>`) so log readers can split sessions easily.

The main UI intentionally does not expose full logs on the Overview screen. Full log inspection belongs in the `Logs` destination under `Inspect`. The `Sub-Store` settings page surfaces a "View Logs" button that opens `logs/substore.log` in the user's text editor.

Live Mihomo logs should be treated as an event stream with a bounded in-memory cache. The local `core.log` file remains a fallback and diagnostic artifact.

## Overrides

Overrides are planned under:

```text
overrides/
  overrides.json
  files/
    <id>.yaml
    <id>.js
    <id>.log
```

YAML overrides are applied before Kumo-controlled runtime settings. JavaScript overrides require a reviewed sandbox before they are enabled.

## Future Work

- Rotate logs.
- Add separate app and service logs.
- Add structured JSONL event logs for agents.
- Add `kumo logs` and `kumo doctor`.
- Add privacy review for logs before sharing diagnostics.
- Add log rotation and Sub-Store log retention controls.
